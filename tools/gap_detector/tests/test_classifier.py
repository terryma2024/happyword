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
