# V0.8.8 — Daily Check-in Rewards — HarmonyOS + Server Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Inputs (frozen):**
> - Design: [`00-design.md`](00-design.md)
>
> **Run loop:** [`.cursor/skills/harmony-autofix-orchestrator/SKILL.md`](../../../.cursor/skills/harmony-autofix-orchestrator/SKILL.md) drives Harmony build/test. Commands come from [`.cursor/ohos-dev-commands.md`](../../../.cursor/ohos-dev-commands.md). Do not invent flags.

**Goal:** Add local-first daily check-ins, seven-day +50 coin rewards, check-in calendar UI, and bound-device cloud sync for V0.8.8.

**Architecture:** Server adds an idempotent child-device check-in sync contract parallel to word-stat sync. HarmonyOS adds `CheckInStore`, `CloudCheckInService`, and `CheckInPage`, then wires BattlePage victory rewards and a TodayPlanPage entry. Roadmap and feature lifecycle docs are updated at the end.

**Tech Stack:** Python / FastAPI / Beanie / pytest; HarmonyOS NEXT, ArkTS, ArkUI, Hypium local tests, ohosTest UI automation.

---

### Task 1: Server check-in contract

**Files:**
- Create: `server/app/models/child_checkin.py`
- Create: `server/app/models/cloud_coin_txn.py`
- Create: `server/app/schemas/checkins.py`
- Create: `server/app/services/checkin_sync_service.py`
- Create: `server/app/routers/child_checkins.py`
- Modify: `server/app/main.py`
- Modify: `server/tests/conftest.py`
- Test: `server/tests/test_child_checkins.py`

- [ ] Write failing tests for bound-device sync:
  - unbound requests return auth errors through existing deps;
  - first sync inserts days and coin txns;
  - duplicate sync is idempotent;
  - sibling sync returns merged cloud rows.
- [ ] Run `cd server && uv run pytest tests/test_child_checkins.py -q`; expected: fails because router/model do not exist.
- [ ] Add Beanie models for `(child_profile_id, day_key)` check-ins and `(child_profile_id, txn_id)` coin txns.
- [ ] Add schemas with strict `extra="forbid"` and day key validation by regex.
- [ ] Add service functions `sync(...)` and `list_all(...)` using set-union semantics.
- [ ] Add router under `/api/v1/family/{family_id}/checkins`.
- [ ] Register models and router in `server/app/main.py` and tests.
- [ ] Re-run `cd server && uv run pytest tests/test_child_checkins.py -q`; expected: pass.

### Task 2: Shared contract and fixture

**Files:**
- Modify: `shared/contracts/protocols/word-stats-sync.md` or create sibling protocol doc.
- Create: `shared/contracts/protocols/checkins-sync.md`
- Create: `shared/fixtures/child/checkins-sync.sample.json`
- Modify: `shared/contracts/openapi/*`
- Test: `server/tests/test_shared_contracts.py`

- [ ] Write the protocol doc from `00-design.md` §8.
- [ ] Add sample fixture with two checked days, one weekly bonus day, one `+50` txn, and merged response.
- [ ] Run `cd server && uv run python ../tools/contracts/export_openapi.py`.
- [ ] Run `cd server && uv run pytest tests/test_shared_contracts.py -q`; expected: pass.

### Task 3: Harmony pure check-in store

**Files:**
- Create: `harmonyos/entry/src/main/ets/models/CheckInSnapshot.ets`
- Create: `harmonyos/entry/src/main/ets/services/CheckInStore.ets`
- Test: `harmonyos/entry/src/test/CheckInStore.test.ets`

- [ ] Write failing Hypium tests for:
  - first win records the day;
  - same-day repeat is idempotent;
  - seventh contiguous day returns `bonusCoins = 50`;
  - missed day resets current streak but preserves best streak;
  - cloud merge unions days and does not duplicate bonus day keys.
- [ ] Run `cd harmonyos && hvigorw -p module=entry@default test --tests CheckInStore`; expected: fails because store does not exist.
- [ ] Implement `CheckInSnapshot`, `CheckInRecordResult`, parse/serialize helpers, and `CheckInStore.recordWin(nowMs)`.
- [ ] Re-run the focused Harmony test; expected: pass.

### Task 4: Harmony coin transaction support

**Files:**
- Modify: `harmonyos/entry/src/main/ets/models/CoinSnapshot.ets`
- Modify: `harmonyos/entry/src/main/ets/services/CoinAccount.ets`
- Test: `harmonyos/entry/src/test/CoinAccount.test.ets`

- [ ] Write failing tests for deterministic `txnId` on weekly bonus and idempotent external transaction application.
- [ ] Run focused coin tests; expected: fail.
- [ ] Add `txnId` to `CoinTxn`, preserve old snapshots by deriving empty txn IDs, and add `applyExternalTxn(txnId, delta, reason, ts)`.
- [ ] Ensure existing `earn` / `redeem` behavior is unchanged.
- [ ] Re-run focused coin tests; expected: pass.

### Task 5: Harmony cloud check-in service

**Files:**
- Create: `harmonyos/entry/src/main/ets/services/CloudCheckInService.ets`
- Modify: `harmonyos/entry/src/main/ets/entryability/EntryAbility.ets`
- Test: `harmonyos/entry/src/test/CloudCheckInService.test.ets`

- [ ] Write failing tests for:
  - unbound returns `unbound`;
  - bound POST sends local days and coin txns;
  - server merged response applies days and cloud coin txns;
  - network failure leaves pending sync.
- [ ] Run focused cloud check-in tests; expected: fail.
- [ ] Implement service using `CloudCredentials`, `ParentFetchAdapter`, and `effectiveServerBaseUrl`.
- [ ] Wire fire-and-forget install in `EntryAbility` like `CloudSyncService`.
- [ ] Re-run focused cloud check-in tests; expected: pass.

### Task 6: Battle result integration

**Files:**
- Modify: `harmonyos/entry/src/main/ets/models/SessionResult.ets`
- Modify: `harmonyos/entry/src/main/ets/pages/BattlePage.ets`
- Modify: `harmonyos/entry/src/main/ets/pages/ResultPage.ets`
- Test: `harmonyos/entry/src/test/CheckInStore.test.ets`

- [ ] Add result fields `checkInRecorded`, `checkInCurrentStreak`, `checkInBonusCoins`.
- [ ] In BattlePage victory today-mode path, call `CheckInStore.recordWin(now)` after normal coin awards.
- [ ] When `bonusCoins > 0`, add `+50` through `CoinAccount.applyExternalTxn` with reason `checkin-weekly-bonus:<dayKey>`.
- [ ] Show `ResultCheckInBonusRow` only when a new weekly bonus is awarded.
- [ ] Fire-and-forget cloud check-in sync after local flush if bound.

### Task 7: Calendar UI and TodayPlan entry

**Files:**
- Create: `harmonyos/entry/src/main/ets/pages/CheckInPage.ets`
- Modify: `harmonyos/entry/src/main/ets/pages/TodayPlanPage.ets`
- Modify: `harmonyos/entry/src/main/resources/base/profile/main_pages.json`
- Test: `harmonyos/entry/src/ohosTest/ets/test/CheckInFlow.ui.test.ets`

- [ ] Add `TodayPlanCheckInButton` to the left of `TodayPlanReportButton`.
- [ ] Add `CheckInPage` with stable IDs from `00-design.md` §5.
- [ ] Add previous / next month controls and a visible month label.
- [ ] Render current month cells; checked cells use `CheckInDay_<YYYY-MM-DD>`.
- [ ] Add ohosTest for opening the page and seeing title/streak/grid.

### Task 8: Version, roadmap, and lifecycle docs

**Files:**
- Modify: `harmonyos/AppScope/app.json5`
- Modify: `docs/features/README.md`
- Modify: `docs/WordMagicGame_roadmap.md`
- Modify: `docs/features/2026-05-23-daily-checkin-v0-8-8/20-replication-trigger.md`
- Modify: `docs/features/2026-05-23-daily-checkin-v0-8-8/50-parity-checklist.md`

- [ ] Bump HarmonyOS to `0.8.8` / `1008008`.
- [ ] Update feature index status to Stage 3 after Harmony implementation.
- [ ] Update roadmap with V0.8.8 daily check-in status and contract summary.
- [ ] Fill soft-gate evidence as verification commands complete.
- [ ] Leave human signature as `replication_approved: false` until owner signs.

### Task 9: Verification

**Files:**
- Validate all touched server, HarmonyOS, shared contract, and docs changes.

- [ ] `cd server && uv run pytest tests/test_child_checkins.py tests/test_shared_contracts.py -q` green.
- [ ] `cd server && uv run pytest` green with 0 warnings.
- [ ] `cd harmonyos && hvigorw -p module=entry@default test` green.
- [ ] `cd harmonyos && hvigorw assembleHap` produces 0 `ArkTS:WARN` lines.
- [ ] `cd harmonyos && codelinter -c ./code-linter.json5 . --fix` clean.
- [ ] Run or document why ohosTest / screenshot capture could not be completed in this environment.
