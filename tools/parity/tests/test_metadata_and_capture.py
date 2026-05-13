from pathlib import Path

from PIL import Image

from parity_audit.cli import build_metadata, run
from parity_audit.capture import capture_dirs_for


def test_build_metadata_includes_git_state_for_non_git_repo(tmp_path: Path) -> None:
    metadata = build_metadata(tmp_path, "working-tree", tmp_path / "out")

    assert metadata["baseline"] == "working-tree"
    assert metadata["baseline_commit"] == "unknown"
    assert metadata["current_commit"] == "unknown"
    assert metadata["dirty"] == "unknown"


def test_capture_dirs_override_asset_screenshots_for_visual_analysis(tmp_path: Path) -> None:
    repo = tmp_path / "repo"
    out = tmp_path / "out"
    (repo / "assets/screenshots/harmonyos").mkdir(parents=True)
    (repo / "assets/screenshots/ios").mkdir(parents=True)
    (repo / "assets/screenshots/android").mkdir(parents=True)
    (out / "captures/ios").mkdir(parents=True)

    Image.new("RGB", (8, 4), (255, 255, 255)).save(repo / "assets/screenshots/harmonyos/home.png")
    Image.new("RGB", (8, 4), (255, 255, 255)).save(repo / "assets/screenshots/ios/home.png")
    Image.new("RGB", (8, 4), (0, 0, 0)).save(out / "captures/ios/home.png")

    exit_code = run(
        [
            "--repo-root",
            str(repo),
            "--baseline",
            "working-tree",
            "--out",
            str(out),
            "--platform",
            "ios",
            "--kind",
            "visual",
        ],
    )

    assert exit_code == 0
    assert (out / "visual-diffs/diff-ios-home.png").exists()


def test_capture_dirs_for_points_at_output_capture_folders(tmp_path: Path) -> None:
    dirs = capture_dirs_for(tmp_path, {"ios", "android"})

    assert dirs["ios"] == tmp_path / "captures" / "ios"
    assert dirs["android"] == tmp_path / "captures" / "android"
