#!/usr/bin/env python3
"""parity_scout CLI entry point.

See docs/superpowers/specs/2026-05-13-parity-scout-design.md for the design.
Subcommands: plan, pick, run, promote, doctor, prune.
"""

from __future__ import annotations

import argparse
import atexit
import datetime as _dt
import errno
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Sequence

# When run as `python3 tools/parity_scout/scout.py ...`, the parent of the
# package (i.e. `tools/`) must be on sys.path so that `import parity_scout.X`
# resolves. Tests rely on pytest's `pythonpath = [".."]` instead.
_PKG_PARENT = Path(__file__).resolve().parents[1]
if str(_PKG_PARENT) not in sys.path:
    sys.path.insert(0, str(_PKG_PARENT))

from parity_scout.planner import build_plan, render_tree  # noqa: E402
from parity_scout.registry import load_registry  # noqa: E402
from parity_scout.spec_extract import ScopeError, resolve_scope  # noqa: E402


_REPO_ROOT = Path(__file__).resolve().parents[2]
_DEFAULT_REGISTRY = Path(__file__).resolve().parent / "page_suite_map.yml"
_RUN_ROOT = _REPO_ROOT / "build-tmp" / "parity_scout"
_LOCK_PATH = _RUN_ROOT / ".lock"


def _pid_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except OSError as exc:
        return exc.errno == errno.EPERM
    return True


def _release_lock() -> None:
    try:
        if _LOCK_PATH.exists():
            # Only remove the lock if it still belongs to us; otherwise leave
            # alone so a concurrent owner is not surprised by deletion.
            content = _LOCK_PATH.read_text(encoding="utf-8").strip()
            try:
                pid = int(content)
            except ValueError:
                pid = -1
            if pid == os.getpid():
                _LOCK_PATH.unlink()
    except OSError:
        pass


def _acquire_lock() -> bool:
    _RUN_ROOT.mkdir(parents=True, exist_ok=True)
    if _LOCK_PATH.exists():
        try:
            pid = int(_LOCK_PATH.read_text(encoding="utf-8").strip())
        except (ValueError, OSError):
            pid = None
        if pid and _pid_alive(pid):
            return False
        try:
            _LOCK_PATH.unlink()
        except OSError:
            return False
    _LOCK_PATH.write_text(str(os.getpid()), encoding="utf-8")
    atexit.register(_release_lock)
    return True


def _build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="scout.py")
    sub = p.add_subparsers(dest="cmd", required=True)

    plan_p = sub.add_parser("plan")
    scope = plan_p.add_mutually_exclusive_group(required=True)
    scope.add_argument("--scope", choices=["overall"])
    scope.add_argument("--spec", type=Path)
    scope.add_argument("--feature", type=Path)
    scope.add_argument("--pages")
    scope.add_argument("--suite")
    scope.add_argument("--describe")
    plan_p.add_argument("--registry", type=Path, default=_DEFAULT_REGISTRY)
    plan_p.add_argument("--run", default=None, help="Reuse an existing run id.")

    pick_p = sub.add_parser("pick")
    pick_p.add_argument("--run", required=True)
    pick_p.add_argument(
        "--branches",
        required=True,
        help='Comma-separated page ids, or "all".',
    )
    pick_p.add_argument("--include-blocked", action="store_true")

    run_p = sub.add_parser("run")
    run_p.add_argument("--run", required=True)
    run_p.add_argument(
        "--only",
        default=None,
        help="Comma-separated subset of already-picked pages.",
    )
    run_p.add_argument("--leaf-timeout", type=int, default=180)
    run_p.add_argument("--allow-dirty-baseline", action="store_true")
    run_p.add_argument("--registry", type=Path, default=_DEFAULT_REGISTRY)

    sub.add_parser("promote")
    sub.add_parser("doctor")
    sub.add_parser("prune")

    return p


def _slugify(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-") or "scope"


def _build_run_id(scope_kind: str, scope_value: str | None) -> str:
    ts = _dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    raw = f"{ts}-{scope_kind}-{_slugify(scope_value or '')}"
    return raw[:80].rstrip("-")


def _cmd_plan(args: argparse.Namespace) -> int:
    if args.scope == "overall":
        kind, value = "overall", None
    elif args.spec is not None:
        kind, value = "spec", str(args.spec)
    elif args.feature is not None:
        kind, value = "feature", str(args.feature)
    elif args.pages is not None:
        kind, value = "pages", args.pages
    elif args.suite is not None:
        kind, value = "suite", args.suite
    elif args.describe is not None:
        kind, value = "describe", args.describe
    else:
        print("scope flag required", file=sys.stderr)
        return 2

    try:
        reg = load_registry(args.registry)
        page_ids = resolve_scope(reg, kind=kind, value=value)
    except ScopeError as exc:
        print(f"scope error: {exc}", file=sys.stderr)
        return 2

    if not page_ids:
        print("no leaves resolved (scope too narrow / unmatched)", file=sys.stderr)
        return 2

    run_id = args.run or _build_run_id(kind, value)
    run_dir = _RUN_ROOT / run_id
    run_dir.mkdir(parents=True, exist_ok=True)
    plan = build_plan(
        reg,
        page_ids=page_ids,
        run_id=run_id,
        scope_kind=kind,
        scope_value=value,
    )
    (run_dir / "plan.json").write_text(plan.to_json() + "\n", encoding="utf-8")
    print(render_tree(plan))
    print(f"\nrun-id: {run_id}")
    print(f"plan:   {run_dir / 'plan.json'}")
    return 0


def _cmd_pick(args: argparse.Namespace) -> int:
    run_dir = _RUN_ROOT / args.run
    plan_path = run_dir / "plan.json"
    if not plan_path.is_file():
        print(f"no plan at {plan_path}", file=sys.stderr)
        return 4
    plan = json.loads(plan_path.read_text(encoding="utf-8"))
    leaves_by_id = {leaf["page_id"]: leaf for leaf in plan["leaves"]}

    if args.branches.strip() == "all":
        requested = list(leaves_by_id.keys())
    else:
        requested = [b.strip() for b in args.branches.split(",") if b.strip()]

    chosen: list[str] = []
    refused: list[tuple[str, str]] = []
    for pid in requested:
        leaf = leaves_by_id.get(pid)
        if leaf is None:
            refused.append((pid, "not-in-plan"))
            continue
        statuses = [leaf[p]["status"] for p in ("harmony", "ios", "android")]
        if all(s == "feature_absent" for s in statuses):
            refused.append((pid, "all-feature-absent"))
            continue
        if "blocked" in statuses and not args.include_blocked:
            refused.append((pid, "blocked-without-include-blocked"))
            continue
        chosen.append(pid)

    if not chosen:
        for pid, reason in refused:
            print(f"refused: {pid} ({reason})", file=sys.stderr)
        return 4

    out = {"run_id": args.run, "branches": chosen, "refused": refused}
    (run_dir / "picked.json").write_text(
        json.dumps(out, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print(f"picked: {', '.join(chosen)}")
    if refused:
        for pid, reason in refused:
            print(f"refused: {pid} ({reason})")
    return 0


def _baseline_clean() -> bool:
    try:
        head = subprocess.run(
            ["git", "rev-parse", "--abbrev-ref", "HEAD"],
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip()
        dirty = subprocess.run(
            ["git", "status", "--porcelain", "harmonyos/entry/src/main/ets"],
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip()
    except Exception:
        return False
    return head == "main" and dirty == ""


def _baseline_sha() -> str:
    try:
        return subprocess.run(
            ["git", "rev-parse", "HEAD"],
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip()
    except Exception:
        return "unknown"


def _cmd_run(args: argparse.Namespace) -> int:
    from parity_scout.adapters.android import AndroidAdapter
    from parity_scout.adapters.harmony import HarmonyAdapter
    from parity_scout.adapters.ios import IosAdapter
    from parity_scout.runner import Runner

    run_dir = _RUN_ROOT / args.run
    if not (run_dir / "picked.json").is_file():
        print(f"no picked.json at {run_dir}", file=sys.stderr)
        return 4
    if not _acquire_lock():
        print(
            f"another parity_scout run is in progress (lock {_LOCK_PATH}); "
            "wait for it or rm the lock if you know it's stale",
            file=sys.stderr,
        )
        return 4
    if not args.allow_dirty_baseline and not _baseline_clean():
        print(
            "HarmonyOS baseline is not on a clean main; pass "
            "--allow-dirty-baseline to bypass",
            file=sys.stderr,
        )
        return 4
    (run_dir / "baseline.txt").write_text(_baseline_sha() + "\n", encoding="utf-8")

    reg = load_registry(args.registry)

    # If --only filters the picked branches, rewrite picked.json for this run.
    if args.only:
        wanted = {p.strip() for p in args.only.split(",") if p.strip()}
        picked = json.loads((run_dir / "picked.json").read_text(encoding="utf-8"))
        picked["branches"] = [b for b in picked["branches"] if b in wanted]
        (run_dir / "picked.json").write_text(
            json.dumps(picked, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )

    capture_specs: dict[str, dict[str, dict]] = {}
    for page in reg.pages:
        capture_specs[page.id] = {
            "harmony": page.harmony.capture.raw if page.harmony.capture else {},
            "ios": page.ios.capture.raw if page.ios.capture else {},
            "android": page.android.capture.raw if page.android.capture else {},
        }

    plan_json = json.loads((run_dir / "plan.json").read_text(encoding="utf-8"))
    scope = plan_json.get("scope") or {}
    spec_path: Path | None = None
    if scope.get("kind") == "spec" and scope.get("value"):
        spec_path = Path(scope["value"])
    elif scope.get("kind") == "feature" and scope.get("value"):
        feat = Path(scope["value"])
        if feat.is_dir():
            mds = sorted(feat.glob("*.md"))
            spec_path = mds[0] if mds else None

    adapters = {
        "harmony": HarmonyAdapter(),
        "ios": IosAdapter(),
        "android": AndroidAdapter(),
    }
    runner = Runner(
        run_dir,
        adapters,
        capture_specs,
        leaf_timeout=args.leaf_timeout,
        spec_path=spec_path,
        registry=reg,
    )
    for ev in runner.iter_events():
        if ev.kind == "LEAF_START":
            print(f"LEAF START page={ev.page_id}", flush=True)
        elif ev.kind == "LEAF_READY":
            print(f"LEAF READY page={ev.page_id} dir={ev.dir}", flush=True)
        elif ev.kind == "RUN_DONE":
            print("RUN DONE", flush=True)
    return 0


def main(argv: Sequence[str] | None = None) -> int:
    args = _build_parser().parse_args(argv)
    if args.cmd == "plan":
        return _cmd_plan(args)
    if args.cmd == "pick":
        return _cmd_pick(args)
    if args.cmd == "run":
        return _cmd_run(args)
    print(f"NOT IMPLEMENTED: {args.cmd}", file=sys.stderr)
    return 64


if __name__ == "__main__":
    raise SystemExit(main())
