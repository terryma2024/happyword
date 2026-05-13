from pathlib import Path


def test_gap_finder_skill_exists_for_codex_and_cursor() -> None:
    repo = Path(__file__).resolve().parents[3]
    skill_paths = [
        repo / ".agents/skills/cross-platform-gap-finder/SKILL.md",
        repo / ".cursor/skills/cross-platform-gap-finder/SKILL.md",
    ]

    for path in skill_paths:
        text = path.read_text(encoding="utf-8")
        assert "name: cross-platform-gap-finder" in text
        assert "parity-gap" in text
        assert "uv run --project tools/parity parity-gap" in text
        assert "不是报告工具" in text
        assert "docs/superpowers/specs" in text
        assert "docs/superpowers/plans" in text
        assert "--plan-doc-scope" in text
        assert "--doc-scope overall" in text
        assert "--doc-path" in text
        assert "让用户选择" in text
        assert "P0" in text
        assert "P1" in text
        assert "P2" in text
        assert "P3" in text
