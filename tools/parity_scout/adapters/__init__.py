"""parity_scout per-platform capture adapters."""

from __future__ import annotations

import abc
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class AdapterResult:
    platform: str
    page_id: str
    out_dir: Path
    success: bool
    stderr_tail: str = ""


class Adapter(abc.ABC):
    name: str

    @abc.abstractmethod
    def capture(
        self,
        page_id: str,
        capture_spec: dict,
        out_dir: Path,
        timeout_s: int,
    ) -> AdapterResult: ...
