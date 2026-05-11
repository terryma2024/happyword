# Android Replica Phase 1 Core ParentAdmin Design

## Status

Design-for-implementation.

## Goal

Implement the first product slice of the native Android client:

```text
Home -> Battle -> Result
Config -> Parent PIN -> ParentAdmin -> LessonDraftReview
```

## Architecture

Use Kotlin domain models and services under `core/`, Android storage/network adapters under `data/`, and Compose screens under `ui/`. The first product slice uses fake repositories and fake `ParentApiClient` where needed so the UI can be tested before real server wiring.

`shared/` remains contracts and fixtures only.

## Phase 1 Screens

| Screen | Orientation | Source |
| --- | --- | --- |
| Home | landscape | `HomePage.ets`, `assets/screenshots/harmonyos/home.png` |
| Battle | landscape | `BattlePage.ets`, `battle.png` |
| Result | landscape | `ResultPage.ets`, `result.png` |
| Config | landscape | `ConfigPage.ets`, `config-part*.png` |
| ParentPinSetup | landscape | `ParentPinSetupPage.ets`, `parent-pin-setup.png` |
| ParentAdmin | portrait | `ParentAdminPage.ets`, `parent-admin-part*.png` |
| LessonDraftReview | portrait | `LessonDraftReviewPage.ets`, V0.5.8 design |

## Core Domain Requirements

- `GameConfig` defaults: player HP 5, monster HP 3, monster count 5, timer 300, auto speak true.
- Timer presets: `30`, `180`, `300`, `600`.
- Custom timer range: `1..3600`.
- First battle mode supports `Choice`; type boundaries for FillLetter and Spell must exist.
- Correct answer damages monster.
- Wrong answer damages player.
- Three consecutive correct answers trigger double damage.
- Battle ends on monsters defeated, player HP 0, or timer 0.
- Stars and coin delta follow HarmonyOS result semantics.

## Parent Requirements

- Parent PIN is six digits.
- Empty PIN opens setup guidance.
- ParentAdmin is gated when PIN exists.
- ParentAdmin uses fakeable `ParentApiClient`.
- LessonDraftReview supports keep/drop/edit, approve, reject, and already-reviewed handling.

## Verification

Required JVM tests:

- `BattleEngineTest`
- `QuestionGeneratorTest`
- `GameConfigStoreTest`
- `ParentPinStoreTest`
- `LessonDraftReviewStoreTest`
- Parent DTO decoding tests

Required UI tests:

- Home starts deterministic battle.
- Battle reaches Result.
- Config saves custom timer `3`.
- PIN gate protects ParentAdmin.
- ParentAdmin fake refresh renders.
- LessonDraftReview fake approve returns to ParentAdmin.

## Explicit Deferrals

- Real camera/gallery permission behavior.
- Real server auth and networking.
- PackManager full sync/activation.
- Device binding.
- DevMenu and preview bypass.
