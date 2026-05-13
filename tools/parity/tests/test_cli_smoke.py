import json
from pathlib import Path

from parity_audit.cli import run


def write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def test_cli_writes_actionable_gap_outputs(tmp_path: Path, capsys) -> None:
    repo = tmp_path / "repo"
    out = tmp_path / "out"

    write(repo / "harmonyos/entry/src/main/ets/pages/HomePage.ets", ".id('HomeStartButton')\n.id('BattleTitle')\n")
    write(repo / "harmonyos/entry/src/ohosTest/ets/test/Home.ui.test.ets", "findComponent('HomeStartButton')\nfindComponent('BattleTitle')\n")
    write(repo / "ios/WordMagicGame/Features/CoreLoop/HomeView.swift", '.accessibilityIdentifier("HomeStartButton")\n')
    write(repo / "android/app/src/main/java/cool/happyword/wordmagic/MainActivity.kt", 'Modifier.testTag("BattleTitle")\n')

    exit_code = run(
        [
            "--repo-root",
            str(repo),
            "--baseline",
            "working-tree",
            "--out",
            str(out),
        ],
    )

    captured = capsys.readouterr()
    data = json.loads((out / "gaps.json").read_text(encoding="utf-8"))

    assert exit_code == 0
    assert "P0 ios stable_id" in captured.out
    assert "P0 android stable_id" in captured.out
    assert (out / "gaps.md").exists()
    assert {gap["platform"] for gap in data["gaps"]} == {"ios", "android"}


def test_cli_behavior_kind_uses_selected_doc_path(tmp_path: Path, capsys) -> None:
    repo = tmp_path / "repo"
    out = tmp_path / "out"

    write(repo / "harmonyos/entry/src/main/ets/pages/BattlePage.ets", ".id('BattleWrongCueSkippedMarker')\n")
    write(repo / "harmonyos/entry/src/ohosTest/ets/test/Battle.ui.test.ets", "findComponent('BattleWrongCueSkippedMarker')\n")
    write(repo / "android/app/src/main/java/cool/happyword/wordmagic/Battle.kt", 'Modifier.testTag("BattleWrongCueSkippedMarker")\n')
    write(
        repo / "docs/superpowers/specs/battle-design.md",
        "iOS and Android must replicate BattleWrongCueSkippedMarker one-frame feedback semantics.\n",
    )

    exit_code = run(
        [
            "--repo-root",
            str(repo),
            "--baseline",
            "working-tree",
            "--kind",
            "behavior",
            "--doc-path",
            "docs/superpowers/specs/battle-design.md",
            "--out",
            str(out),
        ],
    )

    captured = capsys.readouterr()
    data = json.loads((out / "gaps.json").read_text(encoding="utf-8"))

    assert exit_code == 0
    assert "P0 ios behavior" in captured.out
    assert data["metadata"]["doc_scope"] == "docs/superpowers/specs/battle-design.md"
    assert [(gap["platform"], gap["kind"], gap["severity"]) for gap in data["gaps"]] == [
        ("ios", "behavior", "P0"),
        ("android", "behavior", "P1"),
    ]
