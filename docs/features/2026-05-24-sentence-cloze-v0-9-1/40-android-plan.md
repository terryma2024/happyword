# V0.9.1 — Sentence Cloze — Android Replication Plan

> Inputs (frozen after Stage 3): [`00-design.md`](00-design.md), [`20-replication-trigger.md`](20-replication-trigger.md)
> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Status:** Completed on 2026-05-24 after `20-replication-trigger.md` was signed with `replication_approved: true`.

**Verification:** `testDebugUnitTest`, `assembleDebug`, `assembleDebugAndroidTest`, and focused `connectedDebugAndroidTest` for sentence-cloze Battle UI + config passed on the connected emulator.

**Goal:** Replicate the frozen HarmonyOS V0.9.1 sentence cloze feature in the native Kotlin / Jetpack Compose client without redesigning it.

**Architecture:** Add `QuestionKind.SentenceCloze`, sentence template fields, and a Kotlin generator that mirrors Harmony matching rules. Extend type policy, scheduler, battle generation, settings UI, Compose test tags, TTS auto-speak gating, built-in examples, and Android metadata to 0.9.1 / 1009001.

**Tech Stack:** Kotlin, Jetpack Compose, JUnit, Compose UI tests, Gradle Android Plugin.

---

### Task 1: Model, Generator, and Policy

**Files:**
- Modify: `android/app/src/main/java/cool/happyword/wordmagic/core/Models.kt`
- Modify: `android/app/src/main/java/cool/happyword/wordmagic/core/BattleEngine.kt`
- Modify: `android/app/src/main/java/cool/happyword/wordmagic/core/BattleQuestionTypePolicy.kt`
- Modify: `android/app/src/test/java/cool/happyword/wordmagic/core/BattleQuestionTypeTest.kt`
- Modify: `android/app/src/test/java/cool/happyword/wordmagic/core/GameConfigTest.kt`

- [ ] Write failing JUnit coverage for sentence-cloze matching, substring rejection, phrase matching, default type order including `sentence-cloze`, and eligibility requiring bilingual examples.
- [ ] Run focused JVM tests with `cd android && ./gradlew testDebugUnitTest`; expect failures before implementation.
- [ ] Extend `WordEntry` with optional `distractors` and `example`, add `ExampleSentence`, add `QuestionKind.SentenceCloze`, and add `sentenceTemplate` / `sentenceZh` to `Question`.
- [ ] Implement Harmony-equivalent target-span matching and sentence cloze question generation in `BattleEngine`.
- [ ] Add `sentence-cloze` to policy constants, default ordering, display label `句子填词`, kind mapping, eligibility, and fallback chain.
- [ ] Re-run focused JVM tests and expect green.

### Task 2: Scheduler and Battle Source

**Files:**
- Modify: `android/app/src/main/java/cool/happyword/wordmagic/core/BattleQuestionScheduler.kt`
- Modify: `android/app/src/main/java/cool/happyword/wordmagic/core/BattleEngine.kt`
- Modify: `android/app/src/test/java/cool/happyword/wordmagic/core/BattleQuestionSchedulerTest.kt`
- Modify: `android/app/src/test/java/cool/happyword/wordmagic/core/BattleQuestionTypeTest.kt`

- [ ] Write failing tests that Challenge mode can roll among three active Challenge types, disabling sentence cloze prevents it, sentence-cloze-only battles emit cloze questions when examples exist, and fall back to Choice without examples.
- [ ] Run focused JVM tests; expect failures before implementation.
- [ ] Add sentence cloze to the Challenge pool and use uniform RNG selection over all active Challenge types.
- [ ] Add sentence cloze generation to `questionForType` and normal answer correctness semantics.
- [ ] Re-run focused JVM tests and expect green.

### Task 3: Settings, Battle UI, and TTS

**Files:**
- Modify: `android/app/src/main/java/cool/happyword/wordmagic/ui/config/ConfigUi.kt`
- Modify: `android/app/src/main/java/cool/happyword/wordmagic/ui/battle/BattleUi.kt`
- Modify: `android/app/src/androidTest/java/cool/happyword/wordmagic/FamilyLearningFlowTest.kt`
- Modify: `android/app/src/androidTest/java/cool/happyword/wordmagic/SmokeTest.kt`

- [ ] Write failing Compose UI assertions for `ConfigQuestionType_sentence-cloze`, `BattleSentenceClozePrompt`, `BattleSentenceClozeZh`, `BattleOptionsRow_SentenceCloze`, and `BattleSentenceClozeOption_0..2`.
- [ ] Run `cd android && ./gradlew connectedDebugAndroidTest` when a device is available; expect missing-tag failures before implementation.
- [ ] Render sentence cloze with the English cloze sentence and Chinese example support text.
- [ ] Use sentence-cloze-specific option test tags and keep 3-option Choice damage semantics.
- [ ] Suppress automatic TTS when `state.question.kind == QuestionKind.SentenceCloze`; keep `BattleSpeakerButton` manual speak unchanged.
- [ ] Re-run Compose UI tests when a device is available.

### Task 4: Built-in Examples and Version

**Files:**
- Modify: `android/app/src/main/java/cool/happyword/wordmagic/core/PackModels.kt`
- Modify: `android/app/src/test/java/cool/happyword/wordmagic/core/PackModelsTest.kt`
- Modify: `android/app/build.gradle.kts`
- Modify: `docs/features/2026-05-24-sentence-cloze-v0-9-1/50-parity-checklist.md`

- [ ] Write or update tests asserting every Android built-in word has `example.en`, `example.zh`, and supports sentence cloze.
- [ ] Add approved examples to every Android built-in word entry.
- [ ] Bump `versionName` to `0.9.1` and `versionCode` to `1_009_001`.
- [ ] Run `cd android && ./gradlew testDebugUnitTest` and `cd android && ./gradlew assembleDebug`.
- [ ] Mark verified Android rows in the parity checklist.
