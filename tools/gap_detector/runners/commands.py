from __future__ import annotations

import subprocess
from dataclasses import dataclass
from pathlib import Path

from tools.gap_detector.manifest import Probe


@dataclass(frozen=True)
class RunnerCommand:
    platform: str
    command: tuple[str, ...]
    cwd: Path

    def shell_text(self) -> str:
        return " ".join(self.command)


def commands_for_probe(probe: Probe, repo_root: Path) -> tuple[RunnerCommand, ...]:
    commands: list[RunnerCommand] = []
    harmony = probe.runners.get("harmony")
    if harmony and harmony.suite:
        commands.append(
            RunnerCommand(
                platform="harmony",
                command=("scripts/run_ui_tests.sh", "--suite", harmony.suite),
                cwd=repo_root,
            )
        )

    ios = probe.runners.get("ios")
    if ios and ios.suite:
        target = f"{ios.suite}/{ios.case}" if ios.case else ios.suite
        commands.append(
            RunnerCommand(
                platform="ios",
                command=(
                    "xcodebuild",
                    "test",
                    "-scheme",
                    "WordMagicGame",
                    "-destination",
                    "platform=iOS Simulator,name=iPhone 17 Pro",
                    f"-only-testing:{target}",
                    "-derivedDataPath",
                    "/private/tmp/wordmagic-dd",
                ),
                cwd=repo_root / "ios",
            )
        )

    android = probe.runners.get("android")
    if android and android.suite:
        commands.append(
            RunnerCommand(
                platform="android",
                command=("./gradlew", "connectedDebugAndroidTest"),
                cwd=repo_root / "android",
            )
        )
    return tuple(commands)


def execute_command(command: RunnerCommand) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command.command,
        cwd=command.cwd,
        check=False,
        capture_output=True,
        text=True,
    )
