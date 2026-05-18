# V0.8.4 — Battle Balance & Question Pacing — HarmonyOS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Inputs (frozen):**
> - Design: [`00-design.md`](00-design.md)
> - Prerequisite: [V0.8.3 plan](../2026-05-18-battle-polish-v0-8-3/10-harmony-plan.md) merged or equivalent on branch
>
> **Run loop:** [`.cursor/skills/harmony-autofix-orchestrator/SKILL.md`](../../../.cursor/skills/harmony-autofix-orchestrator/SKILL.md) — commands from [`.cursor/ohos-dev-commands.md`](../../../.cursor/ohos-dev-commands.md).

**Goal:** Default magician HP 10; Spell wrong letter tap costs 1 HP; today/plan battles use Config-derived **schedule modes** (§5.3.1 in design).

**Architecture:**

- **Sub-task A:** Constants + `GameConfig` default + Config copy — `DEFAULT_PLAYER_HP`, `GameConfig.playerMaxHp`.
- **Sub-task B:** `SpellingArea` → `BattlePage` wrong-tap penalty path (engine seam + floater).
- **Sub-task C:** `BattleQuestionScheduler` + `PlanQuestionSource` — four modes: `single_type` (100%), `intro_only` (whole battle Intro), `challenge_only` (Challenge from Q1), `two_phase` (intro pass → 50/50 challenge).
- **Sub-task D:** Version gate + full ohosTest pass.
- **Sub-task E:** ohosTest refactor (专测模式 A — Config single-type, no monster-slot walks).

**Tech Stack:** HarmonyOS NEXT, ArkTS, Hypium `entry/src/test/`, ohosTest `entry/src/ohosTest/ets/test/`.

---

## Sub-task A — Default player HP 10

### Task A.1: Engine + config defaults

**Files:**

- Modify: `harmonyos/entry/src/main/ets/services/BattleEngine.ets` — `DEFAULT_PLAYER_HP = 10`
- Modify: `harmonyos/entry/src/main/ets/models/GameConfig.ets` — `playerMaxHp` default `10`
- Modify: `harmonyos/entry/src/test/LocalUnit.test.ets` (or `defaultsMatchEngineDefaults` host) — expect 10
- Modify: `docs/WordMagicGame_overall_spec.md` §4.1 table (via docs task below)

- [ ] Bump `DEFAULT_PLAYER_HP` and `GameConfig` default; keep clamp `[1, 10]`.
- [ ] Run `cd harmonyos && hvigorw -p module=entry@default test`; green.

---

## Sub-task B — Spell wrong letter tap → HP -1

### Task B.1: Engine penalty seam

**Files:**

- Modify: `harmonyos/entry/src/main/ets/services/BattleEngine.ets`
- Test: `harmonyos/entry/src/test/BattleEngine.test.ets`

- [ ] Add `applySpellLetterPenalty(): number` (or similar) that subtracts 1 from player HP, returns `1`, ends battle with `Lost` at 0 HP without advancing question.
- [ ] Tests: `spellWrongTapDamagesOne`; `spellWrongTapAtOneHpEndsBattle`.

### Task B.2: UI wiring

**Files:**

- Modify: `harmonyos/entry/src/main/ets/components/SpellingArea.ets` — new callback `onWrongLetterTap: () => void`
- Modify: `harmonyos/entry/src/main/ets/pages/BattlePage.ets` — mirror wrong-answer feedback (backward projectile, `playerHurtPulse`, `pushFloater('player', 1)`); do **not** call `submitAnswer`
- Test: `harmonyos/entry/src/ohosTest/ets/test/SpellQuestionFlow.ui.test.ets` — extend or add case: wrong tap reduces HP text / HP bar (assert `CharacterCard` HP label or battle state if exposed)

- [ ] Wire callback on wrong pool tap (after shake starts).
- [ ] Run `scripts/run_ui_tests.sh --suite SpellQuestionFlow` (or targeted test name).

---

## Sub-task C — Question scheduler (intro + 50/50 challenge)

### Task C.1: `BattleQuestionScheduler`

**Files:**

- Create: `harmonyos/entry/src/main/ets/services/BattleQuestionScheduler.ets`
- Test: `harmonyos/entry/src/test/BattleQuestionScheduler.test.ets`
- Register in: `harmonyos/entry/src/test/List.test.ets`

- [ ] Constructor takes `enabledTypes: string[]`; compute `BattleScheduleMode` per design §5.3.1 (`single_type` | `intro_only` | `challenge_only` | `two_phase`).
- [ ] **`single_type`:** always return the one kind.
- [ ] **`intro_only`:** intro pass → intro sustain; **never** emit challenge kinds.
- [ ] **`challenge_only`:** challenge roll from Q1; intro pass flag stays false.
- [ ] **`two_phase`:** intro pass until completion predicate → then challenge loop.
- [ ] Per-word caps: at most one `choice` and one `fill-letter` per `wordId` (when those kinds are in `effectiveIntroPool`).
- [ ] Tests:
  - `deriveScheduleModeForSingleType` / `IntroOnly` / `ChallengeOnly` / `TwoPhase`
  - `singleEnabledTypeAlwaysReturnsThatKind`
  - `introOnlyNeverReturnsChallengeKind`
  - `challengeOnlyNeverReturnsIntroKind`
  - `introNeverRepeatsChoiceForSameWord` (`two_phase` + `intro_only`)
  - `introNeverRepeatsFillLetterForSameWord`
  - `twoPhaseTransitionsToChallengeAfterIntroPassComplete`
  - `challengeRollsAreFiftyFiftyWhenBothChallengeTypesEnabled`
  - `challengeUsesOnlyEnabledSpellWhenMediumDisabled`

### Task C.2: `PlanQuestionSource` integration

**Files:**

- Modify: `harmonyos/entry/src/main/ets/services/PlanQuestionSource.ets`
- Modify: `harmonyos/entry/src/main/ets/pages/BattlePage.ets` — construct scheduler from `todayPlan.wordPlan` at battle start; pass into source
- Test: `harmonyos/entry/src/test/PlanQuestionSource.test.ets`

- [ ] Replace `questionTypeForMonsterLevel` primary pick with scheduler output for today mode.
- [ ] Thread `enabledQuestionTypes` from `BattlePage` (same snapshot as plan build) into `PlanQuestionSource` / scheduler.
- [ ] Leave `monsterIndexProvider` in place for catalog / bonus / UI only.
- [ ] Update `PlanQuestionSource.test.ets` for single-type and multi-type schedules.

---

## Sub-task E — ohosTest 专测模式 A

> **Contract:** `selectOnlyQuestionTypeShared(driver, typeId)` → save Config → **100%** of battle questions use `typeId` (see design §5.4). Do **not** depend on monster slot index.

### Task E.1: Shared battle test helpers

**Files:**

- Create or extend: `harmonyos/entry/src/ohosTest/ets/test/UiTestBattleHelpers.ets` (or exports on `RoutingFlow.ui.test.ets`)

- [ ] `assertPlayerHp(driver, current, max)` — parse `HP cur / max` text (default max **10** after V0.8.4).
- [ ] `detectQuestionSurface(driver)` → `'choice' | 'fill-letter' | 'fill-letter-medium' | 'spell'` via `BattlePrompt` vs `LetterTemplateRow` vs `BattleSpellArea`.
- [ ] `advanceOneCorrect(driver)` — dispatch to `tapCorrectAnswerShared` / letter tap / spell pool helpers.

### Task E.2: HP literal updates

**Files:**

- Modify: `RoutingFlow.ui.test.ets`, `MagicAttack.ui.test.ets`, `ReviewMode.ui.test.ets` (comments)

- [ ] Replace `HP 5 / 5` → `HP 10 / 10`, `HP 4 / 5` → `HP 9 / 10` (or use `assertPlayerHp`).

### Task E.3: `FillLetterFlow.ui.test.ets`

- [ ] Remove comments/assertions that require **monster 2 / slot 4 (Elite)** for FillLetter variants.
- [ ] `singleLetterFillAcceptsCorrectLetter`: after `selectOnlyQuestionType('fill-letter')` + start battle, poll until `LetterTemplateRow` with exactly **one** `_` (max N turns), then tap correct letter — **no** “defeat monster 1 first” loop.
- [ ] `mediumLetterFillCompletesBothSteps`: `selectOnlyQuestionType('fill-letter-medium')`; poll until **two** blanks / step-advance feedback; same surface-detection pattern.

### Task E.4: `SpellQuestionFlow.ui.test.ets`

- [ ] `selectOnlyQuestionType('spell')` → expect `BattleSpellArea` on first question (or within 1–2 turns), not `driveUntilSpell(..., 50)` walking monster slots.
- [ ] `fillsSpellSlotsByTappingCorrectPoolLetters`: keep happy path; shorten entry path.
- [ ] `rejectsTapsThatDoNotMatchTheNextSlot`: keep slot-row unchanged; **add** assert player HP decreases by 1 (and optional `BattleDamageFloaterLabel_player` after impact delay).
- [ ] New `spellWrongTapDecreasesPlayerHp` if split from above.

### Task E.5: Schedule-mode UI smokes (optional)

**Files:**

- Create: `harmonyos/entry/src/ohosTest/ets/test/BattlePacing.ui.test.ets`

- [ ] `two_phase`: `selectAllQuestionTypesShared` — over K turns, see Choice, single fill, then medium or Spell.
- [ ] `intro_only`: `selectQuestionTypes(['choice','fill-letter'])` — K turns without `BattleSpellArea` / two-blank medium.
- [ ] `challenge_only`: `selectQuestionTypes(['fill-letter-medium','spell'])` — first question is not Choice-only (detect medium or Spell surface).
- [ ] Register only if stable on CI.

### Task E.6: `List.test.ets` comments

- [ ] Update FillLetter/Spell header comments: no longer “monster slot ordering”; single-type 100% via Config.
- [ ] Keep **FillLetterFlow / SpellQuestionFlow before AdventureFlow** (plan consumption).

- [ ] Run `scripts/run_ui_tests.sh --suite FillLetterFlow`, `--suite SpellQuestionFlow`, `--suite MagicAttack`, `--suite RoutingFlow`.

---

## Sub-task D — Version gate

- [ ] `harmonyos/AppScope/app.json5`: `versionName` `0.8.4`, `versionCode` `1008004`
- [ ] `cd harmonyos && hvigorw assembleHap` — 0 `ArkTS:WARN`
- [ ] `cd harmonyos && codelinter -c ./code-linter.json5 . --fix`
- [ ] `scripts/run_ui_tests.sh` green (or agreed suite subset documented in PR)

---

## Explicitly out of Harmony V0.8.4 scope (document only)

- Review-mode scheduler parity (unless trivial to share `PlanQuestionSource` path).
- iOS / Android — Stage 4 after `20-replication-trigger.md` signature.
- Changing `playerMaxHp` Config max above 10.
