from __future__ import annotations

import subprocess
import time
from pathlib import Path

from .models import Evidence, Gap, Platform


def capture_dirs_for(out_dir: Path, requested: set[str]) -> dict[Platform, Path]:
    dirs: dict[Platform, Path] = {}
    if "ios" in requested:
        dirs["ios"] = out_dir / "captures" / "ios"
    if "android" in requested:
        dirs["android"] = out_dir / "captures" / "android"
    return dirs


def run_capture(repo_root: Path, out_dir: Path, requested: set[str]) -> list[Gap]:
    gaps: list[Gap] = []
    if "harmony" in requested:
        gaps.extend(_run_command(repo_root, ["python3", "scripts/capture_harmony_screenshots.py"], "harmony"))
    if "ios" in requested:
        gaps.extend(_capture_ios(repo_root, out_dir / "captures" / "ios"))
    if "android" in requested:
        gaps.extend(_capture_android(repo_root, out_dir / "captures" / "android"))
    return gaps


def _run_command(cwd: Path, command: list[str], platform: str) -> list[Gap]:
    result = subprocess.run(command, cwd=cwd, capture_output=True, text=True, check=False)
    if result.returncode == 0:
        return []
    if platform == "harmony":
        return [
            _baseline_capture_gap("ios", command, result),
            _baseline_capture_gap("android", command, result),
        ]
    target_platform: Platform = "ios" if platform == "ios" else "android"
    return [
        Gap(
            platform=target_platform,
            kind="screenshot_capture",
            severity="P2",
            title=f"{platform} screenshot capture command failed",
            harmony_evidence=Evidence(platform, "capture command", "Live screenshot capture was requested"),
            platform_evidence=Evidence(platform, "stderr", (result.stderr or result.stdout)[-500:]),
            suggested_fix_entry="Check the relevant .cursor/*-dev-commands.md manifest and rerun capture after the device is available.",
        ),
    ]


def _capture_ios(repo_root: Path, target_dir: Path) -> list[Gap]:
    target_dir.mkdir(parents=True, exist_ok=True)
    commands = [
        (
            repo_root / "ios",
            [
                "xcodebuild",
                "build",
                "-scheme",
                "WordMagicGame",
                "-destination",
                "platform=iOS Simulator,name=iPhone 17 Pro",
                "-derivedDataPath",
                "/private/tmp/wordmagic-dd",
            ],
        ),
        (repo_root, ["xcrun", "simctl", "boot", "iPhone 17 Pro"]),
        (
            repo_root,
            [
                "xcrun",
                "simctl",
                "install",
                "booted",
                "/private/tmp/wordmagic-dd/Build/Products/Debug-iphonesimulator/WordMagicGame.app",
            ],
        ),
        (
            repo_root,
            [
                "xcrun",
                "simctl",
                "launch",
                "booted",
                "com.terryma.wordmagicgame",
                "-UITestResetState",
            ],
        ),
        (repo_root, ["xcrun", "simctl", "io", "booted", "screenshot", str(target_dir / "home.png")]),
        (
            repo_root,
            [
                "xcrun",
                "simctl",
                "launch",
                "booted",
                "com.terryma.wordmagicgame",
                "-UITestResetState",
                "-UITestRouteBattle",
            ],
        ),
        (repo_root, ["xcrun", "simctl", "io", "booted", "screenshot", str(target_dir / "battle.png")]),
    ]
    gaps: list[Gap] = []
    for cwd, command in commands:
        result = subprocess.run(command, cwd=cwd, capture_output=True, text=True, check=False)
        if result.returncode != 0 and command[:3] != ["xcrun", "simctl", "boot"]:
            gaps.extend(_capture_failure("ios", command, result))
            break
        if command[:3] == ["xcrun", "simctl", "launch"]:
            time.sleep(1.0)
    return gaps


def _capture_android(repo_root: Path, target_dir: Path) -> list[Gap]:
    target_dir.mkdir(parents=True, exist_ok=True)
    build = subprocess.run(["./gradlew", "installDebug"], cwd=repo_root / "android", capture_output=True, text=True, check=False)
    if build.returncode != 0:
        return _capture_failure("android", ["./gradlew", "installDebug"], build)
    adb = _adb_path()
    devices = subprocess.run([adb, "devices"], cwd=repo_root, capture_output=True, text=True, check=False)
    serial = _first_android_device(devices.stdout)
    if not serial:
        return _capture_failure("android", [adb, "devices"], devices, detail="No online Android device found")
    launch = subprocess.run(
        [adb, "-s", serial, "shell", "am", "start", "-n", "cool.happyword.wordmagic/.MainActivity"],
        cwd=repo_root,
        capture_output=True,
        text=True,
        check=False,
    )
    if launch.returncode != 0:
        return _capture_failure("android", [adb, "shell", "am", "start"], launch)
    screenshot = subprocess.run(
        [adb, "-s", serial, "exec-out", "screencap", "-p"],
        cwd=repo_root,
        capture_output=True,
        check=False,
    )
    if screenshot.returncode != 0:
        return _capture_failure("android", [adb, "exec-out", "screencap", "-p"], screenshot)
    (target_dir / "home.png").write_bytes(screenshot.stdout)
    return []


def _capture_failure(platform: Platform, command: list[str], result: subprocess.CompletedProcess, detail: str | None = None) -> list[Gap]:
    output = detail or _result_text(result)[-500:]
    return [
        Gap(
            platform=platform,
            kind="screenshot_capture",
            severity="P2",
            title=f"{platform} screenshot capture failed",
            harmony_evidence=Evidence(platform, "capture command", "Live screenshot capture was requested"),
            platform_evidence=Evidence(platform, " ".join(command), output),
            suggested_fix_entry=f"Check .cursor/{platform}-dev-commands.md and rerun with the simulator/emulator available.",
        ),
    ]


def _baseline_capture_gap(platform: Platform, command: list[str], result: subprocess.CompletedProcess) -> Gap:
    return Gap(
        platform=platform,
        kind="screenshot_capture",
        severity="P2",
        title="HarmonyOS baseline screenshot capture failed",
        harmony_evidence=Evidence("harmony", " ".join(command), _result_text(result)[-500:]),
        platform_evidence=Evidence(platform, "capture skipped", "Cannot compare target platform screenshots without baseline refresh"),
        suggested_fix_entry="Check .cursor/ohos-dev-commands.md and rerun with the HarmonyOS device available.",
    )


def _result_text(result: subprocess.CompletedProcess) -> str:
    stderr = result.stderr.decode("utf-8", errors="ignore") if isinstance(result.stderr, bytes) else result.stderr
    stdout = result.stdout.decode("utf-8", errors="ignore") if isinstance(result.stdout, bytes) else result.stdout
    return stderr or stdout or ""


def _adb_path() -> str:
    import os

    android_home = os.environ.get("ANDROID_HOME")
    if android_home:
        return str(Path(android_home) / "platform-tools" / "adb")
    return "adb"


def _first_android_device(output: str) -> str | None:
    for line in output.splitlines()[1:]:
        parts = line.split()
        if len(parts) >= 2 and parts[1] == "device":
            return parts[0]
    return None
