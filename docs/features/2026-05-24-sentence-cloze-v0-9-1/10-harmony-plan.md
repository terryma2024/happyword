# V0.9.1 — Sentence Cloze — HarmonyOS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Inputs (frozen):**
> - Design: [`00-design.md`](00-design.md)
>
> **Run loop:** [`.cursor/skills/harmony-autofix-orchestrator/SKILL.md`](../../../.cursor/skills/harmony-autofix-orchestrator/SKILL.md) drives build -> codelinter -> unit -> emulator -> ohosTest. Commands come from [`.cursor/ohos-dev-commands.md`](../../../.cursor/ohos-dev-commands.md). Do not invent flags.

**Goal:** Implement V0.9.1 sentence cloze questions on HarmonyOS first.

**Architecture:** Add `QuestionKind.SentenceCloze` plus `SentenceClozeGenerator` for example-backed cloze prompts. Extend the existing question-type policy and scheduler so `sentence-cloze` is default-enabled and part of the Challenge pool. Battle UI reuses option buttons with sentence-specific IDs, while built-in JSON packs receive `example.en` / `example.zh` for every word.

**Tech Stack:** HarmonyOS NEXT, ArkTS, ArkUI, Hypium local tests, ohosTest UI automation.

---

### Task 1: Sentence Cloze Model and Generator

**Files:**
- Create: `harmonyos/entry/src/main/ets/services/SentenceClozeGenerator.ets`
- Modify: `harmonyos/entry/src/main/ets/models/Question.ets`
- Modify: `harmonyos/entry/src/test/List.test.ets`
- Test: `harmonyos/entry/src/test/SentenceClozeGenerator.test.ets`

- [ ] Write failing tests for:
  - whole-word matching (`apple` in `I eat an apple.`);
  - partial-substring rejection (`cat` in `caterpillar`);
  - phrase matching (`magic wand` in `I hold a magic wand.`);
  - first-match-only replacement;
  - case-insensitive option uniqueness and repo fallback.
- [ ] Run `cd harmonyos && hvigorw -p module=entry@default test --tests SentenceClozeGenerator` and confirm it fails because the generator/model do not exist yet.
- [ ] Add `QuestionKind.SentenceCloze`, `sentenceTemplate`, and `sentenceZh` fields to `Question`.
- [ ] Add `isValidSentenceCloze()` requiring non-empty `sentenceTemplate`, `sentenceZh`, 3 unique options, and `answer` inside options.
- [ ] Implement `findSentenceClozeTargetSpan`, `wordSupportsSentenceCloze`, and `SentenceClozeGenerator.generate`.
- [ ] Register the new test module in `harmonyos/entry/src/test/List.test.ets`.
- [ ] Re-run the focused generator test and expect green.

### Task 2: Type Policy, Scheduler, and Plan Source

**Files:**
- Modify: `harmonyos/entry/src/main/ets/services/BattleQuestionTypePolicy.ets`
- Modify: `harmonyos/entry/src/main/ets/services/BattleQuestionScheduler.ets`
- Modify: `harmonyos/entry/src/main/ets/services/PlanQuestionSource.ets`
- Modify: `harmonyos/entry/src/test/BattleQuestionTypePolicy.test.ets`
- Modify: `harmonyos/entry/src/test/BattleQuestionScheduler.test.ets`
- Modify: `harmonyos/entry/src/test/PlanQuestionSource.test.ets`

- [ ] Write failing policy tests that default types contain `sentence-cloze`, sanitization preserves it in canonical order, and `wordSupportsQuestionType` requires a matching bilingual example.
- [ ] Write failing scheduler tests that Challenge pool can roll among three enabled Challenge types and never emits `sentence-cloze` when disabled.
- [ ] Write failing `PlanQuestionSource` tests for a sentence-cloze-only battle and fallback to Choice when no planned word supports sentence cloze.
- [ ] Run focused unit tests and confirm expected failures.
- [ ] Add `sentence-cloze` to implemented/default type policy and fallback chains.
- [ ] Change Challenge selection from two-way 50/50 to uniform selection over `effectiveChallengePool`.
- [ ] Inject `SentenceClozeGenerator` into `PlanQuestionSource` and generate exact sentence cloze questions.
- [ ] Re-run focused unit tests and expect green.

### Task 3: Settings UI and ohosTest Helpers

**Files:**
- Modify: `harmonyos/entry/src/main/ets/pages/ConfigPage.ets`
- Modify: `harmonyos/entry/src/ohosTest/ets/test/RoutingFlow.ui.test.ets`
- Modify: `harmonyos/entry/src/ohosTest/ets/test/ConfigFlow.ui.test.ets`

- [ ] Update ConfigFlow UI assertions so `ConfigQuestionType_sentence-cloze` must exist and legacy `ConfigQuestionType_sentence-fill` must not exist.
- [ ] Update shared `QUESTION_TYPE_IDS` to include `sentence-cloze`.
- [ ] Run the relevant ohosTest target or full `scripts/run_ui_tests.sh` when a device is available; before implementation the new assertion should fail.
- [ ] Add label `句子填词` and helper-compatible chip rendering by relying on the default type list.
- [ ] Re-run the UI test path and expect green when the local device runner is available.

### Task 4: Built-in Pack Examples

**Files:**
- Modify: `harmonyos/entry/src/main/resources/rawfile/data/builtin/fruit-forest.json`
- Modify: `harmonyos/entry/src/main/resources/rawfile/data/builtin/school-castle.json`
- Modify: `harmonyos/entry/src/main/resources/rawfile/data/builtin/home-cottage.json`
- Modify: `harmonyos/entry/src/main/resources/rawfile/data/builtin/animal-safari.json`
- Modify: `harmonyos/entry/src/main/resources/rawfile/data/builtin/ocean-realm.json`
- Modify: `harmonyos/entry/src/test/BuiltinPackLoader.test.ets`

- [ ] Write a failing built-in pack test that loads all five JSON files and asserts every word has `example.en`, `example.zh`, and supports `sentence-cloze`.
- [ ] Run the focused built-in test and confirm it fails because examples are missing.
- [ ] Add short child-safe English and Chinese examples to every built-in word.
- [ ] Re-run the focused test and expect green.

### Task 5: Battle UI Wiring

**Files:**
- Modify: `harmonyos/entry/src/main/ets/pages/BattlePage.ets`
- Modify: `harmonyos/entry/src/main/ets/services/BattleEngine.ets`
- Modify: `harmonyos/entry/src/ohosTest/ets/test/BattlePacing.ui.test.ets`

- [ ] Add or update a UI test path that selects only `sentence-cloze`, enters Today Adventure, and asserts `BattleSentenceClozePrompt`, `BattleSentenceClozeZh`, `BattleOptionsRow_SentenceCloze`, and `BattleSentenceClozeOption_0..2`.
- [ ] Run the UI test path and confirm it fails before UI wiring when a device runner is available.
- [ ] Treat `SentenceCloze` as a normal 3-option answer in `BattleEngine.submitAnswer`.
- [ ] Preserve answered sentence fields during the BattlePage feedback window.
- [ ] Render sentence cloze prompt/Chinese support with the stable IDs from `00-design.md`.
- [ ] Use `BattleSentenceClozeOption_0..2` and `BattleOptionsRow_SentenceCloze` for sentence cloze, while keeping existing `BattleOptionA/B/C` for other 3-option questions.
- [ ] Re-run the UI test path and expect green when the local device runner is available.

### Task 6: Version, Gate Docs, and Verification

**Files:**
- Modify: `harmonyos/AppScope/app.json5`
- Modify: `docs/features/2026-05-24-sentence-cloze-v0-9-1/20-replication-trigger.md`
- Modify: `docs/features/2026-05-24-sentence-cloze-v0-9-1/50-parity-checklist.md`
- Optionally modify: `docs/WordMagicGame_roadmap.md`

- [ ] Bump HarmonyOS `versionName` to `0.9.1` and `versionCode` to `1009001`.
- [ ] Fill Stage 3 soft-gate evidence as commands complete.
- [ ] Mark HarmonyOS rows in the parity checklist that are verified by tests.
- [ ] Run `cd harmonyos && hvigorw -p module=entry@default test`.
- [ ] Run `cd harmonyos && hvigorw assembleHap` and confirm 0 `ArkTS:WARN` lines.
- [ ] Run `cd harmonyos && codelinter -c ./code-linter.json5 . --fix`.
- [ ] Run `scripts/run_ui_tests.sh` if a HarmonyOS device runner is available.
