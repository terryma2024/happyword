"""Registry loader for parity_scout.

Parses tools/parity_scout/page_suite_map.yml into typed objects and enforces
the schema rules from the design spec:
- present: false                  -> platform is FEATURE_ABSENT (skipped at run)
- present: true && capture: null  -> platform is BLOCKED (refuse to run leaf)
- present: true && capture.kind in {capture_harmony_step, simctl_route,
  android_screenshot_test}        -> platform is OK
"""

from __future__ import annotations

import enum
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import yaml


class RegistryError(Exception):
    """Raised when the registry yaml violates the schema."""


_VALID_KINDS = {"capture_harmony_step", "simctl_route", "android_screenshot_test"}


class PlatformStatus(str, enum.Enum):
    OK = "ok"
    FEATURE_ABSENT = "feature_absent"
    BLOCKED = "blocked"


@dataclass(frozen=True)
class CaptureSpec:
    kind: str
    raw: dict[str, Any]


@dataclass(frozen=True)
class PlatformEntry:
    present: bool
    page_source: str | None
    capture: CaptureSpec | None

    def status(self) -> PlatformStatus:
        if not self.present:
            return PlatformStatus.FEATURE_ABSENT
        if self.capture is None:
            return PlatformStatus.BLOCKED
        return PlatformStatus.OK

    def block_reason(self) -> str | None:
        return (
            "add-capture-route"
            if self.status() == PlatformStatus.BLOCKED
            else None
        )


@dataclass(frozen=True)
class SpecAnchors:
    stable_ids: list[str] = field(default_factory=list)
    page_section_titles: list[str] = field(default_factory=list)


@dataclass(frozen=True)
class PageEntry:
    id: str
    description: str
    spec_anchors: SpecAnchors
    harmony: PlatformEntry
    ios: PlatformEntry
    android: PlatformEntry


@dataclass(frozen=True)
class Registry:
    pages: tuple[PageEntry, ...]

    def by_id(self, page_id: str) -> PageEntry:
        for p in self.pages:
            if p.id == page_id:
                return p
        raise KeyError(page_id)


def _parse_platform(d: dict[str, Any] | None) -> PlatformEntry:
    if d is None:
        raise RegistryError("missing platform entry")
    present = bool(d.get("present", False))
    page_source = d.get("page_source")
    cap_raw = d.get("capture")
    capture: CaptureSpec | None = None
    if cap_raw is not None:
        if not isinstance(cap_raw, dict):
            raise RegistryError(
                f"capture must be a mapping, got {type(cap_raw).__name__}"
            )
        kind = cap_raw.get("kind")
        if kind not in _VALID_KINDS:
            raise RegistryError(f"unknown capture kind: {kind!r}")
        capture = CaptureSpec(kind=kind, raw=dict(cap_raw))
    return PlatformEntry(present=present, page_source=page_source, capture=capture)


def _parse_anchors(d: dict[str, Any] | None) -> SpecAnchors:
    d = d or {}
    return SpecAnchors(
        stable_ids=list(d.get("stable_ids") or []),
        page_section_titles=list(d.get("page_section_titles") or []),
    )


def _parse_page(d: dict[str, Any]) -> PageEntry:
    return PageEntry(
        id=str(d["id"]),
        description=str(d.get("description", "")),
        spec_anchors=_parse_anchors(d.get("spec_anchors")),
        harmony=_parse_platform(d.get("harmony")),
        ios=_parse_platform(d.get("ios")),
        android=_parse_platform(d.get("android")),
    )


def load_registry(path: Path) -> Registry:
    text = Path(path).read_text(encoding="utf-8")
    data = yaml.safe_load(text) or {}
    raw_pages = data.get("pages") or []
    if not isinstance(raw_pages, list):
        raise RegistryError("`pages` must be a list")
    parsed = tuple(_parse_page(p) for p in raw_pages)
    return Registry(pages=parsed)
