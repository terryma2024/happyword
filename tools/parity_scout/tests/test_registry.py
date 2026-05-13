from pathlib import Path

import pytest

from parity_scout.registry import (
    PageEntry,
    PlatformStatus,
    Registry,
    RegistryError,
    load_registry,
)


def test_load_minimal_registry(fixtures_dir):
    reg = load_registry(fixtures_dir / "registry_minimal.yml")
    assert isinstance(reg, Registry)
    home = reg.by_id("home")
    assert isinstance(home, PageEntry)
    assert home.harmony.status() == PlatformStatus.OK
    assert home.ios.status() == PlatformStatus.OK
    assert home.android.status() == PlatformStatus.FEATURE_ABSENT


def test_present_without_capture_is_blocked(fixtures_dir):
    reg = load_registry(fixtures_dir / "registry_invalid_capture.yml")
    home = reg.by_id("home")
    assert home.harmony.status() == PlatformStatus.BLOCKED
    assert home.harmony.block_reason() == "add-capture-route"


def test_unknown_id_raises(fixtures_dir):
    reg = load_registry(fixtures_dir / "registry_minimal.yml")
    with pytest.raises(KeyError):
        reg.by_id("nonexistent-page")


def test_iter_pages_returns_all(fixtures_dir):
    reg = load_registry(fixtures_dir / "registry_minimal.yml")
    ids = sorted(p.id for p in reg.pages)
    assert ids == ["battle", "home"]


def test_unknown_capture_kind_raises(tmp_path):
    bad = tmp_path / "bad.yml"
    bad.write_text(
        "pages:\n"
        "  - id: home\n"
        "    description: x\n"
        "    spec_anchors: {stable_ids: [], page_section_titles: []}\n"
        "    harmony: {present: true, page_source: a, "
        "capture: {kind: bogus_kind}}\n"
        "    ios: {present: false}\n"
        "    android: {present: false}\n",
        encoding="utf-8",
    )
    with pytest.raises(RegistryError, match="bogus_kind"):
        load_registry(bad)
