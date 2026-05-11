# Question Type Config Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a persisted battle question-type selector that drives today-plan monster kinds and allows UI tests to force a specific implemented question type.

**Architecture:** Store enabled question types on `GameConfig`, centralize ordering/eligibility/mapping in `BattleQuestionTypePolicy`, and make today-plan creation cycle selected types into matching monster slots. `PlanQuestionSource` then generates the exact kind for each slot and skips ineligible words rather than degrading to another type.

**Tech Stack:** HarmonyOS NEXT, ArkTS, ArkUI, Hypium local tests, ohosTest UI automation.

---

### Task 1: Policy And Config Model

**Files:**
- Create: `harmonyos/entry/src/main/ets/services/BattleQuestionTypePolicy.ets`
- Create: `harmonyos/entry/src/test/BattleQuestionTypePolicy.test.ets`
- Modify: `harmonyos/entry/src/main/ets/models/GameConfig.ets`
- Modify: `harmonyos/entry/src/main/ets/services/GameConfigPersistence.ets`
- Modify: `harmonyos/entry/src/test/List.test.ets`

- [ ] Write failing policy/config tests for default type order, sanitization, eligibility, and type-to-monster mapping.
- [ ] Run local tests and confirm the new tests fail because the policy/config field is missing.
- [ ] Implement the policy helper plus `GameConfig.enabledQuestionTypes` clone/persistence support.
- [ ] Re-run local tests and confirm the new tests pass.

### Task 2: Today Plan Type-Driven Monster Slots

**Files:**
- Modify: `harmonyos/entry/src/main/ets/services/TodayAdventureBuilder.ets`
- Modify: `harmonyos/entry/src/test/TodayAdventureBuilder.test.ets`

- [ ] Write failing tests that `build(..., [FillLetterMedium])` produces only Elite slots and `build(..., [Choice, Spell])` alternates Normal/Boss.
- [ ] Run tests and confirm failure on current region-template behavior.
- [ ] Update builder APIs to accept selected question types and generate matching monster slots.
- [ ] Re-run builder tests.

### Task 3: Exact-Kind Plan Question Source

**Files:**
- Modify: `harmonyos/entry/src/main/ets/services/PlanQuestionSource.ets`
- Modify: `harmonyos/entry/src/test/PlanQuestionSource.test.ets`

- [ ] Write failing tests that Boss with a 3-letter word skips to an eligible Spell word instead of falling back to FillLetter, and Elite with a 3-letter word skips to an eligible Medium word.
- [ ] Run tests and confirm failure on the current fallback behavior.
- [ ] Implement exact-kind generation with in-plan word skipping and safe final fallback to choice only if no exact-kind word exists.
- [ ] Re-run source tests.

### Task 4: Config UI And Home Blocking

**Files:**
- Modify: `harmonyos/entry/src/main/ets/pages/ConfigPage.ets`
- Modify: `harmonyos/entry/src/main/ets/pages/HomePage.ets`

- [ ] Add ConfigPage chips for four implemented types plus disabled sentence-fill.
- [ ] Prevent disabling the final implemented type with an inline hint.
- [ ] Validate active pack eligibility before routing from Home and show an inline toast if no selected type can be generated.

### Task 5: UI Automation Uses Product Config

**Files:**
- Modify: `harmonyos/entry/src/ohosTest/ets/test/RoutingFlow.ui.test.ets`
- Modify: `harmonyos/entry/src/ohosTest/ets/test/FillLetterFlow.ui.test.ets`
- Modify: `harmonyos/entry/src/ohosTest/ets/test/SpellQuestionFlow.ui.test.ets`
- Modify: `harmonyos/entry/src/ohosTest/ets/test/ConfigFlow.ui.test.ets`

- [ ] Add shared helpers to open Config, select exactly one question type, save, and return Home.
- [ ] Update FillLetterFlow to select `fill-letter` and `fill-letter-medium` explicitly.
- [ ] Update SpellQuestionFlow to select `spell` explicitly.
- [ ] Add ConfigFlow coverage for persistence, last-enabled protection, and disabled sentence-fill.

### Task 6: Verification

**Files:**
- Validate changed HarmonyOS source and tests.

- [ ] Run focused local tests for policy, builder, and source.
- [ ] Run `FillLetterFlow` and `SpellQuestionFlow` UI suites.
- [ ] Run Harmony build and check for zero `ArkTS:WARN` lines.
- [ ] Read lints for edited files and fix newly introduced diagnostics.
