#!/usr/bin/env python3
"""Preview client/server debug helper.

Reads local secrets from ~/.env without echoing them. The script intentionally
keeps DB access read-only and route-driven so debug sessions can be repeated
without leaking tokens into terminal transcripts.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_MANIFEST_URL = "https://happyword.cool/api/v1/preview-urls.json"
DEBUG_HEADER = "x-hw-debug-session"
ALLOWLIST_COLLECTIONS = {
    "debug_sessions",
    "debug_traces",
    "device_bindings",
    "child_profiles",
    "families",
    "family_pack_pointers",
    "family_word_packs",
    "synced_word_stats",
    "cloud_wishlist_items",
    "redemption_requests",
}
SENSITIVE_HINTS = ("SECRET", "TOKEN", "KEY", "PASS", "PASSWORD", "URI", "JWT")


def load_env(path: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    if not path.exists():
        return out
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key:
            out[key] = value
    return out


def merged_env(env_file: Path) -> dict[str, str]:
    values = load_env(env_file)
    values.update({k: v for k, v in os.environ.items() if v})
    return values


def public_env_summary(env: dict[str, str]) -> dict[str, bool]:
    keys = [
        "VERCEL_TOKEN",
        "VERCEL_PROJECT_ID",
        "VERCEL_ORG_ID",
        "VERCEL_AUTOMATION_BYPASS_SECRET",
        "PREVIEW_DEBUG_SECRET",
        "E2E_MONGODB_URI",
        "MONGODB_URI",
    ]
    return {key: bool(env.get(key)) for key in keys}


def redact_value(value: Any) -> Any:
    if isinstance(value, dict):
        out: dict[str, Any] = {}
        for key, item in value.items():
            key_text = str(key)
            if any(hint.lower() in key_text.lower() for hint in SENSITIVE_HINTS):
                out[key_text] = "[redacted]"
            else:
                out[key_text] = redact_value(item)
        return out
    if isinstance(value, list):
        return [redact_value(item) for item in value]
    return value


def request_json(
    method: str,
    url: str,
    *,
    headers: dict[str, str] | None = None,
    payload: dict[str, Any] | None = None,
    timeout: int = 30,
) -> dict[str, Any]:
    body = None
    merged_headers = {"Accept": "application/json"}
    if headers:
        merged_headers.update(headers)
    if payload is not None:
        body = json.dumps(payload).encode("utf-8")
        merged_headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=body, headers=merged_headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read().decode("utf-8")
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as exc:
        raw = exc.read().decode("utf-8", errors="replace")
        raise SystemExit(f"HTTP {exc.code} from {url}: {raw[:300]}") from exc


def fetch_manifest(url: str, env: dict[str, str]) -> dict[str, Any]:
    headers: dict[str, str] = {}
    bypass = env.get("VERCEL_AUTOMATION_BYPASS_SECRET", "")
    if bypass:
        headers["x-vercel-protection-bypass"] = bypass
    return request_json("GET", url, headers=headers)


def resolve_preview(args: argparse.Namespace, env: dict[str, str]) -> dict[str, Any]:
    manifest = fetch_manifest(args.manifest_url, env)
    previews = manifest.get("previews") or []
    for row in previews:
        if args.pr is not None and str(row.get("pr")) != str(args.pr):
            continue
        if args.branch and row.get("branch") != args.branch:
            continue
        if args.domain and args.domain.rstrip("/") not in {
            str(row.get("url", "")).rstrip("/"),
            str(row.get("branch_url", "")).rstrip("/"),
            str(row.get("deployment_url", "")).rstrip("/"),
        }:
            continue
        return row
    raise SystemExit("No matching preview in manifest")


def debug_headers(env: dict[str, str], session_id: str | None = None) -> dict[str, str]:
    secret = env.get("PREVIEW_DEBUG_SECRET", "")
    if not secret:
        raise SystemExit("PREVIEW_DEBUG_SECRET is not set in env or ~/.env")
    headers = {"Authorization": f"Bearer {secret}"}
    if session_id:
        headers[DEBUG_HEADER] = session_id
    return headers


def cmd_resolve(args: argparse.Namespace, env: dict[str, str]) -> None:
    row = resolve_preview(args, env)
    print(json.dumps(row, ensure_ascii=False, indent=2))


def cmd_create_session(args: argparse.Namespace, env: dict[str, str]) -> None:
    row = resolve_preview(args, env)
    base = (args.domain or row.get("branch_url") or row.get("url") or "").rstrip("/")
    payload = {
        "problem": args.problem,
        "preview_url": base,
        "branch": row.get("branch"),
        "deployment_id": row.get("deployment_id"),
        "created_by": args.created_by,
    }
    created = request_json(
        "POST",
        f"{base}/api/v1/debug/sessions",
        headers=debug_headers(env),
        payload=payload,
    )
    print(json.dumps(created, ensure_ascii=False, indent=2))
    print(f"\nClient header: {DEBUG_HEADER}: {created['session_id']}")


def cmd_stop_session(args: argparse.Namespace, env: dict[str, str]) -> None:
    base = args.base_url.rstrip("/")
    stopped = request_json(
        "POST",
        f"{base}/api/v1/debug/sessions/{args.session_id}/stop",
        headers=debug_headers(env),
    )
    print(json.dumps(stopped, ensure_ascii=False, indent=2))


def cmd_traces(args: argparse.Namespace, env: dict[str, str]) -> None:
    base = args.base_url.rstrip("/")
    traces = request_json(
        "GET",
        f"{base}/api/v1/debug/sessions/{args.session_id}/traces?limit={args.limit}",
        headers=debug_headers(env),
    )
    print(json.dumps(traces, ensure_ascii=False, indent=2))


def cmd_vercel_logs(args: argparse.Namespace, env: dict[str, str]) -> None:
    token = env.get("VERCEL_TOKEN", "")
    if not token:
        raise SystemExit("VERCEL_TOKEN is not set in env or ~/.env")
    command = [
        "vercel",
        "logs",
        args.url,
        "--environment",
        "preview",
        "--token",
        "<redacted>",
    ]
    print("Run this in a separate terminal while reproducing:")
    print(" ".join(command))
    if args.follow:
        real_command = ["vercel", "logs", args.url, "--environment", "preview", "--token", token]
        subprocess.run(real_command, check=False)


def cmd_mongo_find(args: argparse.Namespace, env: dict[str, str]) -> None:
    if args.collection not in ALLOWLIST_COLLECTIONS:
        allowed = ", ".join(sorted(ALLOWLIST_COLLECTIONS))
        raise SystemExit(f"Collection not allowlisted. Allowed: {allowed}")
    uri = env.get("E2E_MONGODB_URI") or env.get("MONGODB_URI") or env.get("MONGO_URI")
    db_name = args.db or env.get("E2E_MONGO_DB_NAME") or env.get("MONGO_DB_NAME")
    if not uri or not db_name:
        raise SystemExit("Mongo URI / DB name missing; set E2E_MONGODB_URI + E2E_MONGO_DB_NAME")
    try:
        from pymongo import MongoClient
    except ImportError as exc:
        raise SystemExit("pymongo is unavailable in this Python environment") from exc
    query = json.loads(args.query)
    projection = None if not args.projection else json.loads(args.projection)
    rows = list(
        MongoClient(uri)[db_name][args.collection]
        .find(query, projection)
        .limit(args.limit)
    )
    for row in rows:
        row["_id"] = str(row.get("_id"))
    print(json.dumps(redact_value(rows), ensure_ascii=False, indent=2, default=str))


def cmd_client_logs(args: argparse.Namespace, _env: dict[str, str]) -> None:
    if args.platform == "harmonyos":
        print('hdc hilog | rg "HW_NET_DEBUG|HW_PREVIEW_DEBUG|CloudSync|PreviewManifest"')
    elif args.platform == "android":
        print('$ANDROID_HOME/platform-tools/adb logcat -v time | rg "HW_NET_DEBUG|WordMagic"')
    else:
        print('xcrun simctl spawn booted log stream --style compact --predicate \'process == "WordMagicGame" AND (eventMessage CONTAINS "HW_NET_DEBUG" OR eventMessage CONTAINS "HW_PREVIEW_DEBUG")\'')


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Preview client/server debug helper")
    parser.add_argument("--env-file", default=str(Path.home() / ".env"))
    parser.add_argument("--manifest-url", default=DEFAULT_MANIFEST_URL)
    sub = parser.add_subparsers(dest="cmd", required=True)

    def add_target(p: argparse.ArgumentParser) -> None:
        p.add_argument("--pr", type=int)
        p.add_argument("--branch")
        p.add_argument("--domain")

    p = sub.add_parser("env-summary")
    p.set_defaults(func=lambda args, env: print(json.dumps(public_env_summary(env), indent=2)))

    p = sub.add_parser("resolve")
    add_target(p)
    p.set_defaults(func=cmd_resolve)

    p = sub.add_parser("create-session")
    add_target(p)
    p.add_argument("--problem", required=True)
    p.add_argument("--created-by", default="operator")
    p.set_defaults(func=cmd_create_session)

    p = sub.add_parser("stop-session")
    p.add_argument("--base-url", required=True)
    p.add_argument("--session-id", required=True)
    p.set_defaults(func=cmd_stop_session)

    p = sub.add_parser("traces")
    p.add_argument("--base-url", required=True)
    p.add_argument("--session-id", required=True)
    p.add_argument("--limit", type=int, default=200)
    p.set_defaults(func=cmd_traces)

    p = sub.add_parser("vercel-logs")
    p.add_argument("--url", required=True)
    p.add_argument("--follow", action="store_true")
    p.set_defaults(func=cmd_vercel_logs)

    p = sub.add_parser("mongo-find")
    p.add_argument("--collection", required=True)
    p.add_argument("--query", default="{}")
    p.add_argument("--projection", default="")
    p.add_argument("--db")
    p.add_argument("--limit", type=int, default=20)
    p.set_defaults(func=cmd_mongo_find)

    p = sub.add_parser("client-logs")
    p.add_argument("--platform", choices=["harmonyos", "android", "ios"], required=True)
    p.set_defaults(func=cmd_client_logs)
    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()
    env = merged_env(Path(args.env_file).expanduser())
    args.func(args, env)


if __name__ == "__main__":
    main()
