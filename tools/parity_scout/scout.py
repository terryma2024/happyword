#!/usr/bin/env python3
"""parity_scout CLI entry point.

See docs/superpowers/specs/2026-05-13-parity-scout-design.md for the design.
Subcommands: plan, pick, run, promote, doctor, prune.
"""

from __future__ import annotations

import argparse
import sys


def _build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="scout.py")
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("plan", help="Decompose a scope into a search plan tree.")
    sub.add_parser("pick", help="Record branch selection for an existing run.")
    sub.add_parser("run", help="Drive per-leaf captures with SKILL sync.")
    sub.add_parser("promote", help="Append curated findings to a feature's followups.")
    sub.add_parser("doctor", help="Preflight diagnostic.")
    sub.add_parser("prune", help="Rotate old run directories.")
    return p


def main(argv: list[str] | None = None) -> int:
    args = _build_parser().parse_args(argv)
    print(f"NOT IMPLEMENTED: {args.cmd}", file=sys.stderr)
    return 64


if __name__ == "__main__":
    raise SystemExit(main())
