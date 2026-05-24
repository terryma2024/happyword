# V0.9.1 — Sentence Cloze — iOS Replication Plan

> Inputs (frozen after Stage 3): [`00-design.md`](00-design.md), [`20-replication-trigger.md`](20-replication-trigger.md)
> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Status:** Completed on 2026-05-24 after `20-replication-trigger.md` was signed with `replication_approved: true`.

**Verification:** Focused iOS unit tests passed for generator, config, scheduler, pronunciation, and built-in packs; focused XCUITest passed for sentence-cloze Battle UI. `xcodegen` was not installed locally, so `ios/WordMagicGame.xcodeproj/project.pbxproj` version fields were synchronized manually with `ios/project.yml`.

**Goal:** Replicate the frozen HarmonyOS V0.9.1 sentence cloze feature in the native Swift / SwiftUI client without redesigning it.

**Architecture:** Add `QuestionKind.sentenceCloze`, sentence template fields on `Question`, and a Swift `SentenceClozeGenerator` that mirrors Harmony matching rules. Extend question-type policy, scheduler, plan source, settings, battle UI, pronunciation gating, built-in examples, and metadata version to 0.9.1 / 1009001.

**Tech Stack:** Swift, SwiftUI, XCTest, XCUITest, XcodeGen-managed project.

---

### Task 1: Model, Generator, and Policy

**Files:**
- Modify: `ios/WordMagicGame/Core/Question.swift`
- Modify: `ios/WordMagicGame/Core/WordRepository.swift`
- Modify: `ios/WordMagicGame/Core/BattleQuestionTypePolicy.swift`
- Modify: `ios/WordMagicGameTests/Core/QuestionGeneratorTests.swift`
- Modify: `ios/WordMagicGameTests/Core/GameConfigTests.swift`

- [ ] Write failing XCTest coverage for whole-word cloze matching, substring rejection, phrase matching, first-match replacement, case-insensitive distractor uniqueness, and default type order including `sentence-cloze`.
- [ ] Run focused unit tests: `cd ios && xcodebuild test -scheme WordMagicGame -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WordMagicGameTests/QuestionGeneratorTests -only-testing:WordMagicGameTests/GameConfigTests -derivedDataPath /private/tmp/wordmagic-dd`; expect failures for missing `sentenceCloze` APIs.
- [ ] Add `QuestionKind.sentenceCloze = "sentence-cloze"`, `sentenceTemplate`, and `sentenceZh` fields; make `Question.isValid` enforce a 3-option cloze question with answer included.
- [ ] Implement `findSentenceClozeTargetSpan`, `wordSupportsSentenceCloze`, and `SentenceClozeGenerator.generate` with the Harmony whitespace-tolerant phrase matching and first valid match rule.
- [ ] Add `sentence-cloze` to `BattleQuestionTypePolicy.defaultOrderedTypeIds`, eligibility, display label `句子填词`, and fallback chain.
- [ ] Re-run the focused unit tests and expect green.

### Task 2: Scheduler and Plan Source

**Files:**
- Modify: `ios/WordMagicGame/Core/BattleQuestionScheduler.swift`
- Modify: `ios/WordMagicGame/Core/WordRepository.swift`
- Modify: `ios/WordMagicGameTests/Core/BattleQuestionSchedulerTests.swift`
- Modify: `ios/WordMagicGameTests/Core/QuestionGeneratorTests.swift`

- [ ] Write failing tests that Challenge mode can roll among `fill-letter-medium`, `spell`, and `sentence-cloze`, that disabling sentence cloze prevents it, that sentence-cloze-only battles emit cloze questions when examples exist, and that they fall back to Choice without examples.
- [ ] Run focused tests for scheduler and question generator; expect failures before implementation.
- [ ] Add sentence cloze to the Challenge pool and change challenge selection from fixed 50/50 to uniform selection over the active Challenge pool.
- [ ] Inject `SentenceClozeGenerator` into `PlanQuestionSource` and generate exact cloze questions for resolved `sentence-cloze`.
- [ ] Re-run focused tests and expect green.

### Task 3: Settings, Battle UI, and Pronunciation

**Files:**
- Modify: `ios/WordMagicGame/Features/Settings/ConfigView.swift`
- Modify: `ios/WordMagicGame/Features/CoreLoop/BattleView.swift`
- Modify: `ios/WordMagicGame/Services/PronunciationService.swift`
- Modify: `ios/WordMagicGame/App/AppCoordinator.swift`
- Modify: `ios/WordMagicGameTests/Core/PronunciationServiceTests.swift`
- Modify: `ios/WordMagicGameUITests/WordMagicGameUITests.swift`

- [ ] Write failing tests that sentence cloze suppresses automatic pronunciation, settings exposes `ConfigQuestionType_sentence-cloze`, and Battle exposes `BattleSentenceClozePrompt`, `BattleSentenceClozeZh`, `BattleOptionsRow_SentenceCloze`, and `BattleSentenceClozeOption_0..2`.
- [ ] Run the focused unit/UI tests listed in `.cursor/ios-dev-commands.md`; expect missing IDs or pronunciation failures.
- [ ] Render sentence cloze with the English cloze sentence plus Chinese example support text; use the exact stable IDs from `00-design.md`.
- [ ] Keep answer buttons as normal 3-option buttons, but use sentence-cloze-specific option IDs.
- [ ] Update `shouldAutoSpeak` and coordinator call sites so sentence cloze never auto-speaks, while `BattleSpeakerButton` still manually speaks the answer.
- [ ] Re-run focused unit/UI tests and expect green.

### Task 4: Built-in Examples and Version

**Files:**
- Modify: `ios/WordMagicGame/Resources/BuiltinPacks/*.json`
- Modify: `ios/WordMagicGameTests/Core/BuiltinPackLoaderTests.swift`
- Modify: `ios/project.yml`
- Modify: `docs/features/2026-05-24-sentence-cloze-v0-9-1/50-parity-checklist.md`

- [ ] Write or update tests asserting every iOS built-in word has `example.en`, `example.zh`, and supports sentence cloze.
- [ ] Copy the approved Harmony built-in examples into the iOS JSON packs.
- [ ] Bump `MARKETING_VERSION` to `0.9.1` and `CURRENT_PROJECT_VERSION` to `1009001`.
- [ ] Run iOS unit tests and build commands from `.cursor/ios-dev-commands.md`.
- [ ] Mark verified iOS rows in the parity checklist.
