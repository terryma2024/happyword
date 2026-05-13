from __future__ import annotations

from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Literal

Platform = Literal["ios", "android"]
GapKind = Literal["behavior", "stable_id", "visual", "test_coverage", "screenshot_capture"]
Severity = Literal["P0", "P1", "P2", "P3"]


@dataclass(frozen=True)
class Evidence:
    identifier: str
    source: str
    detail: str

    def to_dict(self) -> dict[str, str]:
        return asdict(self)


@dataclass(frozen=True)
class Gap:
    platform: Platform
    kind: GapKind
    severity: Severity
    title: str
    harmony_evidence: Evidence
    platform_evidence: Evidence
    suggested_fix_entry: str

    def to_dict(self) -> dict[str, object]:
        data = asdict(self)
        return data


@dataclass(frozen=True)
class ScreenshotMetric:
    screen: str
    harmony_path: Path
    platform_path: Path
    diff_path: Path
    diff_percent: float
    average_delta: float
    size_mismatch: bool

    def to_dict(self) -> dict[str, object]:
        return {
            "screen": self.screen,
            "harmony_path": str(self.harmony_path),
            "platform_path": str(self.platform_path),
            "diff_path": str(self.diff_path),
            "diff_percent": self.diff_percent,
            "average_delta": self.average_delta,
            "size_mismatch": self.size_mismatch,
        }
