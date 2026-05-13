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
