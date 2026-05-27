# V0.9.3 Learning Plan + Review — HarmonyOS Implementation Plan

> Inputs (frozen): [`00-design.md`](00-design.md)
>
> Implementation happened on branch `codex/v0-9-3-learning-plan-roadmap` in commit `3be4840`.

**Goal:** Implement the HarmonyOS source of truth for daily pack battles, stable daily review queues, home-page status labels, and review-battle tuning.

**Architecture:** Add `DailyLearningStateService` as the daily state and review-queue owner, backed by Preferences. Extend `WordStat` / `LearningRecorder` with latest-answer outcome so same-day exclusions and recent-wrong logic are deterministic. Wire `HomePage` and `BattlePage` to consume the service while preserving the existing pack and battle infrastructure.

**Tech Stack:** HarmonyOS NEXT, ArkTS, ArkUI, Hypium local tests.

---

### Task 1: Daily State Service

**Files:**
- Create: `harmonyos/entry/src/main/ets/services/DailyLearningStateService.ets`
- Test: `harmonyos/entry/src/test/DailyLearningStateService.test.ets`
- Modify: `harmonyos/entry/src/test/List.test.ets`

- [x] Add tests for compact day key, stable review queue generation, 50-word cap, A/B label matrix, review progress marking, and review monster count.
- [x] Confirm the new test failed before implementation because `DailyLearningStateService` and `WordStat.lastOutcome` did not exist.
- [x] Implement the daily state models, queue builder, status decision helper, persistence wrapper, and in-memory mutation helpers.

### Task 2: Learning Outcome Tracking

**Files:**
- Modify: `harmonyos/entry/src/main/ets/services/WrongAnswerStore.ets`
- Modify: `harmonyos/entry/src/main/ets/services/LearningRecorder.ets`

- [x] Add `lastOutcome` to `WordStat`.
- [x] Persist and migrate `lastOutcome`, inferring from streak counters for older snapshots.
- [x] Record `correct` / `wrong` on each answer.

### Task 3: Home + Battle Wiring

**Files:**
- Modify: `harmonyos/entry/src/main/ets/pages/HomePage.ets`
- Modify: `harmonyos/entry/src/main/ets/pages/BattlePage.ets`

- [x] Home generates/loads the stable daily review snapshot from active pack words and recorder stats.
- [x] Home status label follows the A/B matrix from `00-design.md`.
- [x] Review button uses remaining daily review count instead of all-time recent-wrong count.
- [x] Battle review mode consumes remaining daily review words, marks reviewed ids, and uses a 10-minute timer.
- [x] Today pack battle wins mark daily pack completion when the player wins.
- [x] Review battle monster count scales from remaining review words and configured monster HP.

### Task 4: Verification

- [ ] `cd harmonyos && hvigorw -p module=entry@default test` green.
  - Current evidence: command reached ArkTS test compilation but failed because `@ohos/hypium` could not be resolved for all tests in this worktree environment.
- [ ] `scripts/run_ui_tests.sh` green.
  - Current evidence: not run in this turn.
- [x] `cd harmonyos && hvigorw assembleHap` produces 0 `ArkTS:WARN` lines.
  - Current evidence: `hvigorw assembleHap` succeeded on 2026-05-26 and `CompileArkTS` emitted no `ArkTS:WARN`.
- [ ] `cd harmonyos && codelinter -c ./code-linter.json5 . --fix` clean.
  - Current evidence: not run in this turn.
- [x] Bump [`harmonyos/AppScope/app.json5`](../../../harmonyos/AppScope/app.json5) to `versionName=0.9.3`, `versionCode=1009003`.
- [ ] Refresh affected screens via `python3 scripts/capture_harmony_screenshots.py`.
  - Current evidence: not run in this turn.
- [x] Server contracts unchanged.

Move on to [`20-replication-trigger.md`](20-replication-trigger.md) for the signed replication gate and delta letter.
