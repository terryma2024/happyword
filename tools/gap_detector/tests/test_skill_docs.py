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
