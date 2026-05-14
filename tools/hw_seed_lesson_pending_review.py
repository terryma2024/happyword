#!/usr/bin/env python3
"""Happyword ops: import a lesson photo, trigger extraction cron, aim for `pending`.

Mirrors ``server/tests/e2e/test_lesson_import_cron_e2e.py`` (fast import +
authorized ``extract-pending`` tick). Use for smoke-testing a Preview URL.

Run via repo wrapper so ``httpx`` resolves::

    bash tools/hw_seed_lesson_pending_review.sh \\
      --base-url https://happyword-xxxx.vercel.app \\
      --family-id fam-01234567

Bypass secret resolution (first non-empty):
  ``HW_VERCEL_BYPASS``, ``E2E_VERCEL_PROTECTION_BYPASS``, ``VERCEL_AUTOMATION_BYPASS_SECRET``

Cron secret resolution:
  ``HW_CRON_SECRET``, ``E2E_CRON_SECRET``, ``VERCEL_CRON_SECRET``, ``CRON_SECRET``

``--family-id`` selects the ``{family_id}`` path segment for
``/api/v1/family/{family_id}/lessons/import`` and matching draft reads
(decorative on the server until drafts are family-scoped).
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

import httpx

_CRON_PATH = "/api/v1/admin/cron/extract-pending"


def _family_path_segment(family_id: str) -> str:
    s = (family_id or "").strip()
    return s if s else "_"


def _import_path(family_id: str) -> str:
    return f"/api/v1/family/{_family_path_segment(family_id)}/lessons/import"


def _draft_path(family_id: str, draft_id: str) -> str:
    return f"/api/v1/family/{_family_path_segment(family_id)}/lesson-drafts/{draft_id}"


def _strip(name: str) -> str:
    return os.environ.get(name, "").strip()


def _first_secret(*names: str) -> str:
    for n in names:
        v = _strip(n)
        if v:
            return v
    return ""


def _bypass_headers() -> dict[str, str]:
    secret = _first_secret(
        "HW_VERCEL_BYPASS",
        "E2E_VERCEL_PROTECTION_BYPASS",
        "VERCEL_AUTOMATION_BYPASS_SECRET",
    )
    if not secret:
        return {}
    return {"x-vercel-protection-bypass": secret}


def _cron_secret() -> str:
    return _first_secret(
        "HW_CRON_SECRET",
        "E2E_CRON_SECRET",
        "VERCEL_CRON_SECRET",
        "CRON_SECRET",
    )


def _default_fixture_path(repo_root: Path) -> Path:
    return (
        repo_root
        / "server"
        / "tests"
        / "e2e"
        / "_fixtures"
        / "lesson_import_fixture.jpg"
    )


def main() -> int:
    repo_root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(
        description="POST lesson import + trigger extract-pending cron on a deployed API.",
    )
    parser.add_argument(
        "--base-url",
        required=True,
        help=(
            "Deployment origin, e.g. https://happyword-xxxx.vercel.app "
            "(no trailing slash needed)."
        ),
    )
    parser.add_argument(
        "--family-id",
        default="",
        help=(
            "Family path segment for /api/v1/family/{family_id}/… lesson routes "
            "(use real fam-… when mirroring a device; default `_` when omitted)."
        ),
    )
    parser.add_argument(
        "--image",
        type=Path,
        default=None,
        help=f"JPEG/PNG/WebP path (default: {_default_fixture_path(repo_root)}).",
    )
    parser.add_argument(
        "--skip-cron",
        action="store_true",
        help="Only run POST /lessons/import (draft stays extracting until cron runs).",
    )
    args = parser.parse_args()

    base = args.base_url.strip().rstrip("/")
    if not base.startswith("http"):
        base = "https://" + base

    img_path = args.image or _default_fixture_path(repo_root)
    if not img_path.is_file():
        print(f"error: image not found: {img_path}", file=sys.stderr)
        return 2

    bypass = _bypass_headers()
    if not bypass:
        print(
            "warning: no Vercel bypass header — Preview deployments may return 401 "
            "(set HW_VERCEL_BYPASS or VERCEL_AUTOMATION_BYPASS_SECRET).",
            file=sys.stderr,
        )

    mime = "image/jpeg"
    suf = img_path.suffix.lower()
    if suf in {".png"}:
        mime = "image/png"
    elif suf in {".webp"}:
        mime = "image/webp"

    headers = dict(bypass)
    timeout = httpx.Timeout(60.0)

    with httpx.Client(
        base_url=base,
        headers=headers,
        timeout=timeout,
        follow_redirects=False,
    ) as http:
        health = http.get("/api/v1/public/health")
        if health.status_code != 200:
            print(
                f"error: GET /api/v1/public/health -> {health.status_code}\n{health.text[:500]}",
                file=sys.stderr,
            )
            return 1

        img_bytes = img_path.read_bytes()
        import_path = _import_path(args.family_id)
        resp = http.post(
            import_path,
            files={"image": (img_path.name, img_bytes, mime)},
        )
        if resp.status_code != 201:
            print(
                f"error: POST {import_path} -> {resp.status_code}\n{resp.text[:2000]}",
                file=sys.stderr,
            )
            return 1

        draft = resp.json()
        draft_id = draft["id"]
        out: dict[str, object] = {
            "base_url": base,
            "operator": {"family_id": _family_path_segment(args.family_id)},
            "import": {"draft_id": draft_id, "status": draft.get("status")},
        }

        if args.skip_cron:
            print(json.dumps(out, indent=2))
            print(
                "notice: skipped cron — draft remains `extracting` until scheduled/manual cron.",
                file=sys.stderr,
            )
            return 0

        cron_s = _cron_secret()
        if not cron_s:
            print(
                "error: cron secret missing — set HW_CRON_SECRET "
                "(or E2E_CRON_SECRET / CRON_SECRET).",
                file=sys.stderr,
            )
            return 1

        cron = http.post(
            _CRON_PATH,
            headers={"Authorization": f"Bearer {cron_s}"},
        )
        if cron.status_code != 200:
            print(
                f"error: POST {_CRON_PATH} -> {cron.status_code}\n{cron.text[:2000]}",
                file=sys.stderr,
            )
            return 1

        summary = cron.json()
        out["cron"] = summary

        fetched = http.get(_draft_path(args.family_id, draft_id))
        if fetched.status_code != 200:
            print(
                f"error: GET draft -> {fetched.status_code}\n{fetched.text[:2000]}",
                file=sys.stderr,
            )
            return 1

        fd = fetched.json()
        out["draft"] = {
            "id": fd.get("id"),
            "status": fd.get("status"),
            "extract_attempts": fd.get("extract_attempts"),
        }

        print(json.dumps(out, indent=2))

        status = fd.get("status")
        if status == "pending":
            return 0
        if status == "extract_failed":
            print(
                "error: extraction failed — check extract_last_error_* on deployment / Mongo.",
                file=sys.stderr,
            )
            return 1
        print(f"warning: unexpected draft status after cron: {status!r}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
