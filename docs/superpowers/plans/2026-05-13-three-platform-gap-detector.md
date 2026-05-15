# Three-Platform Gap Detector Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a repo-local detector that plans, runs, and classifies iOS / Android parity gaps against the latest HarmonyOS baseline without repairing those gaps.

**Architecture:** Implement a small Python stdlib package under `tools/gap_detector/` with pure units for scope planning, manifest persistence, command planning, evidence indexing, and gap classification. Add a CLI that defaults to planning and dry-run execution, with explicit `--execute` for device/simulator commands, and install matching Codex/Cursor skills that keep agents in evidence-only detector mode.

**Tech Stack:** Python 3 standard library, `unittest`, repo-local command manifests, HarmonyOS `hdc` / `scripts/run_ui_tests.sh`, iOS `xcodebuild` / `simctl`, Android Gradle / `adb`, Codex and Cursor skill Markdown.

---

## Source Spec

- `docs/superpowers/specs/2026-05-13-three-platform-gap-detector-design.md`

## File Map

- Modify: `.gitignore` - ignore `.gap-detector/` run artifacts.
- Create: `tools/gap_detector/__init__.py` - package metadata and public version.
- Create: `tools/gap_detector/__main__.py` - `python3 -m tools.gap_detector` entrypoint.
- Create: `tools/gap_detector/cli.py` - CLI argument parsing for `plan`, `run`, and `classify`.
- Create: `tools/gap_detector/scope_planner.py` - scope resolution, `overall` branch paths, and candidate probing.
- Create: `tools/gap_detector/manifest.py` - dataclasses for manifest, probe, runner, and JSON-compatible YAML persistence.
- Create: `tools/gap_detector/runners/__init__.py` - runner package exports.
- Create: `tools/gap_detector/runners/commands.py` - command recipes and dry-run / execute wrapper.
- Create: `tools/gap_detector/evidence.py` - artifact paths and evidence existence index.
- Create: `tools/gap_detector/classifier.py` - gap categories, severity, and classifier rules.
- Create: `tools/gap_detector/README.md` - usage, modes, artifact policy, and non-goals.
- Create: `tools/gap_detector/tests/__init__.py` - unittest package marker.
- Create: `tools/gap_detector/tests/test_scope_planner.py` - scoped, ambiguous, absent, and `overall` planner tests.
- Create: `tools/gap_detector/tests/test_manifest.py` - manifest round-trip and status tests.
- Create: `tools/gap_detector/tests/test_classifier.py` - gap classifier tests.
- Create: `tools/gap_detector/tests/test_cli.py` - CLI smoke tests through subprocess.
- Create: `.agents/skills/three-platform-gap-detector/SKILL.md` - Codex-local skill.
- Create: `.cursor/skills/three-platform-gap-detector/SKILL.md` - Cursor skill with same rules.
- Create: `tools/gap_detector/tests/test_skill_docs.py` - validates skill trigger and hard rules.

## Commands

Run these from the repo root unless a step says otherwise:

```sh
python3 -m unittest discover tools/gap_detector/tests
python3 -m tools.gap_detector plan --scope docs/superpowers/specs/2026-05-13-three-platform-gap-detector-design.md --run-name smoke-spec
python3 -m tools.gap_detector plan --scope overall --run-name smoke-overall
git diff --check
```

The first implementation does not need external Python dependencies. It stores machine-readable manifests as JSON-compatible YAML content in `.yaml` files so future implementations can swap to PyYAML without changing the logical schema.

## Tasks

### Task 1: Package Scaffold And Artifact Ignore

**Files:**
- Modify: `.gitignore`
- Create: `tools/gap_detector/__init__.py`
- Create: `tools/gap_detector/__main__.py`
- Create: `tools/gap_detector/cli.py`
- Create: `tools/gap_detector/tests/__init__.py`
- Create: `tools/gap_detector/tests/test_cli.py`

- [ ] **Step 1: Write the failing CLI package smoke test**

Create `tools/gap_detector/tests/__init__.py`:

```python
"""Tests for the repo-local three-platform gap detector."""
```

Create `tools/gap_detector/tests/test_cli.py`:

```python
import subprocess
import sys
import unittest


class CliSmokeTest(unittest.TestCase):
    def test_module_help_prints_commands(self) -> None:
        result = subprocess.run(
            [sys.executable, "-m", "tools.gap_detector", "--help"],
            check=False,
            capture_output=True,
            text=True,
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("plan", result.stdout)
        self.assertIn("run", result.stdout)
        self.assertIn("classify", result.stdout)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the smoke test and verify it fails**

Run:

```sh
python3 -m unittest tools.gap_detector.tests.test_cli -v
```

Expected: FAIL with `No module named tools.gap_detector`.

- [ ] **Step 3: Add the package entrypoint and minimal CLI**

Create `tools/gap_detector/__init__.py`:

```python
"""Repo-local three-platform gap detector."""

__version__ = "0.1.0"
```

Create `tools/gap_detector/__main__.py`:

```python
from .cli import main


if __name__ == "__main__":
    raise SystemExit(main())
```

Create `tools/gap_detector/cli.py`:

```python
from __future__ import annotations

import argparse
from collections.abc import Sequence


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="python3 -m tools.gap_detector",
        description="Plan, run, and classify three-platform parity gap probes.",
    )
    subcommands = parser.add_subparsers(dest="command", required=True)

    plan = subcommands.add_parser("plan", help="Create a scoped probe manifest")
    plan.add_argument("--scope", required=True, help="Feature/spec/plan/page/suite path or overall")
    plan.add_argument("--run-name", default="", help="Stable run name for artifact paths")

    run = subcommands.add_parser("run", help="Run one manifest probe")
    run.add_argument("--manifest", required=True, help="Path to manifest.yaml")
    run.add_argument("--probe", required=True, help="Probe id to run")
    run.add_argument("--execute", action="store_true", help="Execute platform commands instead of dry-run")

    classify = subcommands.add_parser("classify", help="Classify evidence for a run")
    classify.add_argument("--run", required=True, help="Path to a .gap-detector run directory")

    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    parser.parse_args(argv)
    return 0
```

- [ ] **Step 4: Ignore detector run artifacts**

Append this block to `.gitignore` after the `.compare-screenshots/` entry:

```gitignore
# Local gap detector run artifacts
.gap-detector/
```

- [ ] **Step 5: Run the smoke test and diff check**

Run:

```sh
python3 -m unittest tools.gap_detector.tests.test_cli -v
git diff --check
```

Expected: unittest PASS; `git diff --check` exits 0.

- [ ] **Step 6: Commit scaffold**

Run:

```sh
git add .gitignore tools/gap_detector
git commit -m "feat: scaffold three-platform gap detector"
```

### Task 2: Scope Planner

**Files:**
- Create: `tools/gap_detector/scope_planner.py`
- Create: `tools/gap_detector/tests/test_scope_planner.py`
- Modify: `tools/gap_detector/cli.py`

- [ ] **Step 1: Write failing planner tests**

Create `tools/gap_detector/tests/test_scope_planner.py`:

```python
import tempfile
import unittest
from pathlib import Path

from tools.gap_detector.scope_planner import (
    OVERALL_BRANCH_PATHS,
    ScopeMode,
    ScopePlanner,
)


class ScopePlannerTest(unittest.TestCase):
    def test_spec_scope_resolves_to_single_candidate(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            spec = root / "docs" / "superpowers" / "specs" / "2026-05-13-demo-design.md"
            spec.parent.mkdir(parents=True)
            spec.write_text("# Demo\n", encoding="utf-8")

            plan = ScopePlanner(root).plan(str(spec.relative_to(root)))

            self.assertEqual(plan.mode, ScopeMode.SPEC)
            self.assertFalse(plan.confirmation_required)
            self.assertEqual([item.path for item in plan.candidates], [spec.relative_to(root)])

    def test_absent_scope_creates_confirmation_required_search_plan(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            plan = ScopePlanner(Path(tmp)).plan("")

            self.assertEqual(plan.mode, ScopeMode.SEARCH)
            self.assertTrue(plan.confirmation_required)
            self.assertGreaterEqual(len(plan.candidates), 6)
            self.assertEqual(plan.candidates[0].label, "Core Loop")

    def test_overall_scope_requires_confirmation_and_uses_branch_paths(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            plan = ScopePlanner(Path(tmp)).plan("overall")

            self.assertEqual(plan.mode, ScopeMode.OVERALL)
            self.assertTrue(plan.confirmation_required)
            self.assertEqual([item.label for item in plan.candidates], list(OVERALL_BRANCH_PATHS))

    def test_page_scope_maps_to_known_docs_and_tests(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "harmonyos/entry/src/ohosTest/ets/test").mkdir(parents=True)
            (root / "ios/WordMagicGameUITests").mkdir(parents=True)
            (root / "android/app/src/androidTest/java/cool/happyword/wordmagic").mkdir(parents=True)
            (root / "harmonyos/entry/src/ohosTest/ets/test/ConfigFlow.ui.test.ets").write_text("", encoding="utf-8")
            (root / "ios/WordMagicGameUITests/WordMagicGameUITests.swift").write_text("", encoding="utf-8")
            (root / "android/app/src/androidTest/java/cool/happyword/wordmagic/ConfigCloudSyncVisibilityTest.kt").write_text("", encoding="utf-8")

            plan = ScopePlanner(root).plan("Config")

            self.assertEqual(plan.mode, ScopeMode.PAGE)
            self.assertFalse(plan.confirmation_required)
            self.assertEqual(plan.candidates[0].label, "Config")
            self.assertIn(Path("harmonyos/entry/src/ohosTest/ets/test/ConfigFlow.ui.test.ets"), plan.candidates[0].sources)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run planner tests and verify they fail**

Run:

```sh
python3 -m unittest tools.gap_detector.tests.test_scope_planner -v
```

Expected: FAIL with `No module named tools.gap_detector.scope_planner`.

- [ ] **Step 3: Implement scope planner**

Create `tools/gap_detector/scope_planner.py`:

```python
from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path


class ScopeMode(str, Enum):
    FEATURE = "feature"
    SPEC = "spec"
    PLAN = "plan"
    PAGE = "page"
    SUITE = "suite"
    OVERALL = "overall"
    SEARCH = "search"


OVERALL_BRANCH_PATHS: dict[str, tuple[str, ...]] = {
    "Core Loop": ("Home", "Battle", "Result", "question types", "pronunciation", "timer", "monster effects"),
    "Growth": ("Wishlist", "redemption history", "Monster Codex", "Today Plan", "Learning Report"),
    "Parent/Admin": ("Config", "Parent PIN", "ParentAdmin", "LessonDraftReview"),
    "Cloud": ("parent binding", "bound child profile", "pack sync", "global/family packs"),
    "Debug": ("DevMenu", "preview routing", "bypass secret", "version-label entry"),
    "Contracts": ("shared fixtures", "server contracts", "DTO decoding", "API shape parity"),
}


PAGE_SOURCE_HINTS: dict[str, tuple[str, ...]] = {
    "home": (
        "harmonyos/entry/src/ohosTest/ets/test/AdventureFlow.ui.test.ets",
        "ios/WordMagicGameUITests/WordMagicGameUITests.swift",
        "android/app/src/androidTest/java/cool/happyword/wordmagic/SmokeTest.kt",
    ),
    "battle": (
        "harmonyos/entry/src/ohosTest/ets/test/RoutingFlow.ui.test.ets",
        "ios/WordMagicGameUITests/WordMagicGameUITests.swift",
        "android/app/src/androidTest/java/cool/happyword/wordmagic/SmokeTest.kt",
    ),
    "config": (
        "harmonyos/entry/src/ohosTest/ets/test/ConfigFlow.ui.test.ets",
        "ios/WordMagicGameUITests/WordMagicGameUITests.swift",
        "android/app/src/androidTest/java/cool/happyword/wordmagic/ConfigCloudSyncVisibilityTest.kt",
    ),
    "packmanager": (
        "harmonyos/entry/src/ohosTest/ets/test/PackManagerFlow.ui.test.ets",
        "ios/WordMagicGameUITests/WordMagicGameUITests.swift",
        "android/app/src/androidTest/java/cool/happyword/wordmagic/AndroidScreenScreenshotTest.kt",
    ),
    "parentadmin": (
        "harmonyos/entry/src/ohosTest/ets/test/ParentAdminFlow.ui.test.ets",
        "ios/WordMagicGameUITests/WordMagicGameUITests.swift",
        "android/app/src/androidTest/java/cool/happyword/wordmagic/AndroidScreenScreenshotTest.kt",
    ),
    "bounddeviceinfo": (
        "harmonyos/entry/src/ohosTest/ets/test/BoundDeviceInfoFlow.ui.test.ets",
        "ios/WordMagicGameUITests/WordMagicGameUITests.swift",
        "android/app/src/androidTest/java/cool/happyword/wordmagic/HomeBoundChildFlowTest.kt",
    ),
}


@dataclass(frozen=True)
class ScopeCandidate:
    label: str
    path: Path | None = None
    sources: tuple[Path, ...] = ()
    reason: str = ""


@dataclass(frozen=True)
class ScopePlan:
    mode: ScopeMode
    input_value: str
    confirmation_required: bool
    candidates: tuple[ScopeCandidate, ...] = field(default_factory=tuple)

    def selected_path_labels(self) -> tuple[str, ...]:
        return tuple(candidate.label for candidate in self.candidates)


class ScopePlanner:
    def __init__(self, repo_root: Path) -> None:
        self.repo_root = repo_root

    def plan(self, raw_scope: str) -> ScopePlan:
        scope = raw_scope.strip()
        if not scope:
            return self._search_plan(scope)
        if scope == "overall":
            return self._overall_plan(scope)

        path = Path(scope)
        if (self.repo_root / path).exists():
            return self._path_plan(scope, path)

        normalized_page = scope.replace(" ", "").replace("-", "").lower()
        if normalized_page in PAGE_SOURCE_HINTS:
            return self._page_plan(scope, normalized_page)

        return ScopePlan(
            mode=ScopeMode.SEARCH,
            input_value=scope,
            confirmation_required=True,
            candidates=(
                ScopeCandidate(
                    label=scope,
                    reason="No exact file or known page matched this scope; user selection is required.",
                ),
            ),
        )

    def _path_plan(self, scope: str, path: Path) -> ScopePlan:
        mode = ScopeMode.SUITE
        parts = path.parts
        if len(parts) >= 3 and parts[0:2] == ("docs", "features"):
            mode = ScopeMode.FEATURE
        elif len(parts) >= 4 and parts[0:3] == ("docs", "superpowers", "specs"):
            mode = ScopeMode.SPEC
        elif len(parts) >= 4 and parts[0:3] == ("docs", "superpowers", "plans"):
            mode = ScopeMode.PLAN

        return ScopePlan(
            mode=mode,
            input_value=scope,
            confirmation_required=False,
            candidates=(ScopeCandidate(label=path.name, path=path, sources=(path,)),),
        )

    def _page_plan(self, scope: str, normalized_page: str) -> ScopePlan:
        sources = tuple(
            Path(source)
            for source in PAGE_SOURCE_HINTS[normalized_page]
            if (self.repo_root / source).exists()
        )
        return ScopePlan(
            mode=ScopeMode.PAGE,
            input_value=scope,
            confirmation_required=False,
            candidates=(
                ScopeCandidate(
                    label=scope,
                    sources=sources,
                    reason="Known UI page mapped to existing platform test surfaces.",
                ),
            ),
        )

    def _overall_plan(self, scope: str) -> ScopePlan:
        return ScopePlan(
            mode=ScopeMode.OVERALL,
            input_value=scope,
            confirmation_required=True,
            candidates=tuple(
                ScopeCandidate(label=label, reason=", ".join(items))
                for label, items in OVERALL_BRANCH_PATHS.items()
            ),
        )

    def _search_plan(self, scope: str) -> ScopePlan:
        return ScopePlan(
            mode=ScopeMode.SEARCH,
            input_value=scope,
            confirmation_required=True,
            candidates=tuple(
                ScopeCandidate(label=label, reason=", ".join(items))
                for label, items in OVERALL_BRANCH_PATHS.items()
            ),
        )
```

- [ ] **Step 4: Connect `plan --scope` to the planner**

Modify `tools/gap_detector/cli.py` so it prints candidate paths:

```python
from __future__ import annotations

import argparse
import json
from collections.abc import Sequence
from pathlib import Path

from .scope_planner import ScopePlanner


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="python3 -m tools.gap_detector",
        description="Plan, run, and classify three-platform parity gap probes.",
    )
    subcommands = parser.add_subparsers(dest="command", required=True)

    plan = subcommands.add_parser("plan", help="Create a scoped probe manifest")
    plan.add_argument("--scope", required=True, help="Feature/spec/plan/page/suite path or overall")
    plan.add_argument("--run-name", default="", help="Stable run name for artifact paths")

    run = subcommands.add_parser("run", help="Run one manifest probe")
    run.add_argument("--manifest", required=True, help="Path to manifest.yaml")
    run.add_argument("--probe", required=True, help="Probe id to run")
    run.add_argument("--execute", action="store_true", help="Execute platform commands instead of dry-run")

    classify = subcommands.add_parser("classify", help="Classify evidence for a run")
    classify.add_argument("--run", required=True, help="Path to a .gap-detector run directory")

    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if args.command == "plan":
        plan = ScopePlanner(Path.cwd()).plan(args.scope)
        print(json.dumps(_scope_plan_to_dict(plan), indent=2, ensure_ascii=False))
        return 0
    return 0


def _scope_plan_to_dict(plan: object) -> dict[str, object]:
    return {
        "mode": plan.mode.value,
        "input": plan.input_value,
        "confirmation_required": plan.confirmation_required,
        "candidates": [
            {
                "label": candidate.label,
                "path": str(candidate.path) if candidate.path else "",
                "sources": [str(source) for source in candidate.sources],
                "reason": candidate.reason,
            }
            for candidate in plan.candidates
        ],
    }
```

- [ ] **Step 5: Run planner and CLI tests**

Run:

```sh
python3 -m unittest tools.gap_detector.tests.test_scope_planner tools.gap_detector.tests.test_cli -v
python3 -m tools.gap_detector plan --scope overall --run-name smoke-overall
```

Expected: tests PASS; the plan command prints JSON with `"confirmation_required": true` and `"Core Loop"`.

- [ ] **Step 6: Commit planner**

Run:

```sh
git add tools/gap_detector
git commit -m "feat: add gap detector scope planner"
```

### Task 3: Probe Manifest Persistence

**Files:**
- Create: `tools/gap_detector/manifest.py`
- Create: `tools/gap_detector/tests/test_manifest.py`
- Modify: `tools/gap_detector/cli.py`

- [ ] **Step 1: Write failing manifest tests**

Create `tools/gap_detector/tests/test_manifest.py`:

```python
import tempfile
import unittest
from pathlib import Path

from tools.gap_detector.manifest import (
    ExpectedProbeState,
    Manifest,
    PlatformRunner,
    Probe,
    ScopeRecord,
    SourceRecord,
    load_manifest,
    save_manifest,
)


class ManifestTest(unittest.TestCase):
    def test_manifest_round_trips_as_json_compatible_yaml(self) -> None:
        manifest = Manifest(
            scope=ScopeRecord(
                mode="spec",
                input="docs/superpowers/specs/demo.md",
                baseline_branch="origin/main",
                selected_paths=("Core Loop",),
                skipped_paths={"Debug": "not selected"},
            ),
            sources=SourceRecord(
                docs=("docs/superpowers/specs/demo.md",),
                tests={
                    "harmony": ("harmonyos/entry/src/ohosTest/ets/test/ConfigFlow.ui.test.ets",),
                    "ios": ("ios/WordMagicGameUITests/WordMagicGameUITests.swift",),
                    "android": ("android/app/src/androidTest/java/cool/happyword/wordmagic/ConfigCloudSyncVisibilityTest.kt",),
                },
            ),
            probes=(
                Probe(
                    id="config-question-types",
                    page="Config",
                    expected=ExpectedProbeState(
                        behavior=("Only implemented question chips render.",),
                        stable_ids=("ConfigQuestionType_choice",),
                        style_refs=("assets/screenshots/harmonyos/config-question-types.png",),
                    ),
                    runners={
                        "harmony": PlatformRunner(suite="ConfigFlow", case="questionTypeSectionRendersImplementedChineseChipsOnly"),
                        "ios": PlatformRunner(suite="WordMagicGameUITests", route="config"),
                        "android": PlatformRunner(suite="ConfigCloudSyncVisibilityTest", route="config"),
                    },
                    classify_as=("behavior_drift", "missing_stable_id"),
                    status="pending",
                ),
            ),
        )

        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / "manifest.yaml"
            save_manifest(manifest, target)
            loaded = load_manifest(target)

        self.assertEqual(loaded.scope.baseline_branch, "origin/main")
        self.assertEqual(loaded.scope.skipped_paths["Debug"], "not selected")
        self.assertEqual(loaded.probes[0].id, "config-question-types")
        self.assertEqual(loaded.probes[0].runners["ios"].route, "config")

    def test_mark_probe_status_returns_new_manifest(self) -> None:
        manifest = Manifest(
            scope=ScopeRecord(mode="overall", input="overall", baseline_branch="origin/main", selected_paths=("Core Loop",)),
            sources=SourceRecord(),
            probes=(Probe(id="home", page="Home"),),
        )

        updated = manifest.with_probe_status("home", "classified")

        self.assertEqual(manifest.probes[0].status, "pending")
        self.assertEqual(updated.probes[0].status, "classified")


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run manifest tests and verify they fail**

Run:

```sh
python3 -m unittest tools.gap_detector.tests.test_manifest -v
```

Expected: FAIL with `No module named tools.gap_detector.manifest`.

- [ ] **Step 3: Implement manifest dataclasses and persistence**

Create `tools/gap_detector/manifest.py`:

```python
from __future__ import annotations

import json
from dataclasses import asdict, dataclass, field, replace
from pathlib import Path
from typing import Any


@dataclass(frozen=True)
class ScopeRecord:
    mode: str
    input: str
    baseline_branch: str
    selected_paths: tuple[str, ...] = ()
    skipped_paths: dict[str, str] = field(default_factory=dict)


@dataclass(frozen=True)
class SourceRecord:
    docs: tuple[str, ...] = ()
    tests: dict[str, tuple[str, ...]] = field(default_factory=dict)


@dataclass(frozen=True)
class ExpectedProbeState:
    behavior: tuple[str, ...] = ()
    stable_ids: tuple[str, ...] = ()
    style_refs: tuple[str, ...] = ()


@dataclass(frozen=True)
class PlatformRunner:
    suite: str = ""
    case: str = ""
    route: str = ""


@dataclass(frozen=True)
class Probe:
    id: str
    page: str
    expected: ExpectedProbeState = field(default_factory=ExpectedProbeState)
    runners: dict[str, PlatformRunner] = field(default_factory=dict)
    classify_as: tuple[str, ...] = ()
    status: str = "pending"


@dataclass(frozen=True)
class Manifest:
    scope: ScopeRecord
    sources: SourceRecord = field(default_factory=SourceRecord)
    probes: tuple[Probe, ...] = ()

    def with_probe_status(self, probe_id: str, status: str) -> Manifest:
        probes = tuple(
            replace(probe, status=status) if probe.id == probe_id else probe
            for probe in self.probes
        )
        if probes == self.probes:
            raise ValueError(f"probe not found: {probe_id}")
        return replace(self, probes=probes)


def save_manifest(manifest: Manifest, target: Path) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(_manifest_to_dict(manifest), indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def load_manifest(source: Path) -> Manifest:
    data = json.loads(source.read_text(encoding="utf-8"))
    return _manifest_from_dict(data)


def _manifest_to_dict(manifest: Manifest) -> dict[str, Any]:
    return asdict(manifest)


def _manifest_from_dict(data: dict[str, Any]) -> Manifest:
    return Manifest(
        scope=ScopeRecord(
            mode=data["scope"]["mode"],
            input=data["scope"]["input"],
            baseline_branch=data["scope"]["baseline_branch"],
            selected_paths=tuple(data["scope"].get("selected_paths", ())),
            skipped_paths=dict(data["scope"].get("skipped_paths", {})),
        ),
        sources=SourceRecord(
            docs=tuple(data.get("sources", {}).get("docs", ())),
            tests={
                platform: tuple(paths)
                for platform, paths in data.get("sources", {}).get("tests", {}).items()
            },
        ),
        probes=tuple(_probe_from_dict(item) for item in data.get("probes", ())),
    )


def _probe_from_dict(data: dict[str, Any]) -> Probe:
    expected = data.get("expected", {})
    return Probe(
        id=data["id"],
        page=data["page"],
        expected=ExpectedProbeState(
            behavior=tuple(expected.get("behavior", ())),
            stable_ids=tuple(expected.get("stable_ids", ())),
            style_refs=tuple(expected.get("style_refs", ())),
        ),
        runners={
            platform: PlatformRunner(
                suite=runner.get("suite", ""),
                case=runner.get("case", ""),
                route=runner.get("route", ""),
            )
            for platform, runner in data.get("runners", {}).items()
        },
        classify_as=tuple(data.get("classify_as", ())),
        status=data.get("status", "pending"),
    )
```

- [ ] **Step 4: Make `plan` create `.gap-detector` manifests**

Modify `tools/gap_detector/cli.py` so `plan --scope` creates a manifest path and prints it. Replace the current `if args.command == "plan":` block with:

```python
    if args.command == "plan":
        scope_plan = ScopePlanner(Path.cwd()).plan(args.scope)
        run_name = args.run_name or _safe_run_name(args.scope)
        run_dir = Path(".gap-detector") / "runs" / run_name
        manifest = _manifest_from_scope_plan(scope_plan)
        manifest_path = run_dir / "manifest.yaml"
        save_manifest(manifest, manifest_path)
        print(json.dumps({
            "manifest": str(manifest_path),
            "scope_plan": _scope_plan_to_dict(scope_plan),
        }, indent=2, ensure_ascii=False))
        return 0
```

Add imports:

```python
from .manifest import Manifest, Probe, ScopeRecord, SourceRecord, save_manifest
```

Add helper functions at the end of `cli.py`:

```python
def _safe_run_name(scope: str) -> str:
    cleaned = "".join(ch if ch.isalnum() else "-" for ch in scope.strip().lower()).strip("-")
    return cleaned or "search"


def _manifest_from_scope_plan(scope_plan: object) -> Manifest:
    docs: list[str] = []
    tests: dict[str, list[str]] = {"harmony": [], "ios": [], "android": []}
    probes: list[Probe] = []
    selected_paths: list[str] = []
    skipped_paths: dict[str, str] = {}
    pending_selection = scope_plan.confirmation_required

    for candidate in scope_plan.candidates:
        if pending_selection:
            skipped_paths[candidate.label] = "pending user selection"
        else:
            selected_paths.append(candidate.label)
        if candidate.path:
            docs.append(str(candidate.path))
        for source in candidate.sources:
            source_text = str(source)
            if source_text.startswith("harmonyos/"):
                tests["harmony"].append(source_text)
            elif source_text.startswith("ios/"):
                tests["ios"].append(source_text)
            elif source_text.startswith("android/"):
                tests["android"].append(source_text)
        probes.append(Probe(id=_safe_run_name(candidate.label), page=candidate.label))

    return Manifest(
        scope=ScopeRecord(
            mode=scope_plan.mode.value,
            input=scope_plan.input_value,
            baseline_branch="origin/main",
            selected_paths=tuple(selected_paths),
            skipped_paths=skipped_paths,
        ),
        sources=SourceRecord(
            docs=tuple(dict.fromkeys(docs)),
            tests={platform: tuple(dict.fromkeys(paths)) for platform, paths in tests.items() if paths},
        ),
        probes=tuple(probes),
    )
```

- [ ] **Step 5: Run manifest tests and plan smoke**

Run:

```sh
python3 -m unittest tools.gap_detector.tests.test_manifest tools.gap_detector.tests.test_cli -v
python3 -m tools.gap_detector plan --scope docs/superpowers/specs/2026-05-13-three-platform-gap-detector-design.md --run-name smoke-spec
test -f .gap-detector/runs/smoke-spec/manifest.yaml
```

Expected: tests PASS; `manifest.yaml` exists under `.gap-detector/runs/smoke-spec/`.

- [ ] **Step 6: Commit manifest work**

Run:

```sh
git add tools/gap_detector
git commit -m "feat: persist gap detector manifests"
```

### Task 4: Command Planner And Dry-Run Runner

**Files:**
- Create: `tools/gap_detector/runners/__init__.py`
- Create: `tools/gap_detector/runners/commands.py`
- Modify: `tools/gap_detector/cli.py`
- Modify: `tools/gap_detector/tests/test_cli.py`

- [ ] **Step 1: Add failing runner CLI test**

Append to `tools/gap_detector/tests/test_cli.py`:

```python
    def test_run_dry_run_prints_platform_commands(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            manifest_path = Path(tmp) / "manifest.yaml"
            manifest_path.write_text(
                """
{
  "scope": {
    "mode": "page",
    "input": "Config",
    "baseline_branch": "origin/main",
    "selected_paths": ["Config"],
    "skipped_paths": {}
  },
  "sources": {"docs": [], "tests": {}},
  "probes": [
    {
      "id": "config",
      "page": "Config",
      "expected": {"behavior": [], "stable_ids": [], "style_refs": []},
      "runners": {
        "harmony": {"suite": "ConfigFlow", "case": "questionTypeSectionRendersImplementedChineseChipsOnly", "route": ""},
        "ios": {"suite": "WordMagicGameUITests", "case": "testConfigPinParentAdminAndLessonReviewMockFlow", "route": "config"},
        "android": {"suite": "ConfigCloudSyncVisibilityTest", "case": "", "route": "config"}
      },
      "classify_as": [],
      "status": "pending"
    }
  ]
}
""".strip(),
                encoding="utf-8",
            )

            result = subprocess.run(
                [sys.executable, "-m", "tools.gap_detector", "run", "--manifest", str(manifest_path), "--probe", "config"],
                check=False,
                capture_output=True,
                text=True,
            )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("scripts/run_ui_tests.sh --suite ConfigFlow", result.stdout)
        self.assertIn("xcodebuild test", result.stdout)
        self.assertIn("./gradlew connectedDebugAndroidTest", result.stdout)
```

Add the missing imports at the top of `test_cli.py`:

```python
import tempfile
from pathlib import Path
```

- [ ] **Step 2: Run the dry-run test and verify it fails**

Run:

```sh
python3 -m unittest tools.gap_detector.tests.test_cli.CliSmokeTest.test_run_dry_run_prints_platform_commands -v
```

Expected: FAIL because `run` currently returns without printing commands.

- [ ] **Step 3: Implement command planning**

Create `tools/gap_detector/runners/__init__.py`:

```python
"""Platform command planning for the gap detector."""
```

Create `tools/gap_detector/runners/commands.py`:

```python
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
```

- [ ] **Step 4: Connect `run` CLI to dry-run and explicit execute**

Modify `tools/gap_detector/cli.py` imports:

```python
from .manifest import Manifest, Probe, ScopeRecord, SourceRecord, load_manifest, save_manifest
from .runners.commands import commands_for_probe, execute_command
```

Replace the current `return 0` fallback for `run` with this block before the final return:

```python
    if args.command == "run":
        manifest = load_manifest(Path(args.manifest))
        probe = next((item for item in manifest.probes if item.id == args.probe), None)
        if probe is None:
            parser.error(f"probe not found: {args.probe}")
        commands = commands_for_probe(probe, Path.cwd())
        for command in commands:
            if args.execute:
                result = execute_command(command)
                print(json.dumps({
                    "platform": command.platform,
                    "command": command.shell_text(),
                    "returncode": result.returncode,
                    "stdout": result.stdout[-4000:],
                    "stderr": result.stderr[-4000:],
                }, indent=2, ensure_ascii=False))
                if result.returncode != 0:
                    return result.returncode
            else:
                print(f"[dry-run] {command.platform}: {command.shell_text()} (cwd={command.cwd})")
        return 0
```

- [ ] **Step 5: Run CLI tests**

Run:

```sh
python3 -m unittest tools.gap_detector.tests.test_cli -v
```

Expected: PASS and dry-run output includes all three platform command families.

- [ ] **Step 6: Commit runner work**

Run:

```sh
git add tools/gap_detector
git commit -m "feat: add gap detector dry-run commands"
```

### Task 5: Evidence Index And Classifier

**Files:**
- Create: `tools/gap_detector/evidence.py`
- Create: `tools/gap_detector/classifier.py`
- Create: `tools/gap_detector/tests/test_classifier.py`
- Modify: `tools/gap_detector/cli.py`

- [ ] **Step 1: Write failing classifier tests**

Create `tools/gap_detector/tests/test_classifier.py`:

```python
import tempfile
import unittest
from pathlib import Path

from tools.gap_detector.classifier import GapCategory, Severity, classify_probe
from tools.gap_detector.evidence import EvidenceIndex
from tools.gap_detector.manifest import ExpectedProbeState, PlatformRunner, Probe


class ClassifierTest(unittest.TestCase):
    def test_missing_stable_id_creates_high_gap(self) -> None:
        probe = Probe(
            id="config-question-types",
            page="Config",
            expected=ExpectedProbeState(stable_ids=("ConfigQuestionType_choice",)),
            runners={"ios": PlatformRunner(suite="WordMagicGameUITests")},
        )
        evidence = EvidenceIndex(
            probe_id="config-question-types",
            platform="ios",
            ui_tree_text="ConfigSaveButton",
        )

        gaps = classify_probe(probe, {"ios": evidence})

        self.assertEqual(len(gaps), 1)
        self.assertEqual(gaps[0].category, GapCategory.MISSING_STABLE_ID)
        self.assertEqual(gaps[0].severity, Severity.HIGH)
        self.assertIn("ConfigQuestionType_choice", gaps[0].observed)

    def test_missing_screenshot_creates_medium_gap(self) -> None:
        probe = Probe(
            id="home",
            page="Home",
            expected=ExpectedProbeState(style_refs=("assets/screenshots/harmonyos/home.png",)),
            runners={"android": PlatformRunner(suite="SmokeTest")},
        )
        evidence = EvidenceIndex(probe_id="home", platform="android")

        gaps = classify_probe(probe, {"android": evidence})

        self.assertEqual(gaps[0].category, GapCategory.SCREENSHOT_MISSING)
        self.assertEqual(gaps[0].severity, Severity.MEDIUM)

    def test_existing_stable_id_and_screenshot_create_no_gap(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            screenshot = Path(tmp) / "home.png"
            screenshot.write_bytes(b"png")
            probe = Probe(
                id="home",
                page="Home",
                expected=ExpectedProbeState(stable_ids=("HomeStartButton",), style_refs=("assets/screenshots/harmonyos/home.png",)),
                runners={"harmony": PlatformRunner(suite="AdventureFlow")},
            )
            evidence = EvidenceIndex(
                probe_id="home",
                platform="harmony",
                screenshot=screenshot,
                ui_tree_text="HomeStartButton",
            )

            gaps = classify_probe(probe, {"harmony": evidence})

        self.assertEqual(gaps, ())


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run classifier tests and verify they fail**

Run:

```sh
python3 -m unittest tools.gap_detector.tests.test_classifier -v
```

Expected: FAIL with `No module named tools.gap_detector.classifier`.

- [ ] **Step 3: Implement evidence index**

Create `tools/gap_detector/evidence.py`:

```python
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
```

- [ ] **Step 4: Implement classifier**

Create `tools/gap_detector/classifier.py`:

```python
from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum

from .evidence import EvidenceIndex
from .manifest import Probe


class GapCategory(str, Enum):
    MISSING_FLOW = "missing_flow"
    BEHAVIOR_DRIFT = "behavior_drift"
    MISSING_STABLE_ID = "missing_stable_id"
    STYLE_DRIFT = "style_drift"
    SCREENSHOT_MISSING = "screenshot_missing"
    TEST_COVERAGE_GAP = "test_coverage_gap"
    CONTRACT_DRIFT = "contract_drift"
    MANUAL_GATE = "manual_gate"


class Severity(str, Enum):
    CRITICAL = "critical"
    HIGH = "high"
    MEDIUM = "medium"
    LOW = "low"


@dataclass(frozen=True)
class GapItem:
    id: str
    probe: str
    platform: str
    severity: Severity
    category: GapCategory
    expected: str
    observed: str
    evidence: dict[str, str] = field(default_factory=dict)
    downstream_hint: str = ""
    status: str = "open"

    def to_dict(self) -> dict[str, object]:
        return {
            "id": self.id,
            "probe": self.probe,
            "platform": self.platform,
            "severity": self.severity.value,
            "category": self.category.value,
            "expected": self.expected,
            "observed": self.observed,
            "evidence": self.evidence,
            "downstream_hint": self.downstream_hint,
            "status": self.status,
        }


def classify_probe(probe: Probe, evidence_by_platform: dict[str, EvidenceIndex]) -> tuple[GapItem, ...]:
    gaps: list[GapItem] = []
    for platform in sorted(probe.runners):
        evidence = evidence_by_platform.get(platform, EvidenceIndex(probe_id=probe.id, platform=platform))
        for stable_id in probe.expected.stable_ids:
            if not evidence.contains_stable_id(stable_id):
                gaps.append(
                    GapItem(
                        id=f"gap-{probe.id}-{platform}-missing-stable-id-{len(gaps) + 1:03d}",
                        probe=probe.id,
                        platform=platform,
                        severity=Severity.HIGH,
                        category=GapCategory.MISSING_STABLE_ID,
                        expected=f"Stable id {stable_id} is present on {platform}.",
                        observed=f"Stable id {stable_id} was not found in {platform} evidence.",
                        evidence=_evidence_paths(evidence),
                        downstream_hint=f"Create a {platform} parity follow-up; detector does not edit app source.",
                    )
                )
        if probe.expected.style_refs and not evidence.has_screenshot():
            gaps.append(
                GapItem(
                    id=f"gap-{probe.id}-{platform}-screenshot-missing-{len(gaps) + 1:03d}",
                    probe=probe.id,
                    platform=platform,
                    severity=Severity.MEDIUM,
                    category=GapCategory.SCREENSHOT_MISSING,
                    expected=f"{platform} screenshot evidence exists for {probe.page}.",
                    observed=f"No screenshot file was indexed for {platform} probe {probe.id}.",
                    evidence=_evidence_paths(evidence),
                    downstream_hint="Re-run this detector probe with screenshot capture enabled before remediation planning.",
                )
            )
    return tuple(gaps)


def _evidence_paths(evidence: EvidenceIndex) -> dict[str, str]:
    paths: dict[str, str] = {}
    if evidence.screenshot is not None:
        paths["screenshot"] = str(evidence.screenshot)
    if evidence.log_path is not None:
        paths["log"] = str(evidence.log_path)
    return paths
```

- [ ] **Step 5: Connect `classify` CLI to manifest and artifact folders**

Modify `tools/gap_detector/cli.py` imports:

```python
from .classifier import classify_probe
from .evidence import EvidenceIndex
```

Replace the fallback for `classify` with:

```python
    if args.command == "classify":
        run_dir = Path(args.run)
        manifest = load_manifest(run_dir / "manifest.yaml")
        gaps = []
        for probe in manifest.probes:
            evidence_by_platform = {
                platform: _load_evidence_index(run_dir, probe.id, platform)
                for platform in probe.runners
            }
            for gap in classify_probe(probe, evidence_by_platform):
                gaps.append(gap.to_dict())
        gaps_path = run_dir / "gaps.yaml"
        gaps_path.write_text(json.dumps(gaps, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        print(json.dumps({"gaps": str(gaps_path), "count": len(gaps)}, indent=2, ensure_ascii=False))
        return 0
```

Add helper:

```python
def _load_evidence_index(run_dir: Path, probe_id: str, platform: str) -> EvidenceIndex:
    probe_dir = run_dir / "probes" / probe_id / platform
    screenshot = probe_dir / "screenshot.png"
    ui_tree = probe_dir / "ui-tree.txt"
    log_path = probe_dir / "runner.log"
    return EvidenceIndex(
        probe_id=probe_id,
        platform=platform,
        screenshot=screenshot if screenshot.exists() else None,
        ui_tree_text=ui_tree.read_text(encoding="utf-8") if ui_tree.exists() else "",
        log_path=log_path if log_path.exists() else None,
    )
```

- [ ] **Step 6: Run classifier tests and full detector tests**

Run:

```sh
python3 -m unittest discover tools/gap_detector/tests -v
```

Expected: PASS.

- [ ] **Step 7: Commit classifier**

Run:

```sh
git add tools/gap_detector
git commit -m "feat: classify gap detector evidence"
```

### Task 6: README And CLI Workflow Documentation

**Files:**
- Create: `tools/gap_detector/README.md`
- Modify: `tools/gap_detector/tests/test_cli.py`

- [ ] **Step 1: Write failing README smoke test**

Append to `tools/gap_detector/tests/test_cli.py`:

```python
    def test_readme_documents_non_goal_and_overall_gate(self) -> None:
        readme = Path("tools/gap_detector/README.md").read_text(encoding="utf-8")

        self.assertIn("does not fix gaps", readme)
        self.assertIn("--scope overall", readme)
        self.assertIn("user selection", readme)
        self.assertIn(".gap-detector/runs", readme)
```

- [ ] **Step 2: Run README test and verify it fails**

Run:

```sh
python3 -m unittest tools.gap_detector.tests.test_cli.CliSmokeTest.test_readme_documents_non_goal_and_overall_gate -v
```

Expected: FAIL with `No such file or directory: 'tools/gap_detector/README.md'`.

- [ ] **Step 3: Create README**

Create `tools/gap_detector/README.md`:

```markdown
# Three-Platform Gap Detector

This tool finds iOS and Android behavior or UI parity gaps against the latest HarmonyOS baseline. It does not fix gaps, edit app source, open PRs, or create implementation patches.

## Modes

- Scoped: pass a feature folder, spec, plan, page, or suite path with `--scope`.
- Overall: pass `--scope overall`. Overall mode is expensive and must go through user selection before simulator/device runs.
- Ambiguous: pass an empty or unknown scope to receive candidate paths for user selection.

## Commands

```sh
python3 -m tools.gap_detector plan --scope docs/features/<feature-id> --run-name feature-check
python3 -m tools.gap_detector plan --scope overall --run-name overall-plan
python3 -m tools.gap_detector run --manifest .gap-detector/runs/feature-check/manifest.yaml --probe <probe-id>
python3 -m tools.gap_detector classify --run .gap-detector/runs/feature-check
```

`run` defaults to dry-run command printing. Add `--execute` only when the target simulator/device is ready and the user expects local commands to run.

## Artifacts

Runs live under `.gap-detector/runs/<run-name>/`:

```text
.gap-detector/runs/<run-name>/
  manifest.yaml
  gaps.yaml
  probes/<probe>/<platform>/
```

The artifact directory is gitignored. Later workflows can copy selected evidence into tracked docs when needed.

## Expected Behavior Sources

The detector reads specs, plans, feature docs, stable IDs, existing UI tests, screenshots, and command manifests. Screenshots are evidence, not the only source of truth.
```

- [ ] **Step 4: Run README and full tests**

Run:

```sh
python3 -m unittest discover tools/gap_detector/tests -v
```

Expected: PASS.

- [ ] **Step 5: Commit docs**

Run:

```sh
git add tools/gap_detector/README.md tools/gap_detector/tests/test_cli.py
git commit -m "docs: document gap detector workflow"
```

### Task 7: Codex And Cursor Skills

**Files:**
- Create: `.agents/skills/three-platform-gap-detector/SKILL.md`
- Create: `.cursor/skills/three-platform-gap-detector/SKILL.md`
- Create: `tools/gap_detector/tests/test_skill_docs.py`

- [ ] **Step 1: Write failing skill validation tests**

Create `tools/gap_detector/tests/test_skill_docs.py`:

```python
import unittest
from pathlib import Path


SKILL_PATHS = (
    Path(".agents/skills/three-platform-gap-detector/SKILL.md"),
    Path(".cursor/skills/three-platform-gap-detector/SKILL.md"),
)


class SkillDocsTest(unittest.TestCase):
    def test_skill_files_exist_and_use_condition_only_description(self) -> None:
        for path in SKILL_PATHS:
            text = path.read_text(encoding="utf-8")
            self.assertIn("name: three-platform-gap-detector", text)
            self.assertIn("description: Use when investigating iOS or Android parity gaps", text)
            self.assertNotIn("dispatches", text.split("---", 2)[1])

    def test_skill_enforces_detector_scope_boundaries(self) -> None:
        required = (
            "Do not run `overall` unless the user explicitly requests it.",
            "Build or update a probe manifest before running simulators.",
            "Run one suite/page probe batch at a time.",
            "Stop at evidence-backed gap findings.",
            "Do not edit app source, create fix commits, or open PRs.",
        )
        for path in SKILL_PATHS:
            text = path.read_text(encoding="utf-8")
            for sentence in required:
                self.assertIn(sentence, text)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run skill tests and verify they fail**

Run:

```sh
python3 -m unittest tools.gap_detector.tests.test_skill_docs -v
```

Expected: FAIL with missing `SKILL.md` files.

- [ ] **Step 3: Create Codex skill**

Create `.agents/skills/three-platform-gap-detector/SKILL.md`:

```markdown
---
name: three-platform-gap-detector
description: Use when investigating iOS or Android parity gaps against the HarmonyOS baseline in WordMagicGame, especially when comparing behavior, UI style, stable IDs, screenshots, specs, plans, or three-platform feature docs.
---

# Three-Platform Gap Detector

Use this skill to find iOS and Android gaps against the latest HarmonyOS baseline. This is an evidence workflow, not a repair workflow.

## Start

1. Resolve scope from the user request.
2. Do not run `overall` unless the user explicitly requests it.
3. If the request is ambiguous, generate a search-path plan and ask the user to choose paths.
4. Use latest HarmonyOS on `main` or `origin/main` as the baseline.
5. Read specs, plans, feature docs, and existing tests before judging screenshots.

## Run Discipline

1. Build or update a probe manifest before running simulators.
2. Run one suite/page probe batch at a time.
3. Capture evidence: screenshots, UI tree or accessibility evidence, command logs, test output, and source docs.
4. After each batch, classify findings into the gap queue before continuing.
5. Stop at evidence-backed gap findings.

## Boundaries

- Do not edit app source, create fix commits, or open PRs.
- Do not treat screenshots as the only source of truth.
- Do not silently skip missing counterpart suites; record a `test_coverage_gap`.
- Do not force manual-only debug paths into automated UI suites; record `manual_gate`.

## Commands

```sh
python3 -m tools.gap_detector plan --scope <feature-or-spec-or-page> --run-name <name>
python3 -m tools.gap_detector plan --scope overall --run-name <name>
python3 -m tools.gap_detector run --manifest .gap-detector/runs/<name>/manifest.yaml --probe <probe-id>
python3 -m tools.gap_detector classify --run .gap-detector/runs/<name>
```

Use `run --execute` only when the user expects local platform commands to run and the required simulator/device is ready.

## Handoff

If the user wants to fix a gap, hand off to the applicable feature or bugfix workflow with the gap queue item as input.
```

- [ ] **Step 4: Create Cursor skill with the same content**

Create `.cursor/skills/three-platform-gap-detector/SKILL.md` with the exact same Markdown content as `.agents/skills/three-platform-gap-detector/SKILL.md`.

- [ ] **Step 5: Run skill tests**

Run:

```sh
python3 -m unittest tools.gap_detector.tests.test_skill_docs -v
```

Expected: PASS.

- [ ] **Step 6: Commit skills**

Run:

```sh
git add .agents/skills/three-platform-gap-detector .cursor/skills/three-platform-gap-detector tools/gap_detector/tests/test_skill_docs.py
git commit -m "docs: add gap detector skills"
```

### Task 8: Full Verification And Final Polish

**Files:**
- Modify only files already created in earlier tasks if verification finds a defect.

- [ ] **Step 1: Run all detector tests**

Run:

```sh
python3 -m unittest discover tools/gap_detector/tests -v
```

Expected: PASS.

- [ ] **Step 2: Run scoped plan smoke**

Run:

```sh
python3 -m tools.gap_detector plan --scope docs/superpowers/specs/2026-05-13-three-platform-gap-detector-design.md --run-name final-spec-smoke
test -f .gap-detector/runs/final-spec-smoke/manifest.yaml
```

Expected: manifest file exists and the command prints JSON containing `"manifest": ".gap-detector/runs/final-spec-smoke/manifest.yaml"`.

- [ ] **Step 3: Run overall plan smoke**

Run:

```sh
python3 -m tools.gap_detector plan --scope overall --run-name final-overall-smoke
rg -n '"Core Loop"|pending user selection' .gap-detector/runs/final-overall-smoke/manifest.yaml
```

Expected: `rg` prints at least one `Core Loop` line and at least one `pending user selection` line.

- [ ] **Step 4: Run dry-run command smoke**

Run:

```sh
python3 -m tools.gap_detector run --manifest .gap-detector/runs/final-overall-smoke/manifest.yaml --probe core-loop
```

Expected: command exits 0. If the generated `overall` probes have no platform runners yet, output may be empty; this is acceptable for `overall` path selection because simulator execution requires a scoped manifest. Record this in the final summary.

- [ ] **Step 5: Run classify smoke**

Run:

```sh
python3 -m tools.gap_detector classify --run .gap-detector/runs/final-overall-smoke
test -f .gap-detector/runs/final-overall-smoke/gaps.yaml
```

Expected: `gaps.yaml` exists. It may contain `[]` for a selection-only overall manifest.

- [ ] **Step 6: Run diff check and verify no artifacts are tracked**

Run:

```sh
git diff --check
git status --short --ignored .gap-detector | head -n 20
```

Expected: `git diff --check` exits 0; `.gap-detector/` appears ignored and no run artifacts appear as untracked files in normal `git status --short`.

- [ ] **Step 7: Final commit**

Run:

```sh
git status --short
git add .gitignore tools/gap_detector .agents/skills/three-platform-gap-detector .cursor/skills/three-platform-gap-detector
git commit -m "feat: add three-platform gap detector"
```

Expected: final commit contains only detector tooling, tests, README, skills, and `.gitignore`.

## Acceptance Checklist

- [ ] Scoped `plan` creates `.gap-detector/runs/<name>/manifest.yaml` without global crawling.
- [ ] `plan --scope overall` creates a confirmation-required manifest with Core Loop, Growth, Parent/Admin, Cloud, Debug, and Contracts paths.
- [ ] `run` defaults to dry-run command output and requires `--execute` for real simulator/device commands.
- [ ] `classify` writes `.gap-detector/runs/<name>/gaps.yaml`.
- [ ] Classifier creates concrete gap queue items for missing stable IDs and missing screenshots.
- [ ] `.gap-detector/` run artifacts are gitignored.
- [ ] Codex and Cursor skills exist and forbid source edits, fix commits, and PR creation inside detector mode.
- [ ] `python3 -m unittest discover tools/gap_detector/tests -v` passes.
- [ ] `git diff --check` passes.

## Execution Notes

- Do not run HarmonyOS, iOS, or Android simulator commands during unit-test verification unless the user explicitly chooses an execution path that requires local device proof.
- Do not add a root `pyproject.toml` for this first version. The package is stdlib-only and should match the existing lightweight `tools/` pattern.
- Do not commit `.gap-detector/` artifacts. They are local evidence products for later workflows to consume deliberately.
