# V0.8.4 — Battle Balance & Question Pacing — Android Replication Plan

> **Inputs (frozen):** [`00-design.md`](00-design.md), [`20-replication-trigger.md`](20-replication-trigger.md) (`replication_approved: true`)
>
> **Run loop:** [`.cursor/android-dev-commands.md`](../../../.cursor/android-dev-commands.md)

**Goal:** Match Harmony V0.8.4 — default HP 10, Spell wrong-tap −1 HP, scheduler-driven question mix.

---

### Pre-flight

- [x] `replication_approved: true` in [`20-replication-trigger.md`](20-replication-trigger.md)

### Task 1: Domain

**Files:** `BattleQuestionScheduler.kt`, `BattleQuestionTypePolicy.kt`, `BattleEngine.kt`, `Models.kt`

- [x] Scheduler + policy helpers
- [x] `BattleEngine.nextScheduledQuestion` + `applySpellLetterPenalty` / `spellLetterPenaltyOutcome`
- [x] `GameConfig.playerHp` default **10**
- [x] `BattleQuestionSchedulerTest.kt`

### Task 2: Compose UI

**Files:** `BattleUi.kt` (`SpellAnswerArea`, `BattleScreen`), `WordMagicGameApp.kt`

- [x] Wrong spell pool tap → `onSpellWrongTap` → engine penalty
- [x] Tags unchanged (`BattleSpellArea`, `BattleSpellPool_*`)

### Task 3: UI tests

- [x] Optional Compose/UI Automator smokes explicitly deferred; not a V0.8.4 core parity blocker. Unit/domain parity plus stable runtime tags cover this pass.

### Task 4: Version

**Files:** `android/app/build.gradle.kts`

- [x] `versionName` `0.8.4`, `versionCode` `1008004`

### Task 5: Verification

- [x] `./gradlew testDebugUnitTest --tests BattleQuestionSchedulerTest`
- [x] Targeted V0.8.3 parity/core suite: `./gradlew testDebugUnitTest --tests 'cool.happyword.wordmagic.core.PackSelectionStoreTest' --tests 'cool.happyword.wordmagic.core.GrowthStoresTest' --tests 'cool.happyword.wordmagic.core.BattleEngineTest'`
- [ ] `./gradlew testDebugUnitTest` (full suite not rerun during 2026-05-23 roadmap hygiene)
- [ ] `./gradlew assembleDebug` (not rerun during 2026-05-23 roadmap hygiene)
- [x] Update [`50-parity-checklist.md`](50-parity-checklist.md)
