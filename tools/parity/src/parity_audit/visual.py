from __future__ import annotations

import re
from pathlib import Path

from PIL import Image, ImageChops

from .models import Evidence, Gap, Platform, ScreenshotMetric

PART_RE = re.compile(r"-part\d+$")


def canonical_screen_name(path: Path) -> str:
    name = path.stem
    name = PART_RE.sub("", name)
    if name.endswith("-landscape"):
        name = name.removesuffix("-landscape")
    if name.endswith("-portrait"):
        name = name.removesuffix("-portrait")
    if name.startswith("local-growth-"):
        name = name.removeprefix("local-growth-")
    return name


def pair_screenshots(harmony_dir: Path, platform_dirs: dict[Platform, Path]) -> dict[str, dict[str, Path | None]]:
    harmony_screens = {
        canonical_screen_name(path): path
        for path in sorted(harmony_dir.glob("*.png"))
        if path.is_file()
    }
    pairs: dict[str, dict[str, Path | None]] = {}
    for screen, harmony_path in harmony_screens.items():
        pairs[screen] = {"harmony": harmony_path}
        for platform, directory in platform_dirs.items():
            platform_candidates = {
                canonical_screen_name(path): path
                for path in sorted(directory.glob("*.png"))
                if path.is_file()
            }
            pairs[screen][platform] = platform_candidates.get(screen)
    return pairs


def compare_screenshots(harmony_path: Path, platform_path: Path, diff_path: Path) -> ScreenshotMetric:
    with Image.open(harmony_path).convert("RGB") as harmony_img, Image.open(platform_path).convert("RGB") as platform_img:
        size_mismatch = harmony_img.size != platform_img.size
        normalized_platform = platform_img.resize(harmony_img.size)
        diff = ImageChops.difference(harmony_img, normalized_platform)
        diff_path.parent.mkdir(parents=True, exist_ok=True)
        diff.save(diff_path)
        histogram = diff.histogram()
        pixel_count = harmony_img.size[0] * harmony_img.size[1]
        channel_count = 3
        total_delta = sum((value % 256) * count for value, count in enumerate(histogram))
        average_delta = total_delta / (pixel_count * channel_count)
        changed_pixels = 0
        pixels = diff.load()
        for y in range(diff.height):
            for x in range(diff.width):
                if pixels[x, y] != (0, 0, 0):
                    changed_pixels += 1
        diff_percent = round(changed_pixels * 100.0 / pixel_count, 2)
        return ScreenshotMetric(
            screen=platform_path.stem,
            harmony_path=harmony_path,
            platform_path=platform_path,
            diff_path=diff_path,
            diff_percent=diff_percent,
            average_delta=round(average_delta, 2),
            size_mismatch=size_mismatch,
        )


def find_visual_gaps(
    repo_root: Path,
    out_dir: Path,
    platforms: set[Platform],
    capture_dirs: dict[Platform, Path] | None = None,
    diff_threshold: float = 18.0,
) -> tuple[list[Gap], list[ScreenshotMetric]]:
    screenshot_root = repo_root / "assets" / "screenshots"
    capture_dirs = capture_dirs or {}
    pairs = pair_screenshots(
        harmony_dir=screenshot_root / "harmonyos",
        platform_dirs={
            "ios": capture_dirs.get("ios", screenshot_root / "ios"),
            "android": capture_dirs.get("android", screenshot_root / "android"),
        },
    )
    gaps: list[Gap] = []
    metrics: list[ScreenshotMetric] = []
    for screen, paths in pairs.items():
        harmony_path = paths.get("harmony")
        if not isinstance(harmony_path, Path):
            continue
        for platform in sorted(platforms):
            platform_path = paths.get(platform)
            if not isinstance(platform_path, Path):
                gaps.append(
                    Gap(
                        platform=platform,
                        kind="visual",
                        severity="P2",
                        title=f"{platform} is missing screenshot evidence for {screen}",
                        harmony_evidence=Evidence(screen, str(harmony_path), "HarmonyOS screenshot exists"),
                        platform_evidence=Evidence(screen, f"assets/screenshots/{platform}", "No matching screenshot found"),
                        suggested_fix_entry=f"Capture the {platform} {screen} screen and store it under assets/screenshots/{platform}/.",
                    ),
                )
                continue
            metric = compare_screenshots(
                harmony_path,
                platform_path,
                out_dir / "visual-diffs" / f"diff-{platform}-{screen}.png",
            )
            metrics.append(metric)
            if metric.diff_percent >= diff_threshold:
                gaps.append(
                    Gap(
                        platform=platform,
                        kind="visual",
                        severity="P2",
                        title=f"{platform} screenshot for {screen} differs from HarmonyOS baseline",
                        harmony_evidence=Evidence(screen, str(harmony_path), "HarmonyOS screenshot baseline"),
                        platform_evidence=Evidence(
                            screen,
                            str(platform_path),
                            f"{metric.diff_percent}% pixels changed; average delta {metric.average_delta}",
                        ),
                        suggested_fix_entry=f"Review {metric.diff_path} and align the {platform} {screen} UI if the delta is not expected.",
                    ),
                )
    return gaps, metrics
