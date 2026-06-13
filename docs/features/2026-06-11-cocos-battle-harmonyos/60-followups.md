# Follow-ups — Cocos battle on HarmonyOS

Post-replication parity fixes per SOP §"Bugfixes that change shared semantics".

## FU-1 — Cocos battles record no per-answer side effects (data loss)

- **Date:** 2026-06-13
- **Found by:** Android Cocos-battle code review (V1.1.0 parity, Task 1.4); same gap confirmed on HarmonyOS.
- **Severity:** High — silent data loss whenever the Cocos switch is ON (the default).

### Symptom

On HarmonyOS, battles played in the Cocos scene record **no** per-answer side
effects, while the native BattlePage and the iOS Cocos path both do:

- `LearningRecorder.recordAnswer` never runs → word memory state never
  updates, review scheduling and the learning report degrade, and ResultPage's
  newly-learned counter reads 0 (the enricher reads recorder totals that
  stayed stale).
- Daily review battles never call `markReviewedWords` → the review plan never
  completes.
- `MonsterProgressStore.recordEncounter` / `recordDefeat` never run → codex
  encounter/defeat progress (and milestone coin rewards) are lost.

### Root cause

`CocosBattleBridge.handleSubmit` called `engine.submitAnswer` directly;
`CocosBattleBridgeCallbacks` had no per-answer hook, and `CocosBattlePage`
never ran the BattlePage per-answer block (`onOptionTap` /
`handleSpellSubmit` lines ~1003/~1254). Settlement only ran
`enrichAndFlushSessionResult`, which reads recorder totals.

### Fix (mirrors iOS `AppCoordinator.submitBattleOptionForAnimation`)

- `CocosBattleBridgeCallbacks.onAnswerOutcome(answeredWordId,
  preAnswerCatalogIndex, outcome)` — fired in `handleSubmit` right after
  `engine.submitAnswer`, for non-`advancedStep` outcomes only, exactly once
  per accepted submit, never after finish/dispose. Scalars are captured
  before submit because `engine.getState()` returns the live state object.
- `CocosBattlePage` implements the BattlePage-identical block:
  `recorder.recordAnswer`, `markDailyReviewWordIfNeeded` (review mode),
  `monsterProgress.recordDefeat(preAnswerCatalogIndex)` on
  `outcome.monsterDefeated`, `recordEncounter` on `outcome.newMonsterSpawned`
  (post-answer catalog index) plus the initial monster at session setup.
- Bridge unit tests extended (`CocosBattleBridge.test.ets`): fires exactly
  once per accepted submit (correct / wrong / defeat / battle-end), skips
  medium step advances and spell wrong taps, dropped duplicate submits during
  the feedback hold, and anything after dispose.

### Reopened parity rows (50-parity-checklist.md)

- "Escape → ResultPage enriched stats" — previously marked verified, but
  学习单词 / newly-learned totals were stale on the Cocos path.
- "Monster defeat → next monster transition" — visual transition was
  verified, but codex defeat/encounter recording was missing.

Re-verified via bridge unit tests + build gates (assembleHap, 0 `ArkTS:WARN`,
codelinter). On-device re-check of ResultPage 学习单词 counter and codex
progress recommended at the next device session.

### Cross-platform note

iOS was already correct (design source of truth). The same gap exists on the
Android branch `cocos-battle-android` (flagged in its Task 1.4 review) and is
being fixed there; this entry covers HarmonyOS only.
