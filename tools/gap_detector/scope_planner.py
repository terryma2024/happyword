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
