# V0.8.8 — Daily Check-in Rewards — Replication Trigger

> Inputs (frozen): [`00-design.md`](00-design.md), [`10-harmony-plan.md`](10-harmony-plan.md)
>
> This document is the single gate that controls when iOS / Android replication may begin. iOS and Android agents must verify the signature block at the bottom is filled in before starting any work in `30-ios-plan.md` / `40-android-plan.md`.

## 1. Soft Gate (machine-checkable)

- [x] **No-device unit tests green** — `cd harmonyos && hvigorw -p module=entry@default test`
  - Evidence: 2026-05-24 `BUILD SUCCESSFUL in 3 s 983 ms`.
- [x] **ohosTest UI tests green** — `scripts/run_ui_tests.sh`
  - Evidence: Human simulator verification by matianyi on 2026-05-24 accepted the HarmonyOS flow after install.
- [x] **0 `ArkTS:WARN` lines in HAP build** — `cd harmonyos && hvigorw assembleHap`
  - Evidence: 2026-05-24 `hvigorw assembleHap --no-daemon` `BUILD SUCCESSFUL in 7 s 39 ms`; no `ArkTS:WARN` lines in output.
- [x] **CodeLinter clean** — `cd harmonyos && codelinter -c ./code-linter.json5 . --fix`
  - Evidence: 2026-05-24 `No defects found in your code.`
- [x] **Version bumped** — `harmonyos/AppScope/app.json5`
  - From: `versionName=0.8.4` `versionCode=1008004`
  - To: `versionName=0.8.8` `versionCode=1008008`
- [ ] **Feature merged to main**
  - Commit:
- [ ] **Screenshots refreshed** — for every screen this feature visibly changed
  - Files updated under `assets/screenshots/harmonyos/`:
- [x] **Server contracts up to date**
  - Regenerated: `shared/contracts/openapi/happyword-api.openapi.json`, `.paths.txt`, `.sha256`
  - Tests: `cd server && uv run pytest` passed `556 passed, 64 skipped in 75.24s`.
  - Fixture diffs: `shared/contracts/protocols/checkins-sync.md`, `shared/fixtures/child/checkins-sync.sample.json`

## 2. Delta Letter

### 2.1 New / changed code

| Layer | HarmonyOS / server files |
| --- | --- |
| Server models | `server/app/models/child_checkin.py`, `server/app/models/cloud_coin_txn.py` |
| Server schemas/services/routers | `server/app/schemas/checkins.py`, `server/app/services/checkin_sync_service.py`, `server/app/routers/child_checkins.py` |
| Harmony models | `harmonyos/entry/src/main/ets/models/CheckInSnapshot.ets`, `SessionResult.ets`, `CoinSnapshot.ets` |
| Harmony services | `CheckInStore.ets`, `CloudCheckInService.ets`, `CoinAccount.ets` |
| Harmony pages | `TodayPlanPage.ets`, `ResultPage.ets`, `CheckInPage.ets` |
| Tests | `server/tests/test_child_checkins.py`, `harmonyos/entry/src/test/CheckInStore.test.ets`, `CloudCheckInService.test.ets`, `CheckInCalendarView.test.ets`, `CoinAccount.test.ets` |

### 2.2 Persistence keys (cross-platform; replicas must match semantics)

| Key | Type | Default | Migration notes |
| --- | --- | --- | --- |
| `wordmagic_checkins/snapshot_v1` | `CheckInSnapshot` JSON | empty | New key. |
| `wordmagic_coins/snapshot_v1` | `CoinSnapshot` JSON | existing wallet | Tolerates optional `txnId` on txns. |
| `wordmagic_checkin_sync/sync_checkpoint_ms` | string number | `0` | New key. |

### 2.3 Stable IDs introduced or changed

See [`00-design.md`](00-design.md) §5.

### 2.4 Edge cases discovered during stabilization

- ArkUI calendar rows must use month-sensitive keys. Row keys based only on `rowIndex` can update the month label while leaving day cells visually stale after previous/next taps.
- Check-in entry lives in `TodayPlanPage` to the left of `TodayPlanReportButton`, not on Home.

### 2.5 Tests requiring parity counterparts

| HarmonyOS test | iOS counterpart (XCTest / XCUITest) | Android counterpart (JUnit / Compose UI / UIA) |
| --- | --- | --- |
| `harmonyos/entry/src/test/CheckInStore.test.ets` | [ ] | [ ] |
| `harmonyos/entry/src/test/CloudCheckInService.test.ets` | [ ] | [ ] |
| `harmonyos/entry/src/test/CheckInCalendarView.test.ets` | [ ] | [ ] |

### 2.6 Pitfalls / "do not repeat my mistakes"

- Use explicit state for visible calendar rows and month-sensitive row keys on declarative UI lists; do not key month rows only by row index.

## 3. Open Questions for the Replicas

- [x] Trigger rule selected: winning any Today Adventure automatically checks in.

## 4. Human-Confirm Signature Block

> **iOS / Android agents:** if `replication_approved` is missing, blank, or `false`, refuse to start Stage 4 and ask the human owner. Do not proceed.

```yaml
approved_by: matianyi
approved_at: 2026-05-24
replication_approved: true
notes: HarmonyOS manual simulator verification accepted by owner; start iOS and Android replication from this delta letter.
```
