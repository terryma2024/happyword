from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class EvidenceIndex:
    probe_id: str
    platform: str
    screenshot: Path | None = None
    ui_tree_text: str = ""
    log_path: Path | None = None

    def has_screenshot(self) -> bool:
        return self.screenshot is not None and self.screenshot.is_file()

    def contains_stable_id(self, stable_id: str) -> bool:
        return stable_id in self.ui_tree_text
