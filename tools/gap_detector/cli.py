from __future__ import annotations

import argparse
from collections.abc import Sequence


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
    parser.parse_args(argv)
    return 0
