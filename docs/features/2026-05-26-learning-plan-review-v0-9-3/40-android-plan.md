# V0.9.3 Learning Plan + Review — Android Replication Plan

> Inputs: [`00-design.md`](00-design.md), signed [`20-replication-trigger.md`](20-replication-trigger.md)
>
> Gate: `replication_approved: true` by `matianyi` on `2026-05-26`.

**Goal:** Replicate the V0.9.3 daily learning state, stable review snapshot, Home A/B label, and review battle sizing on Android.

**Architecture:** Add an Android core daily-learning service around persisted local state and existing pack/stat models. Wire the Compose shell to generate the daily snapshot before Home battle entries, mark pack wins and review answers, and render the new stable test tags.

**Tech Stack:** Kotlin, Jetpack Compose, SharedPreferences, JVM JUnit, Compose UI tests.

---

## Task 1: Core Daily State Rules

**Files:**
- Create: `android/app/src/test/java/cool/happyword/wordmagic/core/DailyLearningStateServiceTest.kt`
- Create: `android/app/src/main/java/cool/happyword/wordmagic/core/DailyLearningStateService.kt`
- Modify: `android/app/src/main/java/cool/happyword/wordmagic/core/LearningRecorder.kt`

- [x] Write failing JVM tests for compact day key, snapshot stability, same-day exclusion, 50 cap, reason priority, A/B matrix, and review monster count.
- [x] Implement the service and stat fields needed by the tests.
- [x] Run the focused JVM test until green.

## Task 2: Android Persistence

**Files:**
- Modify: `android/app/src/main/java/cool/happyword/wordmagic/data/AndroidLocalProgressRepositories.kt`
- Test through: `DailyLearningStateServiceTest.kt` and existing recorder tests.

- [x] Add load/save methods for `daily_learning_state/snapshot_v1`.
- [x] Extend learning stats serialization with `lastOutcome` and scheduler fields while accepting legacy 6-column rows.

## Task 3: Home, Battle, Today Plan Wiring

**Files:**
- Modify: `android/app/src/main/java/cool/happyword/wordmagic/ui/navigation/WordMagicGameApp.kt`
- Modify: `android/app/src/main/java/cool/happyword/wordmagic/ui/home/HomeScreen.kt`
- Modify: `android/app/src/main/java/cool/happyword/wordmagic/core/TodayPlanService.kt`
- Modify: `android/app/src/main/java/cool/happyword/wordmagic/ui/LocalGrowthScreens.kt`

- [x] Generate/reuse the daily snapshot before Home battle and review entry.
- [x] Mark A after a won non-review Home battle.
- [x] Mark reviewed word IDs after each review answer.
- [x] Use 600 seconds and dynamic monster count for review battles.
- [x] Render `AdventureCardDailyStatusLabel`, `HomeReviewCountBadge`, `HomeReviewEmptyToast`, `TodayPlanReviewRequiredSection`, and `TodayPlanReviewDone-<wordId>`.

## Task 4: Android Tests + Verification

**Files:**
- Create: `android/app/src/androidTest/java/cool/happyword/wordmagic/HomeDailyLearningUiTest.kt`
- Modify as needed: existing Android tests affected by renamed tags/copy.

- [x] Add Compose UI coverage for Home A/B label and review count/empty toast tags.
- [x] Run `cd android && ./gradlew testDebugUnitTest`.
- [x] Run `cd android && ./gradlew assembleDebug`.
- [x] Run `cd android && ./gradlew connectedDebugAndroidTest` if an Android device/emulator is available.
