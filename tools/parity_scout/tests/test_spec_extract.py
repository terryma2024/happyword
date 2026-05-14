from pathlib import Path

import pytest

from parity_scout.registry import load_registry
from parity_scout.spec_extract import ScopeError, resolve_scope


def test_overall_returns_every_page(fixtures_dir):
    reg = load_registry(fixtures_dir / "registry_minimal.yml")
    pages = resolve_scope(reg, kind="overall", value=None)
    assert sorted(pages) == ["battle", "home"]


def test_pages_explicit_returns_listed(fixtures_dir):
    reg = load_registry(fixtures_dir / "registry_minimal.yml")
    pages = resolve_scope(reg, kind="pages", value="battle,home")
    assert sorted(pages) == ["battle", "home"]


def test_pages_unknown_raises(fixtures_dir):
    reg = load_registry(fixtures_dir / "registry_minimal.yml")
    with pytest.raises(ScopeError, match="unknown page id"):
        resolve_scope(reg, kind="pages", value="bogus")


def test_spec_extracts_via_stable_ids(fixtures_dir):
    reg = load_registry(fixtures_dir / "registry_minimal.yml")
    pages = resolve_scope(
        reg,
        kind="spec",
        value=str(fixtures_dir / "specs" / "wishlist_design.md"),
    )
    # The fixture mentions HomeStartButton and BattleCorrectOption
    # which map to 'home' and 'battle' via the registry's spec_anchors.
    assert sorted(pages) == ["battle", "home"]


def test_describe_with_no_match_is_empty(fixtures_dir):
    reg = load_registry(fixtures_dir / "registry_minimal.yml")
    pages = resolve_scope(reg, kind="describe", value="something totally unrelated")
    assert pages == []
