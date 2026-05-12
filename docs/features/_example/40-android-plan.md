# Example Stable-ID Toggle — Android Replication Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Inputs (frozen):**
> - Design: [`00-design.md`](00-design.md)
> - Replication trigger (must carry `replication_approved: true`): [`20-replication-trigger.md`](20-replication-trigger.md)
>
> **Do not redesign.** If you find an ambiguity, file it in `20-replication-trigger.md` §3 and update `00-design.md` first. Then come back here.
>
> **Run loop:** Commands come from [`.cursor/android-dev-commands.md`](../../../.cursor/android-dev-commands.md). Use `./gradlew` from `android/`.

**Goal:** Replicate the wrong-answer-cue toggle from HarmonyOS onto Android, preserving the four stable IDs and the one-frame skip marker semantics.

**Architecture:** Add `playWrongCue` to the Kotlin `GameConfig` data class; sanitize on load; branch in `AudioService.playWrongCue`; render a transient `Spacer().testTag("BattleWrongCueSkippedMarker")` for one recomposition on skip; add the Config row.

**Tech Stack:** Kotlin, Jetpack Compose, JUnit, Compose UI tests.

---

### Pre-flight: verify the trigger is signed

- [x] Opened [`20-replication-trigger.md`](20-replication-trigger.md). `replication_approved: true`, signed by `SOP authors` on `2026-05-12`. Proceeding.

### Task 1: Domain types and pure logic

**Files:**
- Modify: `android/app/src/main/java/cool/happyword/wordmagic/core/GameConfig.kt`
- Modify: `android/app/src/main/java/cool/happyword/wordmagic/core/AudioService.kt`
- Test: `android/app/src/test/java/cool/happyword/wordmagic/core/GameConfigTest.kt`
- Test: `android/app/src/test/java/cool/happyword/wordmagic/core/AudioServiceTest.kt`

- [x] Add `playWrongCue: Boolean = true`.
- [x] Sanitize on load: missing or non-boolean → `true`.
- [x] `AudioService.playWrongCue` reads the value lazily (per trigger §2.6).
- [x] JUnit cases mirror trigger §2.5 rows 1, 2, 5.

### Task 2: Compose screens with stable test tags

**Files:**
- Modify: `android/app/src/main/java/cool/happyword/wordmagic/ui/config/ConfigScreen.kt`
- Modify: `android/app/src/main/java/cool/happyword/wordmagic/ui/battle/BattleScreen.kt`

- [x] Add a Switch row with `Modifier.testTag("ConfigWrongCueRow")` on the Row, `"ConfigWrongCueLabel"` on the Text, `"ConfigWrongCueSwitch"` on the Switch.
- [x] On Battle, render `Spacer(Modifier.testTag("BattleWrongCueSkippedMarker"))` while a `skipMarkerFrame` flag is true, then flip it off via `LaunchedEffect`.

### Task 3: Compose UI tests + UI Automator parity

**Files:**
- Create: `android/app/src/androidTest/java/cool/happyword/wordmagic/WrongCueUITest.kt`

- [x] `togglesSkipMarker` — flips toggle off, drives a wrong answer, asserts marker visible.
- [x] `noMarkerWhenOn` — leaves toggle on, drives a wrong answer, asserts marker absent.

### Task 4: Versioning and screenshots

**Files:**
- Modify: `android/app/build.gradle.kts`.

- [x] `versionName = "0.6.7.9"` (matches HarmonyOS).
- [x] `versionCode` → next monotonic integer per the existing Android rule.
- [x] Captured `assets/screenshots/android/config.png` at the new row.

### Task 5: Verification

- [x] `cd android && ./gradlew testDebugUnitTest` green.
- [x] `WrongCueUITest` green on the running emulator.
- [x] `cd android && ./gradlew assembleDebug` clean for changed files.
- [x] Updated [`50-parity-checklist.md`](50-parity-checklist.md) Android columns.
