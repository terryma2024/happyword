from pathlib import Path

from PIL import Image

from parity_audit.visual import compare_screenshots, pair_screenshots


def test_pairs_canonical_screens_across_platforms(tmp_path: Path) -> None:
    harmony_dir = tmp_path / "harmonyos"
    ios_dir = tmp_path / "ios"
    android_dir = tmp_path / "android"
    for directory in (harmony_dir, ios_dir, android_dir):
        directory.mkdir()

    (harmony_dir / "home.png").write_bytes(b"not-used")
    (harmony_dir / "monster-codex-part1.png").write_bytes(b"not-used")
    (ios_dir / "home.png").write_bytes(b"not-used")
    (android_dir / "monster-codex.png").write_bytes(b"not-used")

    pairs = pair_screenshots(
        harmony_dir=harmony_dir,
        platform_dirs={"ios": ios_dir, "android": android_dir},
    )

    assert pairs["home"]["ios"] == ios_dir / "home.png"
    assert pairs["monster-codex"]["android"] == android_dir / "monster-codex.png"
    assert pairs["monster-codex"]["ios"] is None


def test_screenshot_diff_normalizes_size_and_writes_diff(tmp_path: Path) -> None:
    harmony = tmp_path / "harmony.png"
    platform = tmp_path / "platform.png"
    diff = tmp_path / "diff.png"

    Image.new("RGB", (20, 10), (255, 255, 255)).save(harmony)
    Image.new("RGB", (10, 5), (0, 0, 0)).save(platform)

    metric = compare_screenshots(harmony, platform, diff)

    assert metric.screen == "platform"
    assert metric.diff_percent == 100.0
    assert metric.average_delta == 255.0
    assert metric.size_mismatch is True
    assert diff.exists()
