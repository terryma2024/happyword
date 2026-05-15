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
