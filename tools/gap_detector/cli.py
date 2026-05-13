from __future__ import annotations

import argparse
import json
from collections.abc import Sequence
from pathlib import Path

from .manifest import Manifest, Probe, ScopeRecord, SourceRecord, load_manifest, save_manifest
from .runners.commands import commands_for_probe, execute_command
from .scope_planner import ScopePlanner


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="python3 -m tools.gap_detector",
        description="Plan, run, and classify three-platform parity gap probes.",
    )
    subcommands = parser.add_subparsers(dest="command", required=True)

    plan = subcommands.add_parser("plan", help="Create a scoped probe manifest")
    plan.add_argument("--scope", required=True, help="Feature/spec/plan/page/suite path or overall")
    plan.add_argument("--run-name", default="", help="Stable run name for artifact paths")

    run = subcommands.add_parser("run", help="Run one manifest probe")
    run.add_argument("--manifest", required=True, help="Path to manifest.yaml")
    run.add_argument("--probe", required=True, help="Probe id to run")
    run.add_argument("--execute", action="store_true", help="Execute platform commands instead of dry-run")

    classify = subcommands.add_parser("classify", help="Classify evidence for a run")
    classify.add_argument("--run", required=True, help="Path to a .gap-detector run directory")

    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if args.command == "plan":
        scope_plan = ScopePlanner(Path.cwd()).plan(args.scope)
        run_name = args.run_name or _safe_run_name(args.scope)
        run_dir = Path(".gap-detector") / "runs" / run_name
        manifest = _manifest_from_scope_plan(scope_plan)
        manifest_path = run_dir / "manifest.yaml"
        save_manifest(manifest, manifest_path)
        print(json.dumps({
            "manifest": str(manifest_path),
            "scope_plan": _scope_plan_to_dict(scope_plan),
        }, indent=2, ensure_ascii=False))
        return 0
    if args.command == "run":
        manifest = load_manifest(Path(args.manifest))
        probe = next((item for item in manifest.probes if item.id == args.probe), None)
        if probe is None:
            parser.error(f"probe not found: {args.probe}")
        commands = commands_for_probe(probe, Path.cwd())
        for command in commands:
            if args.execute:
                result = execute_command(command)
                print(json.dumps({
                    "platform": command.platform,
                    "command": command.shell_text(),
                    "returncode": result.returncode,
                    "stdout": result.stdout[-4000:],
                    "stderr": result.stderr[-4000:],
                }, indent=2, ensure_ascii=False))
                if result.returncode != 0:
                    return result.returncode
            else:
                print(f"[dry-run] {command.platform}: {command.shell_text()} (cwd={command.cwd})")
        return 0
    return 0


def _scope_plan_to_dict(plan: object) -> dict[str, object]:
    return {
        "mode": plan.mode.value,
        "input": plan.input_value,
        "confirmation_required": plan.confirmation_required,
        "candidates": [
            {
                "label": candidate.label,
                "path": str(candidate.path) if candidate.path else "",
                "sources": [str(source) for source in candidate.sources],
                "reason": candidate.reason,
            }
            for candidate in plan.candidates
        ],
    }


def _safe_run_name(scope: str) -> str:
    cleaned = "".join(ch if ch.isalnum() else "-" for ch in scope.strip().lower()).strip("-")
    return cleaned or "search"


def _manifest_from_scope_plan(scope_plan: object) -> Manifest:
    docs: list[str] = []
    tests: dict[str, list[str]] = {"harmony": [], "ios": [], "android": []}
    probes: list[Probe] = []
    selected_paths: list[str] = []
    skipped_paths: dict[str, str] = {}
    pending_selection = scope_plan.confirmation_required

    for candidate in scope_plan.candidates:
        if pending_selection:
            skipped_paths[candidate.label] = "pending user selection"
        else:
            selected_paths.append(candidate.label)
        if candidate.path:
            docs.append(str(candidate.path))
        for source in candidate.sources:
            source_text = str(source)
            if source_text.startswith("harmonyos/"):
                tests["harmony"].append(source_text)
            elif source_text.startswith("ios/"):
                tests["ios"].append(source_text)
            elif source_text.startswith("android/"):
                tests["android"].append(source_text)
        probes.append(Probe(id=_safe_run_name(candidate.label), page=candidate.label))

    return Manifest(
        scope=ScopeRecord(
            mode=scope_plan.mode.value,
            input=scope_plan.input_value,
            baseline_branch="origin/main",
            selected_paths=tuple(selected_paths),
            skipped_paths=skipped_paths,
        ),
        sources=SourceRecord(
            docs=tuple(dict.fromkeys(docs)),
            tests={platform: tuple(dict.fromkeys(paths)) for platform, paths in tests.items() if paths},
        ),
        probes=tuple(probes),
    )
