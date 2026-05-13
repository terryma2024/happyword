from __future__ import annotations

import argparse
import json
from collections.abc import Sequence
from pathlib import Path

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
        plan = ScopePlanner(Path.cwd()).plan(args.scope)
        print(json.dumps(_scope_plan_to_dict(plan), indent=2, ensure_ascii=False))
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
