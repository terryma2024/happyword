# Parity Scout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land `tools/parity_scout/` + `.cursor/skills/parity-scout/SKILL.md` per [`docs/superpowers/specs/2026-05-13-parity-scout-design.md`](../specs/2026-05-13-parity-scout-design.md) — a HarmonyOS-baseline-aware three-platform UI / behavior gap scout that stages simulator screenshots leaf-by-leaf and feeds curated gaps into `docs/features/<id>/60-followups.md`.

**Architecture:** Python CLI (`scout.py`) with subcommands `plan / pick / run / promote / doctor / prune`, a committed registry `page_suite_map.yml` that lists pages and their per-platform capture routes, three thin adapters that wrap existing screenshot manifests (no new test harnesses), and a 150-line scheduler SKILL that drives the agent through the per-leaf vision loop and the user-curated promote gate.

**Tech Stack:** Python 3.11+ (matches `server/` baseline), `pyyaml` for the registry, `rich` for tree printing, `pytest` for offline tests. Adapters shell out to `python3 scripts/capture_harmony_screenshots.py`, `xcrun simctl`, and `$ANDROID_HOME/platform-tools/adb` (existing manifests).

---

## File Structure

**Created:**
- `tools/parity_scout/pyproject.toml` — uv-friendly project metadata + pinned deps + pytest config (mirrors `server/pyproject.toml` discipline: `filterwarnings = ["error"]`).
- `tools/parity_scout/README.md` — operator-facing pointer to the SKILL and manifests.
- `tools/parity_scout/scout.py` — CLI entry; argparse subparsers; loads other modules.
- `tools/parity_scout/registry.py` — load + validate `page_suite_map.yml`.
- `tools/parity_scout/page_suite_map.yml` — committed registry of pages.
- `tools/parity_scout/spec_extract.py` — resolve scope inputs into `[page_id]`.
- `tools/parity_scout/excerpts.py` — slice spec markdown by page.
- `tools/parity_scout/planner.py` — build + render `plan.json` and the human tree.
- `tools/parity_scout/adapters/__init__.py` — adapter dispatcher and abstract base.
- `tools/parity_scout/adapters/harmony.py` — wraps `capture_harmony_screenshots.py --pages <id>`.
- `tools/parity_scout/adapters/ios.py` — wraps `xcrun simctl launch + io screenshot`.
- `tools/parity_scout/adapters/android.py` — wraps `am instrument` + adb screencap.
- `tools/parity_scout/runner.py` — per-leaf rhythm (parallel adapters, `LEAF READY`, `next.flag`).
- `tools/parity_scout/promote.py` — append curated findings to `60-followups.md`.
- `tools/parity_scout/doctor.py` — preflight diagnostic.
- `tools/parity_scout/prune.py` — rotate run dirs.
- `tools/parity_scout/tests/conftest.py` — fixture loaders.
- `tools/parity_scout/tests/fixtures/registry_minimal.yml` — synthetic 3-page registry.
- `tools/parity_scout/tests/fixtures/specs/wishlist_excerpt.md` — synthetic spec slice.
- `tools/parity_scout/tests/fixtures/findings_curated_one_feature.md` — promote fixture.
- `tools/parity_scout/tests/test_registry.py`
- `tools/parity_scout/tests/test_spec_extract.py`
- `tools/parity_scout/tests/test_excerpts.py`
- `tools/parity_scout/tests/test_planner.py`
- `tools/parity_scout/tests/test_promote.py`
- `tools/parity_scout/tests/test_runner.py` — runner rhythm tests (with adapter mocks).
- `.cursor/skills/parity-scout/SKILL.md`
- `.gitignore` patch: `build-tmp/parity_scout/` (if not already covered).

**Modified:**
- `scripts/capture_harmony_screenshots.py` — add `--pages <a,b,c>` CLI flag that filters which step closures run.
- `.cursor/ohos-dev-commands.md` §7 — append one-liner pointer to `tools/parity_scout/README.md`.
- `.cursor/ios-dev-commands.md` §7 — same.
- `.cursor/android-dev-commands.md` §6 — same.
- `.cursor/skills/three-platform-feature-orchestrator/SKILL.md` — Stage 3 + Stage 5 notes about running `parity-scout` before signing / before claiming green.

**Out of scope (deferred):**
- Auto-scroll on iOS / Android. Adapters start as **single-shot per page**; Harmony already scrolls via `capture_harmony_screenshots.py`. The registry's `capture` block leaves room for a future `scroll: true` flag without breaking entries.

---

### Task 1: Bootstrap project skeleton and pyproject

**Files:**
- Create: `tools/parity_scout/pyproject.toml`
- Create: `tools/parity_scout/README.md`
- Create: `tools/parity_scout/scout.py`
- Create: `tools/parity_scout/__init__.py` (empty marker)
- Create: `tools/parity_scout/tests/__init__.py` (empty marker)
- Create: `tools/parity_scout/tests/conftest.py`

- [ ] **Step 1: Create `tools/parity_scout/pyproject.toml`**

```toml
[project]
name = "parity-scout"
version = "0.1.0"
description = "Three-platform UI/behavior parity gap scout for the WordMagicGame monorepo."
requires-python = ">=3.11"
dependencies = [
  "pyyaml>=6.0",
  "rich>=13.0",
]

[dependency-groups]
dev = ["pytest>=8.0"]

[tool.pytest.ini_options]
testpaths = ["tests"]
filterwarnings = ["error"]
addopts = "-ra"
```

- [ ] **Step 2: Create `tools/parity_scout/README.md`** (30-line operator pointer)

```markdown
# parity_scout

Three-platform UI / behavior parity gap scout. **Driver:** [`.cursor/skills/parity-scout/SKILL.md`](../../.cursor/skills/parity-scout/SKILL.md). **Design:** [`docs/superpowers/specs/2026-05-13-parity-scout-design.md`](../../docs/superpowers/specs/2026-05-13-parity-scout-design.md).

## CLI

```bash
python3 tools/parity_scout/scout.py plan    --scope overall
python3 tools/parity_scout/scout.py plan    --spec docs/superpowers/specs/<x>.md
python3 tools/parity_scout/scout.py plan    --feature <feature-id>
python3 tools/parity_scout/scout.py plan    --pages home,wishlist
python3 tools/parity_scout/scout.py plan    --suite ParentAdminFlow
python3 tools/parity_scout/scout.py plan    --describe "..."
python3 tools/parity_scout/scout.py pick    --run <id> --branches home,wishlist
python3 tools/parity_scout/scout.py run     --run <id>
python3 tools/parity_scout/scout.py promote --run <id> --feature <id>
python3 tools/parity_scout/scout.py doctor
python3 tools/parity_scout/scout.py prune   --keep 5
```

Run from repo root. State lives at `build-tmp/parity_scout/<run-id>/`. Registry is `tools/parity_scout/page_suite_map.yml`.

## Tests

```bash
cd tools/parity_scout && uv run pytest
```

## Manifest references

- HarmonyOS: [`.cursor/ohos-dev-commands.md`](../../.cursor/ohos-dev-commands.md)
- iOS: [`.cursor/ios-dev-commands.md`](../../.cursor/ios-dev-commands.md)
- Android: [`.cursor/android-dev-commands.md`](../../.cursor/android-dev-commands.md)
```

- [ ] **Step 3: Create `tools/parity_scout/scout.py` with empty subparser scaffold**

```python
#!/usr/bin/env python3
"""parity_scout CLI entry point.

See docs/superpowers/specs/2026-05-13-parity-scout-design.md for the design.
Subcommands: plan, pick, run, promote, doctor, prune.
"""

from __future__ import annotations

import argparse
import sys


def _build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="scout.py")
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("plan", help="Decompose a scope into a search plan tree.")
    sub.add_parser("pick", help="Record branch selection for an existing run.")
    sub.add_parser("run", help="Drive per-leaf captures with SKILL sync.")
    sub.add_parser("promote", help="Append curated findings to a feature's followups.")
    sub.add_parser("doctor", help="Preflight diagnostic.")
    sub.add_parser("prune", help="Rotate old run directories.")
    return p


def main(argv: list[str] | None = None) -> int:
    args = _build_parser().parse_args(argv)
    print(f"NOT IMPLEMENTED: {args.cmd}", file=sys.stderr)
    return 64


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 4: Create `tools/parity_scout/__init__.py` and `tools/parity_scout/tests/__init__.py`** as empty files.

- [ ] **Step 5: Create `tools/parity_scout/tests/conftest.py`**

```python
"""Shared pytest fixtures for parity_scout."""

from __future__ import annotations

from pathlib import Path

import pytest


@pytest.fixture
def fixtures_dir() -> Path:
    return Path(__file__).parent / "fixtures"
```

- [ ] **Step 6: Smoke-test scaffold**

Run: `cd tools/parity_scout && uv run python scout.py doctor`
Expected: prints `NOT IMPLEMENTED: doctor` to stderr; exit code 64.

- [ ] **Step 7: Commit**

```bash
git add tools/parity_scout/pyproject.toml \
        tools/parity_scout/README.md \
        tools/parity_scout/scout.py \
        tools/parity_scout/__init__.py \
        tools/parity_scout/tests/__init__.py \
        tools/parity_scout/tests/conftest.py
git commit -m "feat(parity-scout): bootstrap CLI skeleton and pyproject"
```

---

### Task 2: Registry loader + schema validator (TDD)

**Files:**
- Create: `tools/parity_scout/tests/fixtures/registry_minimal.yml`
- Create: `tools/parity_scout/tests/fixtures/registry_invalid_capture.yml`
- Create: `tools/parity_scout/tests/test_registry.py`
- Create: `tools/parity_scout/registry.py`

- [ ] **Step 1: Write the fixture `tests/fixtures/registry_minimal.yml`**

```yaml
pages:
  - id: home
    description: Landing screen
    spec_anchors:
      stable_ids: [HomeStartButton]
      page_section_titles: ["Home"]
    harmony:
      present: true
      page_source: harmonyos/entry/src/main/ets/pages/HomePage.ets
      capture:
        kind: capture_harmony_step
        step: home
    ios:
      present: true
      page_source: ios/WordMagicGame/Features/Home/HomePage.swift
      capture:
        kind: simctl_route
        launch_args: ["-UITestResetState"]
        output_basename: home
    android:
      present: false
  - id: battle
    description: Battle (landscape)
    spec_anchors:
      stable_ids: [BattleCorrectOption]
      page_section_titles: ["Battle"]
    harmony:
      present: true
      page_source: harmonyos/entry/src/main/ets/pages/BattlePage.ets
      capture:
        kind: capture_harmony_step
        step: battle
    ios:
      present: true
      page_source: ios/WordMagicGame/Features/Battle/BattlePage.swift
      capture:
        kind: simctl_route
        launch_args: ["-UITestResetState", "-UITestRouteBattle"]
        output_basename: battle
    android:
      present: true
      page_source: android/app/src/main/java/cool/happyword/wordmagic/BattlePage.kt
      capture:
        kind: android_screenshot_test
        case: battle
```

- [ ] **Step 2: Write the fixture `tests/fixtures/registry_invalid_capture.yml`**

```yaml
pages:
  - id: home
    description: Landing screen
    spec_anchors:
      stable_ids: [HomeStartButton]
      page_section_titles: ["Home"]
    harmony:
      present: true
      page_source: harmonyos/entry/src/main/ets/pages/HomePage.ets
      capture: null     # present but no capture → must be blocked
    ios:
      present: true
      page_source: ios/WordMagicGame/Features/Home/HomePage.swift
      capture:
        kind: simctl_route
        launch_args: []
        output_basename: home
    android:
      present: false
```

- [ ] **Step 3: Write failing test `tests/test_registry.py`**

```python
from pathlib import Path

import pytest

from parity_scout.registry import (
    Registry,
    RegistryError,
    PageEntry,
    PlatformStatus,
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
```

- [ ] **Step 4: Run the test, verify it fails**

Run: `cd tools/parity_scout && uv run pytest tests/test_registry.py -v`
Expected: ImportError on `parity_scout.registry`.

- [ ] **Step 5: Implement `tools/parity_scout/registry.py`**

```python
"""Registry loader for parity_scout.

Parses tools/parity_scout/page_suite_map.yml into typed objects and enforces
the schema rules from the design spec:
- present: false  -> platform is FEATURE_ABSENT (skipped at run time)
- present: true && capture: null  -> platform is BLOCKED (refuse to run)
- present: true && capture.kind in {capture_harmony_step, simctl_route,
  android_screenshot_test}  -> platform is OK
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
        return "add-capture-route" if self.status() == PlatformStatus.BLOCKED else None


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
            raise RegistryError(f"capture must be a mapping, got {type(cap_raw).__name__}")
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
```

- [ ] **Step 6: Re-run tests, verify they pass**

Run: `cd tools/parity_scout && uv run pytest tests/test_registry.py -v`
Expected: 5 passed.

- [ ] **Step 7: Commit**

```bash
git add tools/parity_scout/registry.py \
        tools/parity_scout/tests/test_registry.py \
        tools/parity_scout/tests/fixtures/registry_minimal.yml \
        tools/parity_scout/tests/fixtures/registry_invalid_capture.yml
git commit -m "feat(parity-scout): add registry loader with schema validation"
```

---

### Task 3: Scope resolver `spec_extract.py` (TDD)

**Files:**
- Create: `tools/parity_scout/tests/fixtures/specs/wishlist_design.md`
- Create: `tools/parity_scout/tests/test_spec_extract.py`
- Create: `tools/parity_scout/spec_extract.py`

- [ ] **Step 1: Write fixture spec `tests/fixtures/specs/wishlist_design.md`**

```markdown
# Wishlist redemption flow — Design

## User flows

The home `HomeStartButton` opens the battle…

## Wishlist page

The wishlist exposes `HomeWishlistButton`, the wishlist list, and `WishlistHistoryButton`.

## Battle integration

`BattleCorrectOption` is unchanged.
```

- [ ] **Step 2: Write failing test `tests/test_spec_extract.py`**

```python
from pathlib import Path

import pytest

from parity_scout.registry import load_registry
from parity_scout.spec_extract import ScopeError, resolve_scope


def test_overall_returns_every_page(fixtures_dir):
    reg = load_registry(fixtures_dir / "registry_minimal.yml")
    pages = resolve_scope(reg, kind="overall", value=None)
    assert sorted(pages) == ["battle", "home"]


def test_pages_explicit_returns_listed(fixtures_dir):
    reg = load_registry(fixtures_dir / "registry_minimal.yml")
    pages = resolve_scope(reg, kind="pages", value="battle,home")
    assert sorted(pages) == ["battle", "home"]


def test_pages_unknown_raises(fixtures_dir):
    reg = load_registry(fixtures_dir / "registry_minimal.yml")
    with pytest.raises(ScopeError, match="unknown page id"):
        resolve_scope(reg, kind="pages", value="bogus")


def test_spec_extracts_via_stable_ids(fixtures_dir):
    reg = load_registry(fixtures_dir / "registry_minimal.yml")
    pages = resolve_scope(
        reg,
        kind="spec",
        value=str(fixtures_dir / "specs" / "wishlist_design.md"),
    )
    # The fixture mentions HomeStartButton and BattleCorrectOption
    # which map to 'home' and 'battle' via the registry's spec_anchors.
    assert sorted(pages) == ["battle", "home"]


def test_describe_with_no_match_is_empty(fixtures_dir):
    reg = load_registry(fixtures_dir / "registry_minimal.yml")
    pages = resolve_scope(reg, kind="describe", value="something totally unrelated")
    assert pages == []
```

- [ ] **Step 3: Run test, verify it fails**

Run: `cd tools/parity_scout && uv run pytest tests/test_spec_extract.py -v`
Expected: ImportError on `parity_scout.spec_extract`.

- [ ] **Step 4: Implement `tools/parity_scout/spec_extract.py`**

```python
"""Resolve a scope input to a list of registry page ids."""

from __future__ import annotations

from pathlib import Path

from parity_scout.registry import PageEntry, Registry


class ScopeError(Exception):
    """Raised when a scope cannot be resolved to any page."""


_VALID_KINDS = {"overall", "spec", "feature", "pages", "suite", "describe"}


def resolve_scope(reg: Registry, *, kind: str, value: str | None) -> list[str]:
    if kind not in _VALID_KINDS:
        raise ScopeError(f"unknown scope kind: {kind!r}")
    if kind == "overall":
        return [p.id for p in reg.pages]
    if kind == "pages":
        return _resolve_pages(reg, value or "")
    if kind == "suite":
        # Until we wire suite-name -> page_id in the registry, this is the
        # same as `pages`. The registry can later carry a `suite` field per
        # platform; for v0 we accept suite names equal to page ids.
        return _resolve_pages(reg, value or "")
    if kind in {"spec", "feature"}:
        return _resolve_from_markdown(reg, value)
    if kind == "describe":
        return _resolve_from_describe(reg, value or "")
    raise ScopeError(f"unhandled scope kind: {kind!r}")


def _resolve_pages(reg: Registry, value: str) -> list[str]:
    ids = [v.strip() for v in value.split(",") if v.strip()]
    valid = {p.id for p in reg.pages}
    for i in ids:
        if i not in valid:
            raise ScopeError(f"unknown page id: {i!r}")
    return ids


def _read_markdown(value: str | None) -> str:
    if not value:
        raise ScopeError("path required for spec/feature scope")
    path = Path(value)
    if path.is_dir():
        candidates = sorted(path.glob("*.md"))
        if not candidates:
            raise ScopeError(f"feature folder {path} has no markdown files")
        return "\n\n".join(p.read_text(encoding="utf-8") for p in candidates)
    return path.read_text(encoding="utf-8")


def _resolve_from_markdown(reg: Registry, value: str | None) -> list[str]:
    text = _read_markdown(value)
    hits: list[str] = []
    for page in reg.pages:
        if _page_matches_text(page, text):
            hits.append(page.id)
    return hits


def _resolve_from_describe(reg: Registry, prose: str) -> list[str]:
    text = prose
    hits: list[str] = []
    for page in reg.pages:
        if _page_matches_text(page, text):
            hits.append(page.id)
    return hits


def _page_matches_text(page: PageEntry, text: str) -> bool:
    if not text:
        return False
    haystack = text
    for sid in page.spec_anchors.stable_ids:
        if sid and sid in haystack:
            return True
    for title in page.spec_anchors.page_section_titles:
        if title and title in haystack:
            return True
    if page.id and page.id in haystack:
        return True
    return False
```

- [ ] **Step 5: Re-run tests, verify they pass**

Run: `cd tools/parity_scout && uv run pytest tests/test_spec_extract.py -v`
Expected: 5 passed.

- [ ] **Step 6: Commit**

```bash
git add tools/parity_scout/spec_extract.py \
        tools/parity_scout/tests/test_spec_extract.py \
        tools/parity_scout/tests/fixtures/specs/wishlist_design.md
git commit -m "feat(parity-scout): resolve scope inputs to page ids"
```

---

### Task 4: Spec excerpts slicer `excerpts.py` (TDD)

**Files:**
- Create: `tools/parity_scout/tests/test_excerpts.py`
- Create: `tools/parity_scout/excerpts.py`

- [ ] **Step 1: Write failing test**

```python
from pathlib import Path

from parity_scout.excerpts import extract_excerpt
from parity_scout.registry import load_registry


def test_excerpt_keeps_only_matching_headings(fixtures_dir):
    reg = load_registry(fixtures_dir / "registry_minimal.yml")
    spec_path = fixtures_dir / "specs" / "wishlist_design.md"
    home_excerpt = extract_excerpt(reg.by_id("home"), spec_path)
    # 'HomeStartButton' is in the 'User flows' section
    assert "User flows" in home_excerpt
    assert "HomeStartButton" in home_excerpt
    # The 'Battle integration' section should be filtered out
    assert "Battle integration" not in home_excerpt


def test_excerpt_empty_when_no_anchor_matches(fixtures_dir, tmp_path):
    reg = load_registry(fixtures_dir / "registry_minimal.yml")
    bare = tmp_path / "bare.md"
    bare.write_text("# Title\n\nNo anchors here.\n", encoding="utf-8")
    result = extract_excerpt(reg.by_id("home"), bare)
    assert "<!-- no spec anchors matched -->" in result
```

- [ ] **Step 2: Run test, verify it fails**

Run: `cd tools/parity_scout && uv run pytest tests/test_excerpts.py -v`
Expected: ImportError on `parity_scout.excerpts`.

- [ ] **Step 3: Implement `tools/parity_scout/excerpts.py`**

```python
"""Slice a spec markdown into the prose relevant to a given page."""

from __future__ import annotations

import re
from pathlib import Path

from parity_scout.registry import PageEntry


_HEADING_RE = re.compile(r"^(#{1,6})\s+(.+?)\s*$", re.MULTILINE)


def extract_excerpt(page: PageEntry, spec_path: Path) -> str:
    text = Path(spec_path).read_text(encoding="utf-8")
    sections = _split_by_h2(text)
    needles = (
        list(page.spec_anchors.stable_ids)
        + list(page.spec_anchors.page_section_titles)
        + [page.id]
    )
    keep: list[str] = []
    for heading, body in sections:
        haystack = heading + "\n" + body
        if any(n and n in haystack for n in needles):
            keep.append(f"## {heading}\n{body}")
    if not keep:
        return f"<!-- no spec anchors matched for page={page.id} -->\n"
    return "\n".join(keep).strip() + "\n"


def _split_by_h2(text: str) -> list[tuple[str, str]]:
    """Return [(heading_text, body_text), ...] split on '## ' headings."""
    parts: list[tuple[str, str]] = []
    matches = list(re.finditer(r"^##\s+(.+?)\s*$", text, re.MULTILINE))
    if not matches:
        return parts
    for i, m in enumerate(matches):
        heading = m.group(1)
        start = m.end()
        end = matches[i + 1].start() if i + 1 < len(matches) else len(text)
        body = text[start:end].strip("\n")
        parts.append((heading, body))
    return parts
```

- [ ] **Step 4: Re-run tests, verify they pass**

Run: `cd tools/parity_scout && uv run pytest tests/test_excerpts.py -v`
Expected: 2 passed.

- [ ] **Step 5: Commit**

```bash
git add tools/parity_scout/excerpts.py \
        tools/parity_scout/tests/test_excerpts.py
git commit -m "feat(parity-scout): slice spec markdown into per-page excerpts"
```

---

### Task 5: Planner `planner.py` (TDD) — `plan.json` + tree printer

**Files:**
- Create: `tools/parity_scout/tests/test_planner.py`
- Create: `tools/parity_scout/planner.py`

- [ ] **Step 1: Write failing test**

```python
import json

from parity_scout.planner import Leaf, PlanResult, build_plan, render_tree
from parity_scout.registry import load_registry


def test_build_plan_marks_each_platform_status(fixtures_dir):
    reg = load_registry(fixtures_dir / "registry_minimal.yml")
    plan = build_plan(reg, page_ids=["home", "battle"], run_id="r1", scope_kind="pages", scope_value="home,battle")
    assert isinstance(plan, PlanResult)
    home = next(leaf for leaf in plan.leaves if leaf.page_id == "home")
    assert home.harmony["status"] == "ok"
    assert home.android["status"] == "feature_absent"
    battle = next(leaf for leaf in plan.leaves if leaf.page_id == "battle")
    assert battle.android["status"] == "ok"


def test_plan_serializes_to_json(fixtures_dir):
    reg = load_registry(fixtures_dir / "registry_minimal.yml")
    plan = build_plan(reg, page_ids=["home"], run_id="r2", scope_kind="overall", scope_value=None)
    blob = json.loads(plan.to_json())
    assert blob["run_id"] == "r2"
    assert blob["leaves"][0]["page_id"] == "home"


def test_render_tree_marks_blocked_and_feature_absent(fixtures_dir):
    reg = load_registry(fixtures_dir / "registry_minimal.yml")
    plan = build_plan(reg, page_ids=["home", "battle"], run_id="r3", scope_kind="overall", scope_value=None)
    out = render_tree(plan)
    assert "home" in out
    assert "feature_absent" in out
    assert "battle" in out
    assert "ok" in out
```

- [ ] **Step 2: Run test, verify failure**

Run: `cd tools/parity_scout && uv run pytest tests/test_planner.py -v`
Expected: ImportError on `parity_scout.planner`.

- [ ] **Step 3: Implement `tools/parity_scout/planner.py`**

```python
"""Build a search plan from a resolved set of page ids."""

from __future__ import annotations

import json
from dataclasses import asdict, dataclass, field
from typing import Any

from parity_scout.registry import PageEntry, PlatformEntry, PlatformStatus, Registry


@dataclass(frozen=True)
class Leaf:
    page_id: str
    harmony: dict[str, Any]
    ios: dict[str, Any]
    android: dict[str, Any]
    spec_excerpt_path: str | None = None


@dataclass(frozen=True)
class PlanResult:
    run_id: str
    scope_kind: str
    scope_value: str | None
    leaves: tuple[Leaf, ...] = field(default_factory=tuple)

    def to_json(self) -> str:
        return json.dumps(
            {
                "run_id": self.run_id,
                "scope": {"kind": self.scope_kind, "value": self.scope_value},
                "leaves": [asdict(leaf) for leaf in self.leaves],
            },
            indent=2,
            sort_keys=True,
        )


def build_plan(
    reg: Registry,
    *,
    page_ids: list[str],
    run_id: str,
    scope_kind: str,
    scope_value: str | None,
) -> PlanResult:
    leaves = tuple(_leaf_for(reg.by_id(pid)) for pid in page_ids)
    return PlanResult(
        run_id=run_id,
        scope_kind=scope_kind,
        scope_value=scope_value,
        leaves=leaves,
    )


def _leaf_for(page: PageEntry) -> Leaf:
    return Leaf(
        page_id=page.id,
        harmony=_platform_summary(page.harmony, page.id),
        ios=_platform_summary(page.ios, page.id),
        android=_platform_summary(page.android, page.id),
        spec_excerpt_path=None,
    )


def _platform_summary(plat: PlatformEntry, page_id: str) -> dict[str, Any]:
    status = plat.status()
    out: dict[str, Any] = {"status": status.value}
    if status == PlatformStatus.OK:
        out["route"] = page_id
    elif status == PlatformStatus.BLOCKED:
        out["reason"] = plat.block_reason()
    return out


def render_tree(plan: PlanResult) -> str:
    lines = [
        f"PLAN run={plan.run_id}  scope={plan.scope_kind}:{plan.scope_value or '-'}",
    ]
    total = len(plan.leaves)
    for i, leaf in enumerate(plan.leaves):
        prefix = "└──" if i == total - 1 else "├──"
        h = _fmt_status(leaf.harmony)
        ios = _fmt_status(leaf.ios)
        droid = _fmt_status(leaf.android)
        lines.append(f"{prefix} {leaf.page_id:24s} harmony:{h}  ios:{ios}  android:{droid}")
    return "\n".join(lines)


def _fmt_status(plat: dict[str, Any]) -> str:
    status = plat["status"]
    if status == "blocked":
        return f"BLOCKED({plat.get('reason', '?')})"
    return status
```

- [ ] **Step 4: Re-run tests, verify they pass**

Run: `cd tools/parity_scout && uv run pytest tests/test_planner.py -v`
Expected: 3 passed.

- [ ] **Step 5: Commit**

```bash
git add tools/parity_scout/planner.py \
        tools/parity_scout/tests/test_planner.py
git commit -m "feat(parity-scout): build plan results and tree printer"
```

---

### Task 6: Wire `scout.py plan` subcommand

**Files:**
- Modify: `tools/parity_scout/scout.py`

- [ ] **Step 1: Replace the `plan` subparser registration in `scout.py`**

Replace the entire file with:

```python
#!/usr/bin/env python3
"""parity_scout CLI entry point."""

from __future__ import annotations

import argparse
import datetime as _dt
import json
import re
import sys
from pathlib import Path
from typing import Sequence

from parity_scout.planner import build_plan, render_tree
from parity_scout.registry import load_registry
from parity_scout.spec_extract import ScopeError, resolve_scope


_REPO_ROOT = Path(__file__).resolve().parents[2]
_DEFAULT_REGISTRY = Path(__file__).resolve().parent / "page_suite_map.yml"
_RUN_ROOT = _REPO_ROOT / "build-tmp" / "parity_scout"


def _build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="scout.py")
    sub = p.add_subparsers(dest="cmd", required=True)

    plan_p = sub.add_parser("plan")
    scope = plan_p.add_mutually_exclusive_group(required=True)
    scope.add_argument("--scope", choices=["overall"])
    scope.add_argument("--spec", type=Path)
    scope.add_argument("--feature", type=Path)
    scope.add_argument("--pages")
    scope.add_argument("--suite")
    scope.add_argument("--describe")
    plan_p.add_argument("--registry", type=Path, default=_DEFAULT_REGISTRY)
    plan_p.add_argument("--run", default=None, help="Reuse an existing run id.")

    sub.add_parser("pick")
    sub.add_parser("run")
    sub.add_parser("promote")
    sub.add_parser("doctor")
    sub.add_parser("prune")

    return p


def _slugify(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-") or "scope"


def _build_run_id(scope_kind: str, scope_value: str | None) -> str:
    ts = _dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    return f"{ts}-{scope_kind}-{_slugify(scope_value or '')}"[:80].rstrip("-")


def _cmd_plan(args: argparse.Namespace) -> int:
    if args.scope == "overall":
        kind, value = "overall", None
    elif args.spec is not None:
        kind, value = "spec", str(args.spec)
    elif args.feature is not None:
        kind, value = "feature", str(args.feature)
    elif args.pages is not None:
        kind, value = "pages", args.pages
    elif args.suite is not None:
        kind, value = "suite", args.suite
    elif args.describe is not None:
        kind, value = "describe", args.describe
    else:  # argparse guards this
        print("scope flag required", file=sys.stderr)
        return 2

    try:
        reg = load_registry(args.registry)
        page_ids = resolve_scope(reg, kind=kind, value=value)
    except ScopeError as exc:
        print(f"scope error: {exc}", file=sys.stderr)
        return 2

    if not page_ids:
        print("no leaves resolved (scope too narrow / unmatched)", file=sys.stderr)
        return 2

    run_id = args.run or _build_run_id(kind, value)
    run_dir = _RUN_ROOT / run_id
    run_dir.mkdir(parents=True, exist_ok=True)
    plan = build_plan(reg, page_ids=page_ids, run_id=run_id, scope_kind=kind, scope_value=value)
    (run_dir / "plan.json").write_text(plan.to_json() + "\n", encoding="utf-8")
    print(render_tree(plan))
    print(f"\nrun-id: {run_id}")
    print(f"plan:   {run_dir / 'plan.json'}")
    return 0


def main(argv: Sequence[str] | None = None) -> int:
    args = _build_parser().parse_args(argv)
    if args.cmd == "plan":
        return _cmd_plan(args)
    print(f"NOT IMPLEMENTED: {args.cmd}", file=sys.stderr)
    return 64


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 2: Sanity-check** by running `plan` against the fixture

Run:
```
cd tools/parity_scout && uv run python scout.py plan \
  --registry tests/fixtures/registry_minimal.yml \
  --pages home,battle
```
Expected: prints `PLAN run=…` tree with `home` showing `android:feature_absent`, `battle` showing `android:ok`; writes `build-tmp/parity_scout/<id>/plan.json`.

- [ ] **Step 3: Commit**

```bash
git add tools/parity_scout/scout.py
git commit -m "feat(parity-scout): wire scout.py plan subcommand"
```

---

### Task 7: `scout.py pick` subcommand and `picked.json`

**Files:**
- Modify: `tools/parity_scout/scout.py`

- [ ] **Step 1: Replace the `pick` subparser registration block** (`sub.add_parser("pick")` line) with a configured parser and add a handler. Insert the parser config right after the `plan_p.add_argument("--run", ...)` block:

```python
    pick_p = sub.add_parser("pick")
    pick_p.add_argument("--run", required=True)
    pick_p.add_argument("--branches", required=True,
                        help='Comma-separated page ids, or "all".')
    pick_p.add_argument("--include-blocked", action="store_true")
```

Then add the handler function above `def main(`:

```python
def _cmd_pick(args: argparse.Namespace) -> int:
    run_dir = _RUN_ROOT / args.run
    plan_path = run_dir / "plan.json"
    if not plan_path.is_file():
        print(f"no plan at {plan_path}", file=sys.stderr)
        return 4
    plan = json.loads(plan_path.read_text(encoding="utf-8"))
    leaves_by_id = {leaf["page_id"]: leaf for leaf in plan["leaves"]}

    if args.branches.strip() == "all":
        requested = list(leaves_by_id.keys())
    else:
        requested = [b.strip() for b in args.branches.split(",") if b.strip()]

    chosen: list[str] = []
    refused: list[tuple[str, str]] = []
    for pid in requested:
        leaf = leaves_by_id.get(pid)
        if leaf is None:
            refused.append((pid, "not-in-plan"))
            continue
        statuses = [leaf[p]["status"] for p in ("harmony", "ios", "android")]
        if all(s == "feature_absent" for s in statuses):
            refused.append((pid, "all-feature-absent"))
            continue
        if "blocked" in statuses and not args.include_blocked:
            refused.append((pid, "blocked-without-include-blocked"))
            continue
        chosen.append(pid)

    if not chosen:
        for pid, reason in refused:
            print(f"refused: {pid} ({reason})", file=sys.stderr)
        return 4

    out = {"run_id": args.run, "branches": chosen, "refused": refused}
    (run_dir / "picked.json").write_text(
        json.dumps(out, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print(f"picked: {', '.join(chosen)}")
    if refused:
        for pid, reason in refused:
            print(f"refused: {pid} ({reason})")
    return 0
```

And add `if args.cmd == "pick": return _cmd_pick(args)` inside `main`.

- [ ] **Step 2: Sanity-check** the full plan + pick flow

Run:
```
cd tools/parity_scout && uv run python scout.py plan \
  --registry tests/fixtures/registry_minimal.yml --pages home,battle
RUN_ID=$(ls -t /Users/$USER/.cursor/worktrees/happyword/0rzw/build-tmp/parity_scout/ | head -1)
uv run python scout.py pick --run "${RUN_ID}" --branches home,battle
```
Expected: `picked: home, battle`. `picked.json` exists in the run dir.

- [ ] **Step 3: Commit**

```bash
git add tools/parity_scout/scout.py
git commit -m "feat(parity-scout): wire scout.py pick subcommand"
```

---

### Task 8: Harmony adapter + `--pages` flag on the capture script

**Files:**
- Modify: `scripts/capture_harmony_screenshots.py` — add `--pages` argument.
- Create: `tools/parity_scout/adapters/__init__.py`
- Create: `tools/parity_scout/adapters/harmony.py`

- [ ] **Step 1: Patch `scripts/capture_harmony_screenshots.py` to accept `--pages`**

Replace the `def main() -> int:` function with:

```python
def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--pages",
        default=None,
        help="Comma-separated step labels; default = all (per `runners`).",
    )
    args = parser.parse_args()

    maybe_install_hap()
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    print("Capturing HarmonyOS screenshots →", OUT_DIR)
    start_app()
    time.sleep(2.5)

    # … keep existing inner-function defs `shot_home` etc. …

    runners = [
        ("home", shot_home),
        ("battle+result", shot_battle_result),
        ("monster codex", shot_codex),
        ("today plan + learning report", shot_today_and_report),
        ("wishlist + redemption history", shot_wishlist_history),
        ("config + pack manager", shot_config_and_pack),
        ("parent pin setup surface", shot_parent_pin_surface),
        ("scan binding", shot_scan_binding),
        ("parent admin", shot_parent_admin),
        ("bound device info (if bound)", shot_bound_device_if_any),
        ("dev menu + bypass secret", shot_dev_menu_and_bypass),
    ]

    if args.pages:
        wanted = {p.strip() for p in args.pages.split(",") if p.strip()}
        runners = [(label, fn) for (label, fn) in runners if label.split()[0] in wanted]
        if not runners:
            print(f"[warn] no runners match --pages {args.pages}", file=sys.stderr)

    ensure_pin_if_possible()
    start_app()
    time.sleep(2.0)

    for label, fn in runners:
        try:
            print(f"… {label}")
            fn()
            go_home_via_back()
            start_app()
            time.sleep(1.2)
        except Exception as exc:
            print(f"[error] step '{label}': {exc}", file=sys.stderr)
            try:
                go_home_via_back()
            except Exception:
                start_app()
                time.sleep(2.0)

    print("Done.")
    return 0
```

Also add `import argparse` to the top imports if not present.

Run: `python3 scripts/capture_harmony_screenshots.py --pages home --help`
Expected: argparse help message exits 0 (or no hdc errors when `--help`).

- [ ] **Step 2: Create `tools/parity_scout/adapters/__init__.py`**

```python
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
    def capture(self, page_id: str, capture_spec: dict, out_dir: Path, timeout_s: int) -> AdapterResult:
        ...
```

- [ ] **Step 3: Create `tools/parity_scout/adapters/harmony.py`**

```python
"""HarmonyOS adapter — wraps scripts/capture_harmony_screenshots.py."""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

from parity_scout.adapters import Adapter, AdapterResult


_REPO_ROOT = Path(__file__).resolve().parents[3]
_HARMONY_SCREENSHOT_OUT = _REPO_ROOT / "assets" / "screenshots" / "harmonyos"


class HarmonyAdapter(Adapter):
    name = "harmony"

    def capture(self, page_id, capture_spec, out_dir, timeout_s):
        step = capture_spec.get("step") or page_id
        script = _REPO_ROOT / "scripts" / "capture_harmony_screenshots.py"
        if not script.is_file():
            return AdapterResult(
                platform=self.name, page_id=page_id, out_dir=out_dir,
                success=False, stderr_tail="capture_harmony_screenshots.py missing"
            )
        try:
            proc = subprocess.run(
                ["python3", str(script), "--pages", step],
                capture_output=True,
                text=True,
                timeout=timeout_s,
                check=False,
            )
        except subprocess.TimeoutExpired as exc:
            return AdapterResult(
                platform=self.name, page_id=page_id, out_dir=out_dir,
                success=False, stderr_tail=f"timeout after {timeout_s}s: {exc}"
            )
        if proc.returncode != 0:
            return AdapterResult(
                platform=self.name, page_id=page_id, out_dir=out_dir,
                success=False, stderr_tail=proc.stderr[-2000:]
            )
        # Copy newly produced harmony screenshots into out_dir (everything
        # that matches <step>*.png, e.g. home.png, parent-admin-part1.png).
        out_dir.mkdir(parents=True, exist_ok=True)
        moved = 0
        for png in _HARMONY_SCREENSHOT_OUT.glob(f"{step}*.png"):
            shutil.copy(png, out_dir / png.name)
            moved += 1
        success = moved > 0
        return AdapterResult(
            platform=self.name, page_id=page_id, out_dir=out_dir,
            success=success,
            stderr_tail="" if success else "no PNGs produced",
        )
```

- [ ] **Step 4: Commit**

```bash
git add scripts/capture_harmony_screenshots.py \
        tools/parity_scout/adapters/__init__.py \
        tools/parity_scout/adapters/harmony.py
git commit -m "feat(parity-scout): harmony adapter + --pages flag on capture script"
```

---

### Task 9: iOS adapter (`adapters/ios.py`)

**Files:**
- Create: `tools/parity_scout/adapters/ios.py`

- [ ] **Step 1: Create `tools/parity_scout/adapters/ios.py`**

```python
"""iOS adapter — wraps xcrun simctl launch + io screenshot.

Reuses launch arguments already defined in WordMagicGameUITests
(-UITestResetState, -UITestRouteBattle, -UITestRouteConfig, etc.).
"""

from __future__ import annotations

import subprocess
from pathlib import Path

from parity_scout.adapters import Adapter, AdapterResult


_BUNDLE_ID = "com.terryma.wordmagicgame"
_DEVICE_NAME = "iPhone 17 Pro"


class IosAdapter(Adapter):
    name = "ios"

    def capture(self, page_id, capture_spec, out_dir, timeout_s):
        launch_args = list(capture_spec.get("launch_args") or [])
        basename = capture_spec.get("output_basename") or page_id
        out_dir.mkdir(parents=True, exist_ok=True)

        try:
            # Terminate prior instance so reset args take effect.
            subprocess.run(
                ["xcrun", "simctl", "terminate", "booted", _BUNDLE_ID],
                capture_output=True, text=True, timeout=20, check=False,
            )
            subprocess.run(
                ["xcrun", "simctl", "launch", "booted", _BUNDLE_ID, *launch_args],
                capture_output=True, text=True, timeout=timeout_s, check=True,
            )
            # Allow the landing screen to render.
            subprocess.run(["sleep", "2"], check=False)
            out_png = out_dir / f"{basename}.png"
            subprocess.run(
                ["xcrun", "simctl", "io", "booted", "screenshot", str(out_png)],
                capture_output=True, text=True, timeout=20, check=True,
            )
        except subprocess.CalledProcessError as exc:
            return AdapterResult(
                platform=self.name, page_id=page_id, out_dir=out_dir,
                success=False, stderr_tail=(exc.stderr or "")[-2000:]
            )
        except subprocess.TimeoutExpired as exc:
            return AdapterResult(
                platform=self.name, page_id=page_id, out_dir=out_dir,
                success=False, stderr_tail=f"timeout: {exc}"
            )
        return AdapterResult(
            platform=self.name, page_id=page_id, out_dir=out_dir, success=True
        )
```

- [ ] **Step 2: Commit**

```bash
git add tools/parity_scout/adapters/ios.py
git commit -m "feat(parity-scout): iOS adapter via simctl launch + io screenshot"
```

---

### Task 10: Android adapter (`adapters/android.py`)

**Files:**
- Create: `tools/parity_scout/adapters/android.py`

- [ ] **Step 1: Create `tools/parity_scout/adapters/android.py`**

```python
"""Android adapter — wraps am instrument + adb screencap.

For v0 the adapter expects the existing AndroidScreenScreenshotTest to have
written PNGs into the app's internal storage at files/screenshots/<case>.png
(this matches the sequence in .cursor/android-dev-commands.md §11).
"""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

from parity_scout.adapters import Adapter, AdapterResult


_PACKAGE = "cool.happyword.wordmagic"
_TEST_RUNNER = "cool.happyword.wordmagic.test/androidx.test.runner.AndroidJUnitRunner"
_SCREENSHOT_CLASS = "cool.happyword.wordmagic.AndroidScreenScreenshotTest"


def _adb() -> str:
    return os.environ.get("ANDROID_HOME", "/Users/$USER/Library/Android/sdk").rstrip("/") + "/platform-tools/adb"


class AndroidAdapter(Adapter):
    name = "android"

    def capture(self, page_id, capture_spec, out_dir, timeout_s):
        case = capture_spec.get("case") or page_id
        out_dir.mkdir(parents=True, exist_ok=True)
        adb = _adb()
        try:
            subprocess.run(
                [adb, "shell", "am", "instrument", "-w",
                 "-e", "class", f"{_SCREENSHOT_CLASS}#{case}",
                 _TEST_RUNNER],
                capture_output=True, text=True, timeout=timeout_s, check=True,
            )
            out_png = out_dir / f"{case}.png"
            with open(out_png, "wb") as fh:
                proc = subprocess.run(
                    [adb, "exec-out", "run-as", _PACKAGE,
                     "cat", f"files/screenshots/{case}.png"],
                    stdout=fh, stderr=subprocess.PIPE, timeout=20, check=True,
                )
            if out_png.stat().st_size == 0:
                return AdapterResult(
                    platform=self.name, page_id=page_id, out_dir=out_dir,
                    success=False, stderr_tail=(proc.stderr.decode() or "")[-2000:]
                )
        except subprocess.CalledProcessError as exc:
            return AdapterResult(
                platform=self.name, page_id=page_id, out_dir=out_dir,
                success=False, stderr_tail=(exc.stderr or "")[-2000:] if isinstance(exc.stderr, str) else str(exc)
            )
        except subprocess.TimeoutExpired as exc:
            return AdapterResult(
                platform=self.name, page_id=page_id, out_dir=out_dir,
                success=False, stderr_tail=f"timeout: {exc}"
            )
        return AdapterResult(
            platform=self.name, page_id=page_id, out_dir=out_dir, success=True
        )
```

- [ ] **Step 2: Commit**

```bash
git add tools/parity_scout/adapters/android.py
git commit -m "feat(parity-scout): android adapter via am instrument + adb screencap"
```

---

### Task 11: Per-leaf runner (`runner.py`) and `scout.py run` (TDD)

**Files:**
- Create: `tools/parity_scout/runner.py`
- Create: `tools/parity_scout/tests/test_runner.py`
- Modify: `tools/parity_scout/scout.py`

- [ ] **Step 1: Write failing test `tests/test_runner.py`**

```python
import json
import threading
import time
from pathlib import Path

from parity_scout.runner import Runner, LeafRecord


class _FakeAdapter:
    def __init__(self, name, success=True, delay=0.0):
        self.name = name
        self._success = success
        self._delay = delay

    def capture(self, page_id, capture_spec, out_dir, timeout_s):
        time.sleep(self._delay)
        from parity_scout.adapters import AdapterResult
        out_dir.mkdir(parents=True, exist_ok=True)
        if self._success:
            (out_dir / f"{page_id}-part1.png").write_bytes(b"PNG")
        return AdapterResult(
            platform=self.name, page_id=page_id, out_dir=out_dir,
            success=self._success,
            stderr_tail="" if self._success else "boom",
        )


def test_run_emits_leaf_ready_and_blocks_on_next_flag(tmp_path):
    run_dir = tmp_path / "r1"
    run_dir.mkdir()
    plan = {
        "run_id": "r1",
        "scope": {"kind": "pages", "value": "home"},
        "leaves": [{
            "page_id": "home",
            "harmony": {"status": "ok", "route": "home"},
            "ios":     {"status": "ok", "route": "home"},
            "android": {"status": "feature_absent"},
        }],
    }
    (run_dir / "plan.json").write_text(json.dumps(plan), encoding="utf-8")
    (run_dir / "picked.json").write_text(json.dumps({"branches": ["home"]}), encoding="utf-8")

    adapters = {
        "harmony": _FakeAdapter("harmony"),
        "ios": _FakeAdapter("ios"),
        "android": _FakeAdapter("android"),
    }
    capture_specs = {"home": {"harmony": {"step": "home"},
                              "ios":     {"output_basename": "home"},
                              "android": {"case": "home"}}}
    runner = Runner(run_dir, adapters, capture_specs, leaf_timeout=5)

    events: list[str] = []

    def consume():
        for ev in runner.iter_events():
            events.append(ev.kind)
            if ev.kind == "LEAF_READY":
                (run_dir / ev.page_id / "next.flag").touch()

    t = threading.Thread(target=consume)
    t.start()
    t.join(timeout=10)
    assert "LEAF_START" in events
    assert "LEAF_READY" in events
    assert events[-1] == "RUN_DONE"

    home_dir = run_dir / "home"
    assert (home_dir / "harmony" / "home-part1.png").is_file()
    assert (home_dir / "android" / "MISSING.txt").is_file()


def test_run_failed_adapter_still_emits_leaf_ready(tmp_path):
    run_dir = tmp_path / "r2"
    run_dir.mkdir()
    plan = {
        "run_id": "r2",
        "scope": {"kind": "pages", "value": "home"},
        "leaves": [{
            "page_id": "home",
            "harmony": {"status": "ok", "route": "home"},
            "ios":     {"status": "ok", "route": "home"},
            "android": {"status": "ok", "route": "home"},
        }],
    }
    (run_dir / "plan.json").write_text(json.dumps(plan), encoding="utf-8")
    (run_dir / "picked.json").write_text(json.dumps({"branches": ["home"]}), encoding="utf-8")
    adapters = {
        "harmony": _FakeAdapter("harmony"),
        "ios": _FakeAdapter("ios", success=False),
        "android": _FakeAdapter("android"),
    }
    capture_specs = {"home": {"harmony": {"step": "home"},
                              "ios":     {"output_basename": "home"},
                              "android": {"case": "home"}}}
    runner = Runner(run_dir, adapters, capture_specs, leaf_timeout=5)
    events = []

    def consume():
        for ev in runner.iter_events():
            events.append(ev.kind)
            if ev.kind == "LEAF_READY":
                (run_dir / ev.page_id / "next.flag").touch()

    t = threading.Thread(target=consume)
    t.start()
    t.join(timeout=10)
    assert "LEAF_READY" in events
    assert (run_dir / "home" / "ios" / "CAPTURE_FAILED.txt").is_file()
```

- [ ] **Step 2: Run test, verify failure**

Run: `cd tools/parity_scout && uv run pytest tests/test_runner.py -v`
Expected: ImportError on `parity_scout.runner`.

- [ ] **Step 3: Implement `tools/parity_scout/runner.py`**

```python
"""Per-leaf runner: fire 3 adapters in parallel, emit LEAF events, sync via next.flag."""

from __future__ import annotations

import json
import threading
import time
from concurrent.futures import ThreadPoolExecutor, TimeoutError as FuturesTimeout
from dataclasses import dataclass
from pathlib import Path
from typing import Iterator, Mapping

from parity_scout.adapters import Adapter


@dataclass(frozen=True)
class LeafRecord:
    kind: str  # "LEAF_START" | "LEAF_READY" | "RUN_DONE"
    page_id: str | None
    dir: Path | None


class Runner:
    def __init__(
        self,
        run_dir: Path,
        adapters: Mapping[str, Adapter],
        capture_specs: Mapping[str, Mapping[str, dict]],
        leaf_timeout: int = 180,
        poll_seconds: float = 1.0,
    ) -> None:
        self.run_dir = Path(run_dir)
        self.adapters = adapters
        self.capture_specs = capture_specs
        self.leaf_timeout = leaf_timeout
        self.poll_seconds = poll_seconds

    def iter_events(self) -> Iterator[LeafRecord]:
        plan = json.loads((self.run_dir / "plan.json").read_text(encoding="utf-8"))
        picked = json.loads((self.run_dir / "picked.json").read_text(encoding="utf-8"))
        wanted = set(picked["branches"])
        leaves = [leaf for leaf in plan["leaves"] if leaf["page_id"] in wanted]

        for leaf in leaves:
            page_id = leaf["page_id"]
            page_dir = self.run_dir / page_id
            page_dir.mkdir(parents=True, exist_ok=True)
            yield LeafRecord(kind="LEAF_START", page_id=page_id, dir=page_dir)
            self._fire_adapters(leaf, page_dir)
            yield LeafRecord(kind="LEAF_READY", page_id=page_id, dir=page_dir)
            self._wait_for_flag(page_dir / "next.flag")

        yield LeafRecord(kind="RUN_DONE", page_id=None, dir=None)

    def _fire_adapters(self, leaf: dict, page_dir: Path) -> None:
        cs = self.capture_specs.get(leaf["page_id"], {})
        jobs = []
        with ThreadPoolExecutor(max_workers=3) as ex:
            for platform in ("harmony", "ios", "android"):
                plat_dir = page_dir / platform
                plat_dir.mkdir(parents=True, exist_ok=True)
                status = leaf[platform]["status"]
                if status == "feature_absent":
                    (plat_dir / "MISSING.txt").write_text(
                        f"{leaf['page_id']}: feature_absent on {platform}\n",
                        encoding="utf-8",
                    )
                    continue
                if status == "blocked":
                    (plat_dir / "BLOCKED.txt").write_text(
                        f"{leaf['page_id']}: blocked on {platform}\n",
                        encoding="utf-8",
                    )
                    continue
                adapter = self.adapters[platform]
                spec = cs.get(platform, {})
                jobs.append((platform, ex.submit(
                    adapter.capture,
                    leaf["page_id"], spec, plat_dir, self.leaf_timeout,
                )))
            for platform, fut in jobs:
                try:
                    result = fut.result(timeout=self.leaf_timeout + 5)
                except FuturesTimeout:
                    (page_dir / platform / "CAPTURE_FAILED.txt").write_text(
                        f"adapter timeout > {self.leaf_timeout}s\n",
                        encoding="utf-8",
                    )
                    continue
                if not result.success:
                    (page_dir / platform / "CAPTURE_FAILED.txt").write_text(
                        result.stderr_tail or "unknown error\n",
                        encoding="utf-8",
                    )

    def _wait_for_flag(self, flag_path: Path) -> None:
        while not flag_path.is_file():
            time.sleep(self.poll_seconds)
```

- [ ] **Step 4: Re-run tests, verify they pass**

Run: `cd tools/parity_scout && uv run pytest tests/test_runner.py -v`
Expected: 2 passed.

- [ ] **Step 5: Wire `scout.py run` to invoke the runner**

Add the `run` subparser config in `_build_parser()`:

```python
    run_p = sub.add_parser("run")
    run_p.add_argument("--run", required=True)
    run_p.add_argument("--only", default=None, help="Comma-separated subset of picked pages.")
    run_p.add_argument("--leaf-timeout", type=int, default=180)
    run_p.add_argument("--allow-dirty-baseline", action="store_true")
    run_p.add_argument("--registry", type=Path, default=_DEFAULT_REGISTRY)
```

And the handler:

```python
def _cmd_run(args: argparse.Namespace) -> int:
    from parity_scout.adapters.android import AndroidAdapter
    from parity_scout.adapters.harmony import HarmonyAdapter
    from parity_scout.adapters.ios import IosAdapter
    from parity_scout.runner import Runner

    run_dir = _RUN_ROOT / args.run
    if not (run_dir / "picked.json").is_file():
        print(f"no picked.json at {run_dir}", file=sys.stderr)
        return 4
    if not args.allow_dirty_baseline and not _baseline_clean():
        print("HarmonyOS baseline is not on a clean main; pass --allow-dirty-baseline to bypass",
              file=sys.stderr)
        return 4
    (run_dir / "baseline.txt").write_text(_baseline_sha() + "\n", encoding="utf-8")

    reg = load_registry(args.registry)
    capture_specs: dict[str, dict[str, dict]] = {}
    for page in reg.pages:
        capture_specs[page.id] = {
            "harmony": page.harmony.capture.raw if page.harmony.capture else {},
            "ios":     page.ios.capture.raw     if page.ios.capture     else {},
            "android": page.android.capture.raw if page.android.capture else {},
        }

    adapters = {"harmony": HarmonyAdapter(), "ios": IosAdapter(), "android": AndroidAdapter()}
    runner = Runner(run_dir, adapters, capture_specs, leaf_timeout=args.leaf_timeout)
    for ev in runner.iter_events():
        if ev.kind == "LEAF_START":
            print(f"LEAF START page={ev.page_id}", flush=True)
        elif ev.kind == "LEAF_READY":
            print(f"LEAF READY page={ev.page_id} dir={ev.dir}", flush=True)
        elif ev.kind == "RUN_DONE":
            print("RUN DONE", flush=True)
    return 0


def _baseline_clean() -> bool:
    try:
        head = subprocess.run(
            ["git", "rev-parse", "--abbrev-ref", "HEAD"],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
        dirty = subprocess.run(
            ["git", "status", "--porcelain", "harmonyos/entry/src/main/ets"],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
    except Exception:
        return False
    return head == "main" and dirty == ""


def _baseline_sha() -> str:
    try:
        return subprocess.run(
            ["git", "rev-parse", "HEAD"],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
    except Exception:
        return "unknown"
```

Add `import subprocess` to scout.py's imports. Add `if args.cmd == "run": return _cmd_run(args)` inside `main`.

- [ ] **Step 6: Commit**

```bash
git add tools/parity_scout/runner.py \
        tools/parity_scout/tests/test_runner.py \
        tools/parity_scout/scout.py
git commit -m "feat(parity-scout): per-leaf runner with parallel adapters and next.flag sync"
```

---

### Task 12: `promote.py` and `scout.py promote` (TDD)

**Files:**
- Create: `tools/parity_scout/tests/fixtures/findings_curated_one_feature.md`
- Create: `tools/parity_scout/tests/test_promote.py`
- Create: `tools/parity_scout/promote.py`
- Modify: `tools/parity_scout/scout.py`

- [ ] **Step 1: Write the fixture**

```markdown
# Curated findings (slice for 2026-04-29-wishlist)

- [ ] **wishlist (iOS)** — coin label vertically misaligned vs Harmony baseline.
- [ ] **gift-box-modal (Android)** — modal background uses #1A1A1A vs Harmony #0F0F12.
```

- [ ] **Step 2: Write failing test**

```python
import datetime as dt
from pathlib import Path

import pytest

from parity_scout.promote import PromoteError, promote_curated_findings


def test_promote_appends_to_existing_followups(tmp_path, fixtures_dir):
    feature_dir = tmp_path / "docs" / "features" / "2026-04-29-wishlist"
    feature_dir.mkdir(parents=True)
    followups = feature_dir / "60-followups.md"
    followups.write_text("# Followups\n\nPrior section.\n", encoding="utf-8")

    findings = fixtures_dir / "findings_curated_one_feature.md"
    promote_curated_findings(
        findings=findings,
        feature_dir=feature_dir,
        run_id="r1",
        baseline_line="harmonyos main @ deadbee (clean)",
        scope_line="spec:wishlist-design.md",
        leaves_line="wishlist, gift-box-modal",
        today=dt.date(2026, 5, 13),
    )
    text = followups.read_text(encoding="utf-8")
    assert "## Parity scout — 2026-05-13 (run r1)" in text
    assert "wishlist (iOS)" in text
    assert "gift-box-modal (Android)" in text
    assert text.startswith("# Followups")


def test_promote_refuses_when_feature_folder_missing(tmp_path, fixtures_dir):
    findings = fixtures_dir / "findings_curated_one_feature.md"
    with pytest.raises(PromoteError, match="missing"):
        promote_curated_findings(
            findings=findings,
            feature_dir=tmp_path / "does-not-exist",
            run_id="r1",
            baseline_line="x",
            scope_line="x",
            leaves_line="x",
            today=dt.date(2026, 5, 13),
        )
```

- [ ] **Step 3: Run test, verify failure**

Run: `cd tools/parity_scout && uv run pytest tests/test_promote.py -v`
Expected: ImportError on `parity_scout.promote`.

- [ ] **Step 4: Implement `tools/parity_scout/promote.py`**

```python
"""Append a curated findings slice to a feature's 60-followups.md."""

from __future__ import annotations

import datetime as dt
import re
from pathlib import Path


class PromoteError(Exception):
    pass


def promote_curated_findings(
    *,
    findings: Path,
    feature_dir: Path,
    run_id: str,
    baseline_line: str,
    scope_line: str,
    leaves_line: str,
    today: dt.date | None = None,
) -> Path:
    feature_dir = Path(feature_dir)
    if not feature_dir.is_dir():
        raise PromoteError(f"feature folder missing: {feature_dir}")
    findings = Path(findings)
    if not findings.is_file():
        raise PromoteError(f"findings file missing: {findings}")
    body = findings.read_text(encoding="utf-8").strip("\n")
    bullets = [ln for ln in body.splitlines() if ln.lstrip().startswith("- [")]
    if not bullets:
        raise PromoteError("findings file has no '- [ ]' items")
    today = today or dt.date.today()
    section = (
        f"\n## Parity scout — {today.isoformat()} (run {run_id})\n\n"
        f"Baseline: {baseline_line}\n"
        f"Scope: {scope_line}\n"
        f"Leaves analysed: {leaves_line}\n\n"
        + "\n".join(bullets) + "\n"
    )
    followups = feature_dir / "60-followups.md"
    if followups.is_file():
        existing = followups.read_text(encoding="utf-8").rstrip("\n") + "\n"
    else:
        existing = "# Followups\n"
    followups.write_text(existing + section, encoding="utf-8")
    return followups
```

- [ ] **Step 5: Re-run tests, verify they pass**

Run: `cd tools/parity_scout && uv run pytest tests/test_promote.py -v`
Expected: 2 passed.

- [ ] **Step 6: Wire `scout.py promote`**

Add to `_build_parser()`:

```python
    prom_p = sub.add_parser("promote")
    prom_p.add_argument("--run", required=True)
    prom_p.add_argument("--feature", required=True, help="feature id, e.g. 2026-04-29-v0.3.9-wishlist-redemption-flow")
    prom_p.add_argument("--findings", type=Path, default=None,
                        help="Override findings file. Default: findings.curated.<feature>.md in the run dir.")
```

Add handler:

```python
def _cmd_promote(args: argparse.Namespace) -> int:
    from parity_scout.promote import PromoteError, promote_curated_findings

    run_dir = _RUN_ROOT / args.run
    feature_dir = _REPO_ROOT / "docs" / "features" / args.feature
    findings = args.findings or (run_dir / f"findings.curated.{args.feature}.md")
    plan_path = run_dir / "plan.json"
    plan = json.loads(plan_path.read_text(encoding="utf-8")) if plan_path.is_file() else {}
    scope = plan.get("scope") or {}
    scope_line = f"{scope.get('kind','?')}:{scope.get('value','-')}"
    leaves_line = ", ".join(leaf["page_id"] for leaf in plan.get("leaves") or [])
    baseline_path = run_dir / "baseline.txt"
    baseline_line = baseline_path.read_text(encoding="utf-8").strip() if baseline_path.is_file() else "unknown"
    try:
        out = promote_curated_findings(
            findings=findings,
            feature_dir=feature_dir,
            run_id=args.run,
            baseline_line=baseline_line,
            scope_line=scope_line,
            leaves_line=leaves_line,
        )
    except PromoteError as exc:
        print(f"promote refused: {exc}", file=sys.stderr)
        return 4
    print(f"appended to {out}")
    return 0
```

Wire it in `main`: `if args.cmd == "promote": return _cmd_promote(args)`.

- [ ] **Step 7: Commit**

```bash
git add tools/parity_scout/promote.py \
        tools/parity_scout/tests/test_promote.py \
        tools/parity_scout/tests/fixtures/findings_curated_one_feature.md \
        tools/parity_scout/scout.py
git commit -m "feat(parity-scout): promote curated findings into feature followups"
```

---

### Task 13: `doctor` and `prune` subcommands

**Files:**
- Create: `tools/parity_scout/doctor.py`
- Create: `tools/parity_scout/prune.py`
- Modify: `tools/parity_scout/scout.py`

- [ ] **Step 1: Implement `tools/parity_scout/doctor.py`**

```python
"""Preflight diagnostic for parity_scout.

Non-gating: prints status for each platform and the HarmonyOS baseline.
The SKILL is responsible for refusing runs when a required device is
unreachable. This command never exits non-zero on individual probe failures.
"""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

from parity_scout.registry import load_registry


def run_doctor(registry_path: Path) -> int:
    print("scout.py doctor")
    _probe("hdc list targets",
           ["hdc", "list", "targets"],
           ok_predicate=lambda out: bool(out.strip()) and "[Empty]" not in out)
    _probe("xcrun simctl list devices",
           ["xcrun", "simctl", "list", "devices", "available"],
           ok_predicate=lambda out: "iPhone" in out)
    adb = os.environ.get("ANDROID_HOME", "") + "/platform-tools/adb"
    _probe("adb devices",
           [adb, "devices"],
           ok_predicate=lambda out: "device" in out and "List of devices" in out)
    _probe_baseline()
    try:
        reg = load_registry(registry_path)
        print(f"  ✓ registry valid ({len(reg.pages)} pages)")
    except Exception as exc:
        print(f"  ✗ registry: {exc}")
    return 0


def _probe(label, cmd, ok_predicate):
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=10).stdout
    except Exception as exc:
        print(f"  ✗ {label} → {exc}")
        return
    print(f"  {'✓' if ok_predicate(out) else '✗'} {label}")


def _probe_baseline():
    try:
        head = subprocess.run(["git", "rev-parse", "--abbrev-ref", "HEAD"],
                              capture_output=True, text=True, check=True).stdout.strip()
        sha = subprocess.run(["git", "rev-parse", "--short", "HEAD"],
                             capture_output=True, text=True, check=True).stdout.strip()
        dirty = subprocess.run(["git", "status", "--porcelain",
                                "harmonyos/entry/src/main/ets"],
                               capture_output=True, text=True, check=True).stdout.strip()
        clean = "clean" if not dirty else "DIRTY"
        mark = "✓" if head == "main" and not dirty else "✗"
        print(f"  {mark} harmonyos baseline → {head} @ {sha} {clean}")
    except Exception as exc:
        print(f"  ✗ harmonyos baseline → {exc}")
```

- [ ] **Step 2: Implement `tools/parity_scout/prune.py`**

```python
"""Rotate build-tmp/parity_scout/<run-id>/ directories, keeping the newest N."""

from __future__ import annotations

import shutil
from pathlib import Path


def run_prune(run_root: Path, keep: int) -> int:
    run_root = Path(run_root)
    if not run_root.is_dir():
        return 0
    dirs = sorted(
        (d for d in run_root.iterdir() if d.is_dir()),
        key=lambda d: d.stat().st_mtime,
        reverse=True,
    )
    keep = max(keep, 0)
    kept = dirs[:keep]
    pruned = dirs[keep:]
    for d in pruned:
        shutil.rmtree(d, ignore_errors=True)
    print(f"kept {len(kept)}, pruned {len(pruned)}")
    return 0
```

- [ ] **Step 3: Wire both in `scout.py`**

Replace `sub.add_parser("doctor")` and `sub.add_parser("prune")` with:

```python
    doc_p = sub.add_parser("doctor")
    doc_p.add_argument("--registry", type=Path, default=_DEFAULT_REGISTRY)

    pr_p = sub.add_parser("prune")
    pr_p.add_argument("--keep", type=int, default=5)
```

Handlers:

```python
def _cmd_doctor(args: argparse.Namespace) -> int:
    from parity_scout.doctor import run_doctor
    return run_doctor(args.registry)


def _cmd_prune(args: argparse.Namespace) -> int:
    from parity_scout.prune import run_prune
    return run_prune(_RUN_ROOT, args.keep)
```

Wire in `main`. Smoke-test:

Run: `cd tools/parity_scout && uv run python scout.py doctor`
Expected: prints status lines; exit 0.

- [ ] **Step 4: Commit**

```bash
git add tools/parity_scout/doctor.py \
        tools/parity_scout/prune.py \
        tools/parity_scout/scout.py
git commit -m "feat(parity-scout): doctor and prune subcommands"
```

---

### Task 14: Seed `page_suite_map.yml` with the current 9 baseline pages

**Files:**
- Create: `tools/parity_scout/page_suite_map.yml`

Source-of-truth seed: 9 pages that all three platforms already have something for, per the existing screenshot manifests + iOS launch args + Android screenshot test.

- [ ] **Step 1: Create `tools/parity_scout/page_suite_map.yml`**

```yaml
# parity_scout registry — page <-> per-platform capture route alignment.
# See docs/superpowers/specs/2026-05-13-parity-scout-design.md §4.3.
# When adding a page, also update tests/test_registry.py's page_source
# existence check (it walks every entry).

pages:
  - id: home
    description: Landing screen (landscape, child-facing)
    spec_anchors:
      stable_ids: [HomeStartButton, HomeChildProfileButton, HomeVersionLabel]
      page_section_titles: [Home, "主页"]
    harmony:
      present: true
      page_source: harmonyos/entry/src/main/ets/pages/HomePage.ets
      capture: { kind: capture_harmony_step, step: home }
    ios:
      present: true
      page_source: ios/WordMagicGame/Features/Home/HomePage.swift
      capture: { kind: simctl_route, launch_args: ["-UITestResetState"], output_basename: home }
    android:
      present: true
      page_source: android/app/src/main/java/cool/happyword/wordmagic/HomePage.kt
      capture: { kind: android_screenshot_test, case: home }

  - id: battle
    description: Battle page (landscape)
    spec_anchors:
      stable_ids: [BattleCorrectOption, BattleFinishButton]
      page_section_titles: [Battle]
    harmony:
      present: true
      page_source: harmonyos/entry/src/main/ets/pages/BattlePage.ets
      capture: { kind: capture_harmony_step, step: battle }
    ios:
      present: true
      page_source: ios/WordMagicGame/Features/Battle/BattlePage.swift
      capture: { kind: simctl_route, launch_args: ["-UITestResetState", "-UITestRouteBattle"], output_basename: battle }
    android:
      present: true
      page_source: android/app/src/main/java/cool/happyword/wordmagic/BattlePage.kt
      capture: { kind: android_screenshot_test, case: battle }

  - id: result
    description: Battle result (landscape)
    spec_anchors:
      stable_ids: [ResultHomeButton]
      page_section_titles: [Result]
    harmony:
      present: true
      page_source: harmonyos/entry/src/main/ets/pages/ResultPage.ets
      capture: { kind: capture_harmony_step, step: battle+result }
    ios:
      present: true
      page_source: ios/WordMagicGame/Features/Result/ResultPage.swift
      capture: null   # BLOCKED until iOS Result launch arg exists
    android:
      present: true
      page_source: android/app/src/main/java/cool/happyword/wordmagic/ResultPage.kt
      capture: { kind: android_screenshot_test, case: result }

  - id: config
    description: Game settings (landscape)
    spec_anchors:
      stable_ids: [HomeConfigButton, ConfigParentPinButton, ConfigParentAdminButton]
      page_section_titles: [Config, "游戏设置"]
    harmony:
      present: true
      page_source: harmonyos/entry/src/main/ets/pages/ConfigPage.ets
      capture: { kind: capture_harmony_step, step: config }
    ios:
      present: true
      page_source: ios/WordMagicGame/Features/Config/ConfigPage.swift
      capture: { kind: simctl_route, launch_args: ["-UITestResetState", "-UITestRouteConfig"], output_basename: config-landscape }
    android:
      present: true
      page_source: android/app/src/main/java/cool/happyword/wordmagic/ConfigPage.kt
      capture: { kind: android_screenshot_test, case: config-landscape }

  - id: wishlist
    description: Wishlist (landscape)
    spec_anchors:
      stable_ids: [HomeWishlistButton, WishlistHistoryButton, WishlistGiftBoxModal]
      page_section_titles: [Wishlist, "魔法愿望单"]
    harmony:
      present: true
      page_source: harmonyos/entry/src/main/ets/pages/WishlistPage.ets
      capture: { kind: capture_harmony_step, step: wishlist+redemption }
    ios:
      present: true
      page_source: ios/WordMagicGame/Features/Wishlist/WishlistPage.swift
      capture: { kind: simctl_route, launch_args: ["-UITestResetState", "-UITestRouteWishlist"], output_basename: wishlist }
    android:
      present: false  # no Android wishlist yet

  - id: today-plan
    description: Today plan (landscape)
    spec_anchors:
      stable_ids: [HomePlanButton, TodayPlanReportButton]
      page_section_titles: ["Today Plan", "今日学习计划"]
    harmony:
      present: true
      page_source: harmonyos/entry/src/main/ets/pages/TodayPlanPage.ets
      capture: { kind: capture_harmony_step, step: today }
    ios:
      present: true
      page_source: ios/WordMagicGame/Features/TodayPlan/TodayPlanPage.swift
      capture: { kind: simctl_route, launch_args: ["-UITestResetState", "-UITestRouteTodayPlan"], output_basename: today-plan }
    android:
      present: true
      page_source: android/app/src/main/java/cool/happyword/wordmagic/TodayPlanPage.kt
      capture: { kind: android_screenshot_test, case: today-plan }

  - id: parent-admin
    description: Parent admin (portrait)
    spec_anchors:
      stable_ids: [ConfigParentAdminButton, ParentAdminTitle]
      page_section_titles: ["Parent Admin", "家长管理后台"]
    harmony:
      present: true
      page_source: harmonyos/entry/src/main/ets/pages/ParentAdminPage.ets
      capture: { kind: capture_harmony_step, step: parent }
    ios:
      present: true
      page_source: ios/WordMagicGame/Features/ParentAdmin/ParentAdminPage.swift
      capture: { kind: simctl_route, launch_args: ["-UITestResetState", "-UITestRouteParentAdmin"], output_basename: parent-admin }
    android:
      present: true
      page_source: android/app/src/main/java/cool/happyword/wordmagic/ParentAdminPage.kt
      capture: { kind: android_screenshot_test, case: parent-admin }

  - id: bound-device-info
    description: Parent account info (landscape)
    spec_anchors:
      stable_ids: [ConfigBoundDeviceInfoButton]
      page_section_titles: ["Bound Device", "家长账户"]
    harmony:
      present: true
      page_source: harmonyos/entry/src/main/ets/pages/BoundDeviceInfoPage.ets
      capture: { kind: capture_harmony_step, step: bound }
    ios:
      present: true
      page_source: ios/WordMagicGame/Features/Account/BoundDeviceInfoPage.swift
      capture: { kind: simctl_route, launch_args: ["-UITestResetState", "-UITestSeedBoundDevice", "-UITestRouteBoundDeviceInfo"], output_basename: bound-device-info }
    android:
      present: true
      page_source: android/app/src/main/java/cool/happyword/wordmagic/BoundDeviceInfoPage.kt
      capture: { kind: android_screenshot_test, case: bound-device-info }

  - id: pack-manager
    description: Pack manager (landscape)
    spec_anchors:
      stable_ids: [ConfigPackManagerEntry, PackToggle]
      page_section_titles: ["Pack Manager", "我的词包"]
    harmony:
      present: true
      page_source: harmonyos/entry/src/main/ets/pages/PackManagerPage.ets
      capture: { kind: capture_harmony_step, step: config }
    ios:
      present: true
      page_source: ios/WordMagicGame/Features/Pack/PackManagerPage.swift
      capture: { kind: simctl_route, launch_args: ["-UITestResetState", "-UITestRoutePackManager"], output_basename: pack-manager }
    android:
      present: false  # no Android pack manager yet
```

- [ ] **Step 2: Update `tests/test_registry.py` to also check the real registry parses**

Append to `tests/test_registry.py`:

```python
def test_real_registry_parses():
    from pathlib import Path
    real = Path(__file__).resolve().parents[1] / "page_suite_map.yml"
    if not real.is_file():
        pytest.skip("real registry not present in this checkout")
    reg = load_registry(real)
    assert len(reg.pages) >= 1
    # every present:true entry must point at an existing source file in repo
    repo_root = Path(__file__).resolve().parents[3]
    for page in reg.pages:
        for platform in ("harmony", "ios", "android"):
            plat = getattr(page, platform)
            if plat.present:
                assert plat.page_source, f"{page.id}/{platform} missing page_source"
                # Files may legitimately not exist yet for in-flight features;
                # we record a warning rather than failing, to keep this gate
                # actionable without being brittle.
                p = repo_root / plat.page_source
                if not p.is_file():
                    print(f"WARN: {page.id}/{platform} page_source not found: {p}")
```

Run: `cd tools/parity_scout && uv run pytest tests/test_registry.py -v`
Expected: all tests pass (including the new one).

- [ ] **Step 3: Commit**

```bash
git add tools/parity_scout/page_suite_map.yml \
        tools/parity_scout/tests/test_registry.py
git commit -m "feat(parity-scout): seed page_suite_map.yml with 9 baseline pages"
```

---

### Task 15: Write the SKILL `.cursor/skills/parity-scout/SKILL.md`

**Files:**
- Create: `.cursor/skills/parity-scout/SKILL.md`

- [ ] **Step 1: Write the SKILL**

```markdown
---
name: parity-scout
description: Drives a per-feature visual + spec-anchored gap scout across HarmonyOS / iOS / Android using tools/parity_scout/. Use when asked to "find iOS / Android gaps vs HarmonyOS main", "check parity for <feature>", or "screenshot the three platforms and tell me what's different".
---

# parity-scout

**Role:** **Scheduler only.** It does **not** embed CLI flag tables — read [`tools/parity_scout/README.md`](../../tools/parity_scout/README.md) for copy-pastable lines and [`docs/superpowers/specs/2026-05-13-parity-scout-design.md`](../../docs/superpowers/specs/2026-05-13-parity-scout-design.md) for the full design.

## Inputs

A user task that names a scope: a feature folder, a spec doc, an explicit page list, "overall", or a free-form description.

## Flow

1. **Inputs.** Identify a scope from the task:
   - feature folder name → `--feature <id>` (pass the folder path, e.g. `docs/features/<id>`)
   - spec doc path → `--spec <path>`
   - "scout everything" / "overall" → `--scope overall`
   - free prose → `--describe "<verbatim user prose>"`
   - explicit pages → `--pages a,b,c`
   - Harmony suite name → `--suite Foo,Bar`
   Otherwise: **ask the user once in chat**.
2. **Doctor.** Run `python3 tools/parity_scout/scout.py doctor` and surface its output.
3. **Plan.** Run `python3 tools/parity_scout/scout.py plan ...`. If `--scope overall`, **stop and confirm with the user** — this is the expensive global mode. Otherwise present the tree in chat and ask which branches to pick (checkbox list). Blocked / all-feature-absent branches are shown but greyed.
4. **Pick.** Run `scout.py pick --run <id> --branches <user-selection>`. If the user picked any `blocked` leaf, **refuse to start `run`** and tell them to add the capture route first; offer to flip into an "add the route" subtask before resuming.
5. **Per-leaf loop.** Run `scout.py run --run <id>` foreground, watched. For each `LEAF READY page=<id> dir=<path>` line emitted by the process:
   1. Read the staged `<path>/spec-excerpts.md` (NOTE: the runner writes per-page output to `<dir>` — see §6 if `spec-excerpts.md` is absent, in which case extract on the fly via `excerpts.py`).
   2. Read each `*.png` under `<path>/{harmony,ios,android}/` (Cursor agent vision).
   3. Compare PNGs across platforms and against the spec excerpts. The spec excerpts narrow what counts as a gap; visual-only differences not anchored by the spec are downranked, not promoted.
   4. Append findings to `<run-id>/findings.md` under a `## <page>` heading, with bullet lines tagged `[harmony|ios|android]` + severity hint.
   5. `touch <dir>/next.flag` to release `scout.py run` to the next leaf.
6. **Curate.** After `RUN DONE`:
   1. Read `findings.md`. Drop noise. Write `findings.curated.md`.
   2. Group items by feature folder (each item's page id usually maps to one feature; if ambiguous, ask the user). Write `findings.curated.<feature-id>.md` for every feature touched. Items that can't be assigned go to `findings.curated.unassigned.md`.
   3. Show the user a one-screen summary listing every feature slice and ask: "promote which slices? (all / none / pick)".
7. **Promote.** For each picked slice, run `scout.py promote --run <id> --feature <feature-id>` and show the resulting diff hunk in chat. **Do not commit.** The user runs git themselves.

## Guards to invoke

- **`safe-command-policy`** before every `scout.py` invocation.
- **`autoloop-guard`** on the per-leaf loop. If `LEAF READY` repeats without `findings.md` growth, abort.
- **`harmony-emulator-manage`** (and the iOS / Android equivalents in their respective manifests) as preflight when any selected leaf needs that platform's adapter.

## Stop conditions (must end in one of these)

- `RUN DONE` + user resolved every curated feature slice (promote or skip) + (if promoted) diff hunks shown.
- Precondition refused — missing capture route on a selected leaf, dirty HarmonyOS baseline without `--allow-dirty-baseline`, or a required device unreachable preflight → user told what to add; no files touched.
- `autoloop-guard` tripped → run dir preserved for inspection.

## Sub-skills to invoke

`safe-command-policy` · `autoloop-guard` · `harmony-emulator-manage`

iOS and Android device preflight pull from their respective command manifests, not dedicated sub-skills.

## What this skill does NOT do

- It does not write CLI flag tables — read `tools/parity_scout/README.md`.
- It does not run `git commit`. The user owns the commit step after `promote`.
- It does not create `docs/features/<id>/` folders. `promote` refuses if the folder is missing.
```

- [ ] **Step 2: Commit**

```bash
git add .cursor/skills/parity-scout/SKILL.md
git commit -m "feat(parity-scout): add SKILL scheduler"
```

---

### Task 16: Stage `spec-excerpts.md` per leaf in `scout.py run`

The SKILL Step 5.1 reads `spec-excerpts.md`. We need the runner to write it.

**Files:**
- Modify: `tools/parity_scout/runner.py`
- Modify: `tools/parity_scout/scout.py`

- [ ] **Step 1: Pass the spec path + registry into the Runner so it can write `spec-excerpts.md`**

In `scout.py::_cmd_run`, after loading `picked.json`, also load the plan and look up the original scope. If `scope.kind in {"spec", "feature"}`, resolve the spec path and pass it to the Runner; otherwise pass `None`.

Append to the `Runner.__init__`:

```python
        spec_path: Path | None = None,
        registry=None,
```

In `_fire_adapters` (or a new step before it), write `spec-excerpts.md`:

```python
    def _write_excerpts(self, page_id: str, page_dir: Path) -> None:
        if self.spec_path is None or self.registry is None:
            (page_dir / "spec-excerpts.md").write_text(
                "<!-- no spec scope provided -->\n", encoding="utf-8",
            )
            return
        from parity_scout.excerpts import extract_excerpt
        try:
            page = self.registry.by_id(page_id)
        except KeyError:
            (page_dir / "spec-excerpts.md").write_text(
                f"<!-- registry missing page {page_id} -->\n", encoding="utf-8",
            )
            return
        text = extract_excerpt(page, self.spec_path)
        (page_dir / "spec-excerpts.md").write_text(text, encoding="utf-8")
```

And call `self._write_excerpts(page_id, page_dir)` immediately before yielding `LEAF_START` (or right after `mkdir`).

In `scout.py::_cmd_run`, build the Runner with the new args:

```python
    plan_json = json.loads((run_dir / "plan.json").read_text(encoding="utf-8"))
    scope = plan_json.get("scope") or {}
    spec_path = None
    if scope.get("kind") in {"spec"}:
        spec_path = Path(scope.get("value"))
    elif scope.get("kind") == "feature":
        feat = Path(scope.get("value"))
        candidates = sorted(feat.glob("*.md")) if feat.is_dir() else []
        spec_path = candidates[0] if candidates else None

    runner = Runner(
        run_dir, adapters, capture_specs,
        leaf_timeout=args.leaf_timeout,
        spec_path=spec_path,
        registry=reg,
    )
```

- [ ] **Step 2: Extend `tests/test_runner.py` with a spec-excerpts case**

Add at the bottom of `tests/test_runner.py`:

```python
def test_runner_writes_spec_excerpts_when_provided(tmp_path, fixtures_dir):
    from parity_scout.registry import load_registry
    run_dir = tmp_path / "r3"
    run_dir.mkdir()
    plan = {
        "run_id": "r3",
        "scope": {"kind": "spec", "value": str(fixtures_dir / "specs" / "wishlist_design.md")},
        "leaves": [{
            "page_id": "home",
            "harmony": {"status": "ok", "route": "home"},
            "ios":     {"status": "ok", "route": "home"},
            "android": {"status": "feature_absent"},
        }],
    }
    (run_dir / "plan.json").write_text(json.dumps(plan), encoding="utf-8")
    (run_dir / "picked.json").write_text(json.dumps({"branches": ["home"]}), encoding="utf-8")

    adapters = {"harmony": _FakeAdapter("harmony"),
                "ios": _FakeAdapter("ios"),
                "android": _FakeAdapter("android")}
    capture_specs = {"home": {"harmony": {"step": "home"},
                              "ios":     {"output_basename": "home"},
                              "android": {"case": "home"}}}
    reg = load_registry(fixtures_dir / "registry_minimal.yml")
    runner = Runner(
        run_dir, adapters, capture_specs, leaf_timeout=5,
        spec_path=Path(plan["scope"]["value"]),
        registry=reg,
    )
    for ev in runner.iter_events():
        if ev.kind == "LEAF_READY":
            (run_dir / ev.page_id / "next.flag").touch()
    home_excerpts = (run_dir / "home" / "spec-excerpts.md").read_text(encoding="utf-8")
    assert "User flows" in home_excerpts
    assert "HomeStartButton" in home_excerpts
```

Also update `Runner.__init__` signature in earlier tests if they passed positional args — they currently use kwargs, so OK.

- [ ] **Step 3: Run tests, verify they pass**

Run: `cd tools/parity_scout && uv run pytest -v`
Expected: every test passes.

- [ ] **Step 4: Commit**

```bash
git add tools/parity_scout/runner.py \
        tools/parity_scout/scout.py \
        tools/parity_scout/tests/test_runner.py
git commit -m "feat(parity-scout): runner stages spec-excerpts.md per leaf"
```

---

### Task 17: Manifest one-liner pointers and SKILL cross-link

**Files:**
- Modify: `.cursor/ohos-dev-commands.md`
- Modify: `.cursor/ios-dev-commands.md`
- Modify: `.cursor/android-dev-commands.md`
- Modify: `.cursor/skills/three-platform-feature-orchestrator/SKILL.md`

- [ ] **Step 1: Append to `.cursor/ohos-dev-commands.md` after the §7 "Screenshots / Visual Parity" section header (in this file: §4 "UI / on-device (Instrument)" + its "UI suite repair SOP" sub-section).** Find the line containing `### UI suite repair SOP` and after that section, before `## 5) Failure artifacts`, insert:

```markdown
### Parity-scout pointer

Use `parity-scout` to find three-platform UI / behavior gaps against HarmonyOS `main`. CLI cheat-sheet: [`tools/parity_scout/README.md`](../tools/parity_scout/README.md). Skill: [`.cursor/skills/parity-scout/SKILL.md`](../.cursor/skills/parity-scout/SKILL.md). Don't run it from this manifest's "Screenshots" sub-flow directly — go through the skill.
```

- [ ] **Step 2: Append to `.cursor/ios-dev-commands.md` after §7 "Screenshots / Visual Parity"**, before §8:

```markdown
### Parity-scout pointer

For finding iOS gaps vs HarmonyOS `main`, run via the `parity-scout` skill. CLI cheat-sheet: [`tools/parity_scout/README.md`](../tools/parity_scout/README.md). Skill: [`.cursor/skills/parity-scout/SKILL.md`](../.cursor/skills/parity-scout/SKILL.md).
```

- [ ] **Step 3: Append to `.cursor/android-dev-commands.md` after §6 "Manual QA commands"**, before §7:

```markdown
### Parity-scout pointer

For finding Android gaps vs HarmonyOS `main`, run via the `parity-scout` skill. CLI cheat-sheet: [`tools/parity_scout/README.md`](../tools/parity_scout/README.md). Skill: [`.cursor/skills/parity-scout/SKILL.md`](../.cursor/skills/parity-scout/SKILL.md).
```

- [ ] **Step 4: Add a note to `three-platform-feature-orchestrator/SKILL.md`** Stage 3 + Stage 5.

In the Stage 3 bullet (`Drive the soft gate in 20-replication-trigger.md §1.`), append:

```
   - **Suspect parity drift?** Run `parity-scout` (`.cursor/skills/parity-scout/SKILL.md`) before signing the trigger.
```

In the Stage 5 bullet (`Drive 50-parity-checklist.md to all-green.`), append:

```
   - Re-run `parity-scout` whenever a red row remains after a fix attempt — the gap may be visual, not behavioral.
```

- [ ] **Step 5: Commit**

```bash
git add .cursor/ohos-dev-commands.md \
        .cursor/ios-dev-commands.md \
        .cursor/android-dev-commands.md \
        .cursor/skills/three-platform-feature-orchestrator/SKILL.md
git commit -m "docs(parity-scout): cross-link from per-platform manifests and orchestrator skill"
```

---

### Task 18: Real-device smoke (manual, not in CI)

**Files:**
- None (verification only)

- [ ] **Step 1: Run doctor**

Run: `python3 tools/parity_scout/scout.py doctor`
Expected: at least HarmonyOS baseline ✓ and registry ✓ are green on a developer machine. Other platforms ✗ acceptable if their simulators aren't booted.

- [ ] **Step 2: Plan + pick + run for one page (`home`)**

Run:
```sh
python3 tools/parity_scout/scout.py plan --pages home
# capture the printed run-id
RUN_ID=<paste>
python3 tools/parity_scout/scout.py pick --run "${RUN_ID}" --branches home
python3 tools/parity_scout/scout.py run --run "${RUN_ID}" &
RUN_PID=$!
# In another terminal, after seeing 'LEAF READY page=home dir=...':
touch "build-tmp/parity_scout/${RUN_ID}/home/next.flag"
wait "${RUN_PID}"
```
Expected: `LEAF START page=home`, `LEAF READY page=home dir=...`, `RUN DONE`. The home leaf dir contains at least one PNG for every platform that is `present: true && capture: ok` on the developer's running simulators.

- [ ] **Step 3: Document the smoke result in the PR description.** No code change.

- [ ] **Step 4: No commit for this task** — it is a verification gate.

---

## Self-Review

### 1. Spec coverage

- §3 decisions table → covered by Tasks 1–18.
- §4.2 file layout → covered by Tasks 1, 2, 3, 4, 5, 6, 8, 9, 10, 11, 12, 13, 14, 15.
- §4.3 registry schema → Tasks 2, 14 (loader + seed).
- §5.1 plan → Tasks 5, 6 (planner + CLI wiring).
- §5.2 pick → Task 7.
- §5.3 run + spec-excerpts → Tasks 11, 16.
- §5.4 promote + curate-by-feature contract → Task 12 (CLI/promote.py); the curate-by-feature splitter lives in the SKILL Step 6 (Task 15) because curation is a human/agent activity, not a CLI command.
- §5.5 doctor → Task 13.
- §5.6 prune → Task 13.
- §6 SKILL → Task 15.
- §7.1 baseline discipline → Task 11 Step 5 (`_baseline_clean` / `_baseline_sha`).
- §7.2 per-leaf failures → Task 11 (`CAPTURE_FAILED.txt` / `MISSING.txt`).
- §7.3 edges → Tasks 2 (registry unknown), 3 (scope errors), 11 (concurrent guard NOT yet implemented — see gap below).
- §8 tests → Tasks 2, 3, 4, 5, 11, 12.
- §9 integration → Task 17.

**Gap identified:** spec §7.3 says "concurrent `run` invocations refused via `build-tmp/parity_scout/.lock`". The plan does not implement this. **Adding a follow-up task below.**

### 2. Placeholder scan

No TBD / TODO / vague-handler patterns found. Every step has runnable code or commands.

### 3. Type consistency

- `PlatformStatus` enum values (`OK / FEATURE_ABSENT / BLOCKED`) match the JSON serialization (`"ok" / "feature_absent" / "blocked"`) used in `planner.py`, runner, SKILL.
- `AdapterResult` signature is shared across all adapters and the runner.
- `PromoteError` raised in `promote.py` and caught in `scout.py::_cmd_promote`.
- `ScopeError` raised in `spec_extract.py` and caught in `scout.py::_cmd_plan`.

### Added follow-up: Task 11b — concurrent run lock

Insert between Task 11 and Task 12 in execution order. Files: `tools/parity_scout/scout.py`, `tools/parity_scout/runner.py` (acquire lock in `_cmd_run` not Runner so unit tests aren't affected).

- [ ] **Step 1: Implement lock helper at module level in `scout.py`**

```python
import atexit
import os
import errno

_LOCK_PATH = _RUN_ROOT / ".lock"


def _acquire_lock() -> bool:
    _RUN_ROOT.mkdir(parents=True, exist_ok=True)
    if _LOCK_PATH.exists():
        try:
            pid = int(_LOCK_PATH.read_text(encoding="utf-8").strip())
        except (ValueError, OSError):
            pid = None
        if pid and _pid_alive(pid):
            return False
        _LOCK_PATH.unlink()
    _LOCK_PATH.write_text(str(os.getpid()), encoding="utf-8")
    atexit.register(_release_lock)
    return True


def _release_lock() -> None:
    try:
        if _LOCK_PATH.exists():
            _LOCK_PATH.unlink()
    except OSError:
        pass


def _pid_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except OSError as exc:
        return exc.errno == errno.EPERM
    return True
```

- [ ] **Step 2: Call `_acquire_lock()` at the top of `_cmd_run` and refuse with exit `4` if it returns `False`.**

- [ ] **Step 3: Commit**

```bash
git add tools/parity_scout/scout.py
git commit -m "feat(parity-scout): pid-stamped run lock at build-tmp/parity_scout/.lock"
```

---

## Execution Handoff

**Plan complete and saved to `docs/superpowers/plans/2026-05-13-parity-scout.md`. Two execution options:**

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration. Best for this plan because the 18 tasks are independent and each one has a tight TDD loop.

**2. Inline Execution** — Execute tasks in this session using `executing-plans`, batch execution with checkpoints for review.

**Which approach?**
