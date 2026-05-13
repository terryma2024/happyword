import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


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

    def test_readme_documents_non_goal_and_overall_gate(self) -> None:
        readme = Path("tools/gap_detector/README.md").read_text(encoding="utf-8")

        self.assertIn("does not fix gaps", readme)
        self.assertIn("--scope overall", readme)
        self.assertIn("user selection", readme)
        self.assertIn(".gap-detector/runs", readme)


if __name__ == "__main__":
    unittest.main()
