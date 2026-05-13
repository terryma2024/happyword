from pathlib import Path

from parity_audit.doc_clues import collect_doc_clues, clue_for_identifier
from parity_audit.gap_rules import find_stable_id_gaps


def write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def test_collects_superpowers_spec_and_plan_clues_for_identifiers(tmp_path: Path) -> None:
    repo = tmp_path / "repo"
    write(
        repo / "docs/superpowers/specs/feature-design.md",
        "iOS and Android must replicate the same one-frame semantics for BattleWrongCueSkippedMarker.\n",
    )
    write(
        repo / "docs/superpowers/plans/feature-plan.md",
        "- [ ] Add `.id('ConfigWrongCueSwitch')` and mirror it as accessibilityIdentifier/testTag.\n",
    )

    clues = collect_doc_clues(repo, overall=True)

    marker = clue_for_identifier(clues, "BattleWrongCueSkippedMarker")
    switch = clue_for_identifier(clues, "ConfigWrongCueSwitch")

    assert marker is not None
    assert marker.kind == "behavior"
    assert marker.path.endswith("feature-design.md")
    assert "must replicate" in marker.snippet
    assert switch is not None
    assert switch.kind == "stable_id"


def test_stable_id_gap_uses_superpowers_clue_as_expected_behavior() -> None:
    gaps = find_stable_id_gaps(
        harmony_ids={"ConfigWrongCueSwitch"},
        harmony_test_refs={"ConfigWrongCueSwitch"},
        platform_ids={"ios": set(), "android": set()},
        doc_clues={
            "ConfigWrongCueSwitch": "docs/superpowers/plans/feature-plan.md: Add `.id('ConfigWrongCueSwitch')` and mirror it.",
        },
    )

    assert gaps[0].harmony_evidence.source == "docs/superpowers/plans/feature-plan.md"
    assert "mirror it" in gaps[0].harmony_evidence.detail
    assert "docs/superpowers" in gaps[0].suggested_fix_entry
