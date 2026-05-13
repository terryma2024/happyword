from parity_audit.doc_clues import DocClue
from parity_audit.gap_rules import find_behavior_gaps, find_stable_id_gaps


def test_missing_harmony_tested_id_is_p0_gap_for_each_platform() -> None:
    gaps = find_stable_id_gaps(
        harmony_ids={"HomeStartButton", "BattleTitle", "UntestedDecorativeLabel"},
        harmony_test_refs={"HomeStartButton", "BattleTitle"},
        platform_ids={
            "ios": {"HomeStartButton"},
            "android": {"BattleTitle"},
        },
    )

    gap_keys = {(gap.platform, gap.kind, gap.severity, gap.harmony_evidence.identifier) for gap in gaps}

    assert ("ios", "stable_id", "P0", "BattleTitle") in gap_keys
    assert ("android", "stable_id", "P0", "HomeStartButton") in gap_keys
    assert all(gap.harmony_evidence.identifier != "UntestedDecorativeLabel" for gap in gaps)


def test_missing_untested_id_is_p3_review_gap() -> None:
    gaps = find_stable_id_gaps(
        harmony_ids={"DecorativeBadge"},
        harmony_test_refs=set(),
        platform_ids={
            "ios": set(),
            "android": {"DecorativeBadge"},
        },
    )

    assert len(gaps) == 1
    assert gaps[0].platform == "ios"
    assert gaps[0].severity == "P3"
    assert gaps[0].kind == "stable_id"


def test_doc_behavior_clue_without_platform_counterpart_is_behavior_p0() -> None:
    gaps = find_behavior_gaps(
        harmony_ids={"BattleWrongCueSkippedMarker"},
        harmony_test_refs={"BattleWrongCueSkippedMarker"},
        platform_ids={"ios": set(), "android": {"BattleWrongCueSkippedMarker"}},
        platform_refs={"ios": set(), "android": {"BattleWrongCueSkippedMarker"}},
        doc_clues={
            "BattleWrongCueSkippedMarker": [
                DocClue(
                    identifier="BattleWrongCueSkippedMarker",
                    kind="behavior",
                    path="docs/superpowers/specs/battle.md",
                    line=12,
                    snippet="iOS and Android must replicate BattleWrongCueSkippedMarker semantics.",
                ),
            ],
        },
    )

    assert [(gap.platform, gap.kind, gap.severity, gap.harmony_evidence.identifier) for gap in gaps] == [
        ("ios", "behavior", "P0", "BattleWrongCueSkippedMarker")
    ]
    assert gaps[0].harmony_evidence.source == "docs/superpowers/specs/battle.md:12"
    assert "semantics" in gaps[0].suggested_fix_entry


def test_doc_behavior_clue_with_identifier_but_missing_test_is_behavior_p1() -> None:
    gaps = find_behavior_gaps(
        harmony_ids={"BattleWrongCueSkippedMarker"},
        harmony_test_refs={"BattleWrongCueSkippedMarker"},
        platform_ids={"ios": {"BattleWrongCueSkippedMarker"}, "android": {"BattleWrongCueSkippedMarker"}},
        platform_refs={"ios": set(), "android": {"BattleWrongCueSkippedMarker"}},
        doc_clues={
            "BattleWrongCueSkippedMarker": [
                DocClue(
                    identifier="BattleWrongCueSkippedMarker",
                    kind="behavior",
                    path="docs/superpowers/specs/battle.md",
                    line=12,
                    snippet="iOS and Android must replicate BattleWrongCueSkippedMarker semantics.",
                ),
            ],
        },
    )

    assert [(gap.platform, gap.kind, gap.severity) for gap in gaps] == [("ios", "behavior", "P1")]
