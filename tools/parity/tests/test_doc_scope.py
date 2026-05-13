from pathlib import Path

from parity_audit.cli import run
from parity_audit.doc_clues import build_doc_search_plan, collect_doc_clues, clue_for_identifier


def write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def test_doc_clues_only_search_selected_paths_unless_overall(tmp_path: Path) -> None:
    repo = tmp_path / "repo"
    selected = repo / "docs/superpowers/specs/selected.md"
    unrelated = repo / "docs/superpowers/plans/unrelated.md"
    write(selected, "Selected behavior must replicate SelectedMarker.\n")
    write(unrelated, "Unrelated behavior must replicate UnrelatedMarker.\n")

    selected_clues = collect_doc_clues(repo, paths=[selected])
    overall_clues = collect_doc_clues(repo, overall=True)

    assert clue_for_identifier(selected_clues, "SelectedMarker") is not None
    assert clue_for_identifier(selected_clues, "UnrelatedMarker") is None
    assert clue_for_identifier(overall_clues, "SelectedMarker") is not None
    assert clue_for_identifier(overall_clues, "UnrelatedMarker") is not None


def test_doc_search_plan_groups_candidate_branches(tmp_path: Path) -> None:
    repo = tmp_path / "repo"
    write(repo / "docs/superpowers/specs/a-design.md", "# A\n")
    write(repo / "docs/superpowers/plans/a-plan.md", "# A plan\n")
    write(repo / "docs/features/2026-05-12-demo/00-design.md", "# Demo\n")

    plan = build_doc_search_plan(repo)

    assert "docs/superpowers/specs" in plan
    assert "docs/superpowers/plans" in plan
    assert "docs/features" in plan
    assert "docs/superpowers/specs/a-design.md" in plan["docs/superpowers/specs"]
    assert "docs/features/2026-05-12-demo/00-design.md" in plan["docs/features"]


def test_cli_plan_doc_scope_writes_plan_without_global_search(tmp_path: Path, capsys) -> None:
    repo = tmp_path / "repo"
    out = tmp_path / "out"
    write(repo / "docs/superpowers/specs/a-design.md", "# A\n")

    exit_code = run(["--repo-root", str(repo), "--out", str(out), "--plan-doc-scope"])

    captured = capsys.readouterr()
    assert exit_code == 0
    assert "Doc search plan written" in captured.out
    assert (out / "doc-search-plan.md").exists()
    assert (out / "doc-search-plan.json").exists()
