from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

from .capture import capture_dirs_for, run_capture
from .doc_clues import clue_for_identifier, collect_doc_clues, write_doc_search_plan
from .gap_rules import find_behavior_gaps, find_stable_id_gaps, find_test_coverage_gaps
from .repo import collect_harmony_baseline, collect_working_tree, flatten
from .renderers import terminal_summary, write_outputs
from .visual import find_visual_gaps

SEVERITY_ORDER = {"P0": 0, "P1": 1, "P2": 2, "P3": 3}


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Find iOS and Android gaps against the HarmonyOS baseline.")
    parser.add_argument("--repo-root", default=".", help="Repository root. Defaults to current directory.")
    parser.add_argument("--baseline", default="origin/main", help="HarmonyOS baseline git ref, or working-tree for tests.")
    parser.add_argument("--out", required=True, help="Output directory for gaps.json, gaps.md, and visual diffs.")
    parser.add_argument("--fetch", action="store_true", help="Fetch origin before reading the baseline ref.")
    parser.add_argument("--capture", default="", help="Comma-separated capture targets: ios,android,harmony.")
    parser.add_argument("--platform", choices=["ios", "android", "all"], default="all")
    parser.add_argument("--kind", default="behavior,stable_id,test_coverage,visual", help="Comma-separated gap kinds to run.")
    parser.add_argument("--fail-on", choices=["P0", "P1", "P2"], default=None)
    parser.add_argument("--doc-scope", choices=["overall", "none"], default="none", help="Use overall only when the user explicitly asks for global spec/plan search.")
    parser.add_argument("--doc-path", action="append", default=[], help="Specific spec/plan/feature markdown path to search for expected-behavior clues. May be repeated.")
    parser.add_argument("--plan-doc-scope", action="store_true", help="Write doc-search-plan.md/json and exit so the user can choose paths.")
    return parser


def run(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    repo_root = Path(args.repo_root).resolve()
    out_dir = Path(args.out).resolve()
    if args.plan_doc_scope:
        write_doc_search_plan(repo_root, out_dir)
        print(f"Doc search plan written to {out_dir / 'doc-search-plan.md'}")
        return 0
    if args.fetch:
        subprocess.run(["git", "fetch", "origin"], cwd=repo_root, check=False)

    selected_platforms = {"ios", "android"} if args.platform == "all" else {args.platform}
    selected_kinds = {kind.strip() for kind in args.kind.split(",") if kind.strip()}
    capture_targets = {target.strip() for target in args.capture.split(",") if target.strip()}

    capture_gaps = run_capture(repo_root, out_dir, capture_targets) if capture_targets else []
    baseline = collect_harmony_baseline(repo_root, args.baseline)
    current = collect_working_tree(repo_root)
    doc_paths = [Path(path) for path in args.doc_path]
    doc_clues = collect_doc_clues(repo_root, paths=doc_paths, overall=args.doc_scope == "overall")

    gaps = list(capture_gaps)
    metrics = []
    if "stable_id" in selected_kinds:
        gaps.extend(
            find_stable_id_gaps(
                harmony_ids=baseline["ids"],
                harmony_test_refs=baseline["refs"],
                platform_ids={
                    "ios": flatten(current["ios_ids"]),
                    "android": flatten(current["android_ids"]),
                },
                doc_clues=_doc_clue_map(doc_clues),
            ),
        )
    if "behavior" in selected_kinds:
        gaps.extend(
            find_behavior_gaps(
                harmony_ids=baseline["ids"],
                harmony_test_refs=baseline["refs"],
                platform_ids={
                    "ios": flatten(current["ios_ids"]),
                    "android": flatten(current["android_ids"]),
                },
                platform_refs={
                    "ios": flatten(current["ios_refs"]),
                    "android": flatten(current["android_refs"]),
                },
                doc_clues=doc_clues,
            ),
        )
    if "test_coverage" in selected_kinds:
        gaps.extend(
            find_test_coverage_gaps(
                harmony_test_refs=baseline["refs"],
                platform_refs={
                    "ios": flatten(current["ios_refs"]),
                    "android": flatten(current["android_refs"]),
                },
            ),
        )
    if "visual" in selected_kinds:
        visual_gaps, metrics = find_visual_gaps(repo_root, out_dir, selected_platforms, capture_dirs_for(out_dir, capture_targets))
        gaps.extend(visual_gaps)

    gaps = [gap for gap in gaps if gap.platform in selected_platforms]
    metadata = build_metadata(repo_root, args.baseline, out_dir)
    metadata["doc_scope"] = _doc_scope_label(args.doc_scope, doc_paths)
    write_outputs(out_dir, gaps, metrics, metadata)
    print(terminal_summary(gaps))
    if args.fail_on and any(SEVERITY_ORDER[gap.severity] <= SEVERITY_ORDER[args.fail_on] for gap in gaps):
        return 1
    return 0


def build_metadata(repo_root: Path, baseline: str, out_dir: Path) -> dict[str, str]:
    return {
        "baseline": baseline,
        "baseline_commit": _git_output(repo_root, ["rev-parse", "--short", baseline]),
        "current_commit": _git_output(repo_root, ["rev-parse", "--short", "HEAD"]),
        "dirty": _dirty_state(repo_root),
        "repo_root": str(repo_root),
        "out_dir": str(out_dir),
    }


def _git_output(repo_root: Path, args: list[str]) -> str:
    result = subprocess.run(["git", *args], cwd=repo_root, capture_output=True, text=True, check=False)
    if result.returncode != 0:
        return "unknown"
    return result.stdout.strip() or "unknown"


def _dirty_state(repo_root: Path) -> str:
    result = subprocess.run(["git", "status", "--short"], cwd=repo_root, capture_output=True, text=True, check=False)
    if result.returncode != 0:
        return "unknown"
    return "dirty" if result.stdout.strip() else "clean"


def _doc_clue_map(doc_clues) -> dict[str, str]:
    mapped: dict[str, str] = {}
    for identifier in doc_clues:
        clue = clue_for_identifier(doc_clues, identifier)
        if clue is not None:
            mapped[identifier] = clue.evidence_text
    return mapped


def _doc_scope_label(doc_scope: str, doc_paths: list[Path]) -> str:
    if doc_scope == "overall":
        return "overall"
    if doc_paths:
        return ",".join(str(path) for path in doc_paths)
    return "none"


def main() -> None:
    raise SystemExit(run(sys.argv[1:]))
