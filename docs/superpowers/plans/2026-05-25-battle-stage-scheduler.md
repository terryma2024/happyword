# Battle Stage Scheduler Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement V0.9.2 battle sequencing so enabled question types run in strict difficulty stages, words complete each stage before advancing the question stage, and newly spawned monsters are selected from the currently active stage's difficulty pool.

**Architecture:** Add a focused `BattleStageScheduler` service that owns stage state, per-stage word coverage, monster-to-stage assignment, and catalog index selection. Question-stage progress advances as soon as the current stage's supported words are covered; existing monsters keep their original catalog assignment until defeated, and only newly spawned monsters bind to the then-active stage. `PlanQuestionSource` asks it for the next `(wordId, questionKind)` and `BattlePage` uses the same instance for current monster catalog lookup. Boss dialogue display becomes per-catalog-once per battle and Super uses the ordinary bubble presentation.

**Tech Stack:** HarmonyOS ArkTS / ArkUI, Hypium unit tests, existing `WordRepository`, `QuestionKind`, `MonsterCatalog`, and `PlanQuestionSource`.

---

### Task 1: Document Cross-Platform Battle Stage Rules

**Files:**
- Modify: `docs/features/2026-05-25-boss-dialogue-v0-9-2/60-followups.md`

- [ ] **Step 1: Add a Battle Stage Scheduling section**

Append:

```markdown
## 2026-05-25 Battle stage scheduling rule

Question types are stage-ordered by difficulty:

1. `choice` — 中文选词
2. `fill-letter` — 单字母填空
3. `fill-letter-medium` — 双字母填空
4. `spell` — 多字母选择
5. `sentence-cloze` — 句子填词

Within the user's enabled question-type set, battle stages run strictly from easy to hard. For a stage `QTn`, all words in the selected pack that support `QTn` must be served at least once before the scheduler may advance to `QTn+1`.

Question-stage coverage and monster lifetime are decoupled:

- If a monster dies before the current stage's word coverage is complete, spawn another monster from the same stage difficulty pool and continue with the next uncovered word.
- When the current stage's words are all covered, advance immediately to the next enabled stage with supported words, even if the current monster is still alive.
- The current monster keeps its original catalog identity and difficulty level until defeated, even if it survives across one or more question-stage advances.
- When that monster is defeated, spawn the next monster from the difficulty pool of the question stage that is active at that moment. For example, if `M1L1` survives through `QT1` and `QT2` and dies during `QT3`, the next monster is `M?L3`.
- If all enabled stages are complete but `monstersTotal` is not yet reached, stay on the last enabled supported stage and keep spawning monsters from that stage's difficulty pool until `monstersTotal` ends the battle.

Current platform difficulty mapping uses existing catalog levels:

| Question type | Stage label | Catalog pool |
| --- | --- | --- |
| `choice` | L1 | `MonsterLevel.Beginner` |
| `fill-letter` | L2 | `MonsterLevel.Intermediate` |
| `fill-letter-medium` | L3 | `MonsterLevel.Advanced` |
| `spell` | L4 | `MonsterLevel.Super` |
| `sentence-cloze` | L5 semantic stage | `MonsterLevel.Super` until a fifth art/catalog level exists |

This mapping is strict: a lower stage must not spawn a higher-level monster, and a higher stage must not fall back to a lower-level monster. If no word supports a question type, skip that stage and do not spawn its monster level.

Dialogue presentation follows catalog identity per battle:

- Super monsters use the same non-blocking bubble presentation as ordinary monsters.
- The first appearance of a catalog monster in a battle may show intro and defeat lines.
- If the same catalog monster appears again in the same battle, suppress both intro and defeat lines.

Replication note: iOS and Android must implement the same state machine; do not reuse the older intro/challenge random scheduler.
```

- [ ] **Step 2: Review the document**

Run: `sed -n '1,260p' docs/features/2026-05-25-boss-dialogue-v0-9-2/60-followups.md`

Expected: The new section explicitly states the C rule for post-stage completion and the current four-level catalog mapping.

### Task 2: Add BattleStageScheduler with Full Branch UT

**Files:**
- Create: `harmonyos/entry/src/main/ets/services/BattleStageScheduler.ets`
- Create: `harmonyos/entry/src/test/BattleStageScheduler.test.ets`
- Modify: `harmonyos/entry/src/test/List.test.ets`

- [ ] **Step 1: Write failing tests**

Create tests covering:

```text
1. low HP / many words: monster index 1 and 2 stay on choice until every word has choice coverage.
2. high HP / few words: after every word has choice coverage, the question stage advances to fill-letter while the same monster keeps its original L1 catalog assignment.
3. partial enabled types: only fill-letter and spell are emitted, in that order.
4. unsupported words: stage coverage skips words that cannot serve that type.
5. empty stage: a question type with no supported words is skipped and gets no monster stage.
6. old monster spans multiple stages: if an L1 monster survives through QT1 and QT2 and dies during QT3, the next monster uses the L3 catalog pool.
7. final stage sustain: after all stages complete, new monsters stay on the last supported stage.
8. catalog index for each stage comes from the expected MonsterLevel pool.
```

Use public methods:

```typescript
const scheduler = new BattleStageScheduler(wordIds, enabledTypes, canServe, rng);
const pick = scheduler.pickNext(monsterIndex, lastWordId);
scheduler.markServed(pick.wordId, pick.kind);
const catalog = scheduler.catalogIndexForMonster(monsterIndex);
```

- [ ] **Step 2: Run tests red**

Run: `cd harmonyos && hvigorw -p module=entry@default test --tests BattleStageScheduler`

Expected: compile failure because `BattleStageScheduler` does not exist.

- [ ] **Step 3: Implement scheduler**

Implement:

```typescript
export class BattleStagePick {
  kind: string = '';
  wordId: string = '';
}

export class BattleStageScheduler {
  constructor(wordIds: string[], enabledTypes: string[], canServe: StageSupportFn, rng?: RandomFn)
  pickNext(monsterIndex: number, lastWordId?: string): BattleStagePick
  markServed(wordId: string, kind: string): void
  catalogIndexForMonster(monsterIndex: number): number
  activeKindForTest(): string
}
```

Build stages from sanitized question types in difficulty order. Each stage stores only unique word ids that `canServe(wordId, kind)` returns true for. Skip empty stages. Advance to the next stage immediately when `markServed` completes current-stage coverage. Detect monster changes in `pickNext` only to bind a newly seen monster index to the currently active stage; do not let monster death advance the question stage. If already at the final stage, stay there. Pick catalog indices from `monsterCatalogIndicesForLevel(stageLevel(kind))` using RNG.

- [ ] **Step 4: Run tests green**

Run: `cd harmonyos && hvigorw -p module=entry@default test --tests BattleStageScheduler`

Expected: `BUILD SUCCESSFUL`.

### Task 3: Route PlanQuestionSource Through BattleStageScheduler

**Files:**
- Modify: `harmonyos/entry/src/main/ets/services/PlanQuestionSource.ets`
- Modify: `harmonyos/entry/src/test/PlanQuestionSource.test.ets`

- [ ] **Step 1: Write failing integration test**

Add a test where enabled types are `[choice, fill-letter]`, three words exist, monster changes from `1` to `2` before choice coverage is complete, and `PlanQuestionSource` still emits `choice` for the remaining word rather than `fill-letter`.

- [ ] **Step 2: Run test red**

Run: `cd harmonyos && hvigorw -p module=entry@default test --tests PlanQuestionSource`

Expected: The new test fails under the old scheduler behavior.

- [ ] **Step 3: Update PlanQuestionSource constructor support**

Allow `PlanQuestionSource` to receive either the old `BattleQuestionScheduler` or a new `BattleStageScheduler`. When a stage scheduler is present:

```typescript
const pick = this.stageScheduler.pickNext(this.monsterIndexProvider(), lastWordId);
primaryType = pick.kind;
preferredWordId = pick.wordId;
phasePool = [primaryType];
...
this.stageScheduler.markServed(word.id, exact.kind);
```

Do not degrade to lower question types for stage picks; skip unsupported words at scheduler construction instead.

- [ ] **Step 4: Run PlanQuestionSource tests green**

Run: `cd harmonyos && hvigorw -p module=entry@default test --tests PlanQuestionSource`

Expected: `BUILD SUCCESSFUL`.

### Task 4: Wire BattlePage and TodayAdventureBuilder to Stage Scheduler

**Files:**
- Modify: `harmonyos/entry/src/main/ets/pages/BattlePage.ets`
- Modify: `harmonyos/entry/src/main/ets/services/TodayAdventureBuilder.ets`
- Modify: `harmonyos/entry/src/test/TodayAdventureBuilder.test.ets`

- [ ] **Step 1: Write failing TodayAdventureBuilder test**

Assert selected question types no longer pre-build a cycling monster plan that advances by monster slot. The plan may keep `monsterSlots` for preview/fallback, but runtime catalog choice must come from `BattleStageScheduler`.

- [ ] **Step 2: Implement BattlePage wiring**

In today mode, construct `BattleStageScheduler(planWordIds, cfg.enabledQuestionTypes, canServe)` from the same `bundleRepo` that powers `PlanQuestionSource`. Pass it into `PlanQuestionSource`. In `catalogIndexProvider`, prefer `stageScheduler.catalogIndexForMonster(engine.getState().monsterIndex)` over `todayPlan.monsterSlots`.

- [ ] **Step 3: Keep TodayAdventureBuilder preview conservative**

Leave `monsterSlots` as a preview/fallback artifact, but do not rely on it for runtime stage progression. Keep tests that validate 10 slots for preview/default config.

- [ ] **Step 4: Run tests**

Run:

```bash
cd harmonyos && hvigorw -p module=entry@default test --tests BattleStageScheduler --tests PlanQuestionSource --tests TodayAdventureBuilder
```

Expected: `BUILD SUCCESSFUL`.

### Task 5: Update Dialogue Presentation Rules

**Files:**
- Modify: `harmonyos/entry/src/main/ets/pages/BattlePage.ets`
- Modify: `harmonyos/entry/src/ohosTest/ets/test/BattleFlow.ui.test.ets`

- [ ] **Step 1: Write failing UI/unit-level assertions where possible**

Update `superBossIntroUsesBannerAndAutoDismisses` to expect the ordinary intro bubble id and not the Super banner id. Add coverage that repeated catalog identity suppresses intro/defeat if existing UI test seams allow it.

- [ ] **Step 2: Implement presentation**

Remove Super-specific blocking from answer guards. `showIntroForCurrentMonster` should:

```text
if catalogIndex already seen in this battle: do not show intro
else show ordinary intro bubble and remember catalogIndex
```

`showDefeatForMonster` should show only if the catalog identity has not already shown defeat in this battle.

- [ ] **Step 3: Run BattleFlow**

Run: `scripts/run_ui_tests.sh --suite BattleFlow --rebuild`

Expected: 4 tests pass.

### Task 6: Full Verification and Commit

**Files:**
- All changed files

- [ ] **Step 1: Full unit tests**

Run: `cd harmonyos && hvigorw -p module=entry@default test`

Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 2: HAP build**

Run: `cd harmonyos && hvigorw assembleHap`

Expected: `BUILD SUCCESSFUL`, with no `ArkTS:WARN` lines.

- [ ] **Step 3: CodeLinter**

Run: `cd harmonyos && codelinter -c ./code-linter.json5 . --fix`

Expected: `No defects found in your code.`

- [ ] **Step 4: Diff hygiene**

Run: `git diff --check`

Expected: no output.

- [ ] **Step 5: Commit**

```bash
git add docs/features/2026-05-25-boss-dialogue-v0-9-2/60-followups.md docs/superpowers/plans/2026-05-25-battle-stage-scheduler.md harmonyos/entry/src/main/ets harmonyos/entry/src/test harmonyos/entry/src/ohosTest/ets/test
git commit -m "feat(harmony): stage battle questions by difficulty"
```
