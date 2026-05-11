# Android Validation Plan

## Validation Philosophy

Android must follow the repo's verification-heavy style:

```text
docs/contracts -> pure logic tests -> UI tests -> emulator/device automation -> release gates
```

Do not use screenshots as the first proof of correctness. Prove domain behavior with JVM tests first, then use Compose/UI Automator tests for route and user-flow confidence.

## Phase 0 Verification

| Check | Command | Expected |
| --- | --- | --- |
| SDK tools available | `adb version` | Prints Android Debug Bridge version. |
| SDK manager available | `sdkmanager --version` | Prints a version. |
| Emulator tooling available | `emulator -list-avds` | Prints AVD list or empty list without command-not-found. |
| JDK alignment | `cd android && ./gradlew --version` | Gradle JVM is 17. |
| Project compiles | `cd android && ./gradlew assembleDebug` | Debug APK builds. |
| JVM tests | `cd android && ./gradlew testDebugUnitTest` | All tests pass. |
| Connected smoke | `cd android && ./gradlew connectedDebugAndroidTest` | Smoke test passes on emulator. |

## Phase 1 Verification

### JVM Tests

Required test groups:

- `BattleEngineTest`
- `QuestionGeneratorTest`
- `GameConfigStoreTest`
- `ParentPinStoreTest`
- `LessonDraftReviewStoreTest`
- Parent API DTO decoding tests with fixtures.

Run:

```sh
cd android
./gradlew testDebugUnitTest
```

Expected:

- 0 failures.
- No skipped tests unless the skip reason is explicit in test output.

### Compose UI Tests

Required flows:

- Home renders selected pack and starts deterministic battle.
- Battle answers one correct and one wrong question.
- Result returns to Home and updates coin/today state.
- Config saves a custom timer of `3`.
- PIN setup gates ParentAdmin.
- ParentAdmin fake refresh renders overview.
- LessonDraftReview fake draft can be approved.

Run:

```sh
cd android
./gradlew connectedDebugAndroidTest
```

Expected:

- All tests pass on `WordMagicGame_API36`.

## Phase 2 Verification

Required JVM tests:

- Pack merge precedence.
- Active max five.
- Pin only active packs.
- Perfect-run rotation.
- Coin debit and redemption history cap.
- LearningReport pack-keyed aggregation.

Required UI tests:

- Toggle pack in PackManager and see Home chip row update.
- Add custom wish behind PIN.
- Open MonsterCodex.
- Open TodayPlan.
- Open LearningReport and find a builtin pack row.

## Phase 3 Verification

Required contract checks:

- Decode shared fixtures from `shared/fixtures/`.
- Validate client request payloads against documented shared contracts where practical.

Mock server flow:

```sh
cd server
uv run python mock_ui_server.py
```

```sh
adb reverse tcp:8123 tcp:8123
cd android
./gradlew connectedDebugAndroidTest \
  -Pandroid.testInstrumentationRunnerArguments.serverBaseUrl=http://127.0.0.1:8123
```

Expected:

- Short-code bind flow can use the local mock server.
- Global/family pack fetch can use the local mock server.
- Battle remains playable when sync fails.

## Phase 4 Verification

Debug variant:

```sh
cd android
./gradlew connectedDebugAndroidTest \
  -Pandroid.testInstrumentationRunnerArguments.includeDebugMenu=true
```

Expected:

- DevMenu opens only in debug.
- Backend environment override persists locally.
- Preview manifest can be parsed from mock response.
- Bypass secret can be set and cleared.

Release variant:

```sh
cd android
./gradlew assembleRelease
```

Expected:

- Release APK builds.
- Debug menu route is absent from release code path.
- No preview bypass screen is reachable.

## Screenshot Parity Checks

After each phase, capture Android screenshots and store them under:

```text
assets/screenshots/android/
```

Suggested names:

- `home.png`
- `battle.png`
- `result.png`
- `config.png`
- `parent-admin.png`
- `lesson-draft-review.png`

Do not overwrite HarmonyOS screenshots.

Manual review criteria:

- Primary action visible.
- No important text overlaps.
- Buttons fit within bounds.
- Landscape child flow is usable on a phone emulator.
- Portrait parent flow is readable without tablet-sized whitespace.

## Pre-Commit Checklist

Before committing Android implementation work:

```sh
git diff --check
cd android && ./gradlew testDebugUnitTest
cd android && ./gradlew assembleDebug
```

If Android UI was touched and an emulator is available:

```sh
cd android && ./gradlew connectedDebugAndroidTest
```

If server contracts or mock server were touched:

```sh
cd server && uv run pytest
```

Expected:

- Android unit/build checks pass.
- Connected tests pass when emulator tooling is available.
- Server tests finish with 0 errors and 0 warnings when server files changed.
