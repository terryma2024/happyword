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

### Fix (v1.1.1, Android-blueprint consolidation)

Two passes landed on 2026-06-13. The first (`dd106ab`) added the hook with an
inline per-answer block in `CocosBattlePage`; the second consolidated it onto
the Android fix design (commit `4a0bea8` on `cocos-battle-android`), which
extracts the native body into ONE shared function so the two frontends cannot
drift:

- `CocosBattleBridgeCallbacks.onAnswerOutcome(event)` (optional, default
  no-op) with a typed `CocosAnswerOutcomeEvent` payload `{answeredWordId,
  preMonsterCatalogIndex, postMonsterCatalogIndex, outcome}` — fired in
  `handleSubmit` exactly once per submit the engine processed (including
  fill-letter-medium step advances, Android bridge-contract parity), never
  for hold-dropped duplicates, post-end submits, after dispose, or
  `spellWrongTap`. The wordId and pre-answer catalog index are captured
  BEFORE `engine.submitAnswer` because `getState()` returns the live state.
- New `services/BattleAnswerRecorder.ets` — the native BattlePage per-answer
  body moved statement-for-statement (`recordAnswer` +
  `markDailyReviewWordIfNeeded`, `recordEncounter` with the page's old
  dedup, `recordMonsterDefeat`). `applyAnswerOutcome(event)` runs the full
  Cocos-path body and skips learning stats on `advancedStep` — exactly the
  native page's "Do not record learning stats" early return.
- `BattlePage` delegates to the same service (extraction-only, zero behavior
  change); `CocosBattlePage` wires `applyAnswerOutcome` into the bridge
  callback and records the opening monster's encounter at session setup
  (BattlePage first-`syncFromEngine` parity).
- Bridge unit tests (`CocosBattleBridge.test.ets`, 8 cases): fires once per
  accepted submit with pre-submit info, carries pre/post catalog indices
  across a defeat, fires on the final blow and on medium step advances, not
  for hold duplicates / post-end / dispose / spellWrongTap.

### Reopened parity rows (50-parity-checklist.md)

- "Escape → ResultPage enriched stats" — previously marked verified, but
  学习单词 / newly-learned totals were stale on the Cocos path.
- "Monster defeat → next monster transition" — visual transition was
  verified, but codex defeat/encounter recording was missing.

Re-verified via bridge unit tests + build gates (assembleHap, 0 `ArkTS:WARN`,
codelinter) **and live on the arm64 emulator** (`127.0.0.1:5555`, v1.1.0
debug HAP build 2606130951, 2026-06-13):

- Before the battle, `/data/app/el2/100/base/com.terryma.wordmagicgame/haps/entry/preferences/`
  contained neither `wordmagic_learning` nor `wordmagic_monster_progress`.
- One correct answer (草莓 → strawberry) in the **Cocos** scene created
  `wordmagic_learning` with
  `{"wordId":"fruit-strawberry","seenCount":1,"correctCount":1,…,"nextReviewMs":…,"memoryState":"learning"}`
  — word stats + review scheduling now persist from the Cocos path.
- Escape → ResultPage showed 答题数 1/1, 正确率 100%, 学习单词 2 (non-zero —
  the stale-counter symptom is gone), and the settlement flush wrote
  `wordmagic_monster_progress` with
  `{"catalogIndex":15,"encountered":true,…}` (Pebble Golem, the monster on
  screen) — codex encounter recording works end to end.

### Cross-platform note

iOS was already correct (design source of truth). Android fixed the same gap
on `cocos-battle-android` (commit `4a0bea8`, `applyAnswerSideEffects` shared
by the native screen and both Cocos route sites) — the HarmonyOS
consolidation above mirrors that design; this entry covers HarmonyOS only.
