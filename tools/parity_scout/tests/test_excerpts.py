from pathlib import Path

from parity_scout.excerpts import extract_excerpt
from parity_scout.registry import load_registry


def test_excerpt_keeps_only_matching_headings(fixtures_dir):
    reg = load_registry(fixtures_dir / "registry_minimal.yml")
    spec_path = fixtures_dir / "specs" / "wishlist_design.md"
    home_excerpt = extract_excerpt(reg.by_id("home"), spec_path)
    # 'HomeStartButton' is in the 'User flows' section
    assert "User flows" in home_excerpt
    assert "HomeStartButton" in home_excerpt
    # The 'Battle integration' section should be filtered out
    assert "Battle integration" not in home_excerpt


def test_excerpt_empty_when_no_anchor_matches(fixtures_dir, tmp_path):
    reg = load_registry(fixtures_dir / "registry_minimal.yml")
    bare = tmp_path / "bare.md"
    bare.write_text("# Title\n\nNo anchors here.\n", encoding="utf-8")
    result = extract_excerpt(reg.by_id("home"), bare)
    assert "<!-- no spec anchors matched" in result
