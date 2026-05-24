# V0.8.6 — 怪物等级积分金币 — Replication Trigger

> Inputs (frozen): [`00-design.md`](00-design.md), [`10-harmony-plan.md`](10-harmony-plan.md)
>
> This document is the single gate that controls when iOS / Android replication may begin. iOS and Android agents must verify the signature block at the bottom is filled in before starting any work in `30-ios-plan.md` / `40-android-plan.md`.

## 1. Soft Gate (machine-checkable)

Paste evidence (paths to logs, commit SHAs, screenshot folders) next to each item before checking it.

- [x] **No-device unit tests green** — `cd harmonyos && hvigorw -p module=entry@default test`
  - Evidence: 2026-05-23 local run, `BUILD SUCCESSFUL in 4 s 568 ms`. Pre-flight required `cd harmonyos && ohpm install` to restore `oh_modules/@ohos/hypium`.
- [x] **ohosTest UI tests green** — `scripts/run_ui_tests.sh`
  - Evidence: User confirmed Harmony acceptance testing passed on 2026-05-24; earlier local no-device unit tests and HAP build were green.
- [x] **0 `ArkTS:WARN` lines in HAP build** — `cd harmonyos && hvigorw assembleHap`
  - Evidence: 2026-05-23 local run, `BUILD SUCCESSFUL in 2 s 131 ms`; no `ArkTS:WARN` lines observed. Output included a Java `sun.misc.Unsafe` warning from the packaging tool, not an ArkTS compiler warning.
- [x] **CodeLinter clean** — `cd harmonyos && codelinter -c ./code-linter.json5 . --fix`
  - Evidence: 2026-05-23 local run, exit 0, `No defects found in your code.`
- [x] **Version bumped** — `harmonyos/AppScope/app.json5`
  - From: `versionName=0.8.4` `versionCode=1008004`
  - To: `versionName=0.8.6` `versionCode=1008006`
- [ ] **Feature merged to main**
  - Commit: Pending HarmonyOS implementation.
- [x] **Screenshots refreshed** — for every screen this feature visibly changed
  - Files updated under `assets/screenshots/harmonyos/`: No source screenshot files changed in this worktree; user confirmed Harmony acceptance testing passed on 2026-05-24.
- [x] **Server contracts up to date** — not required; this is a client-only reward-rule change.
  - Regenerated: N/A
  - Tests: N/A
  - Fixture diffs: N/A

## 2. Delta Letter

Filled after HarmonyOS stabilization. iOS and Android agents must not start until §4 is signed.

### 2.1 New / changed code

| Layer | HarmonyOS files |
| --- | --- |
| Models | `models/BattleState.ets` adds `defeatedMonsterLevelScore`; `models/SessionResult.ets` adds `monsterLevelScore` and keeps `coinsBaseFromStars` only as a router/display compatibility baseline. |
| Services | `services/BattleRewardCalc.ets` replaces star/Bonus reward helpers with `coinValueForMonsterLevel`, `computeMonsterLevelCoinAward`, and `computeRetiredBonusCoinDelta`; `services/BattleEngine.ets` records monster-level score at kill time. |
| Pages | `pages/BattlePage.ets` awards `result.monsterLevelScore` through the existing coin account; `pages/ResultPage.ets` merges `monsterLevelScore` and removes the retired Bonus extra coin row. |
| Tests | `BattleRewardCalc.test.ets` covers level values and retired Bonus delta; `LocalUnit.test.ets` covers kill-time score accumulation and partial-loss reward score. |

### 2.2 Persistence keys (cross-platform; replicas must match semantics)

No new persistence keys.

| Key | Type | Default | Migration notes |
| --- | --- | --- | --- |
| Existing coin ledger | Platform-local wallet model | Existing default | Existing balances remain unchanged; future battle rewards use monster-level score. |

### 2.3 Stable IDs introduced or changed

No new stable IDs are planned.

| ID | Where | Notes |
| --- | --- | --- |
| Existing result/home coin labels | Result and Home screens | Continue to assert displayed earned coins / balance. |

### 2.4 Edge cases discovered during stabilization

- `ohpm install` may be required in fresh worktrees before local unit tests, otherwise `@ohos/hypium` fails to resolve.

### 2.5 Tests requiring parity counterparts

| HarmonyOS test | iOS counterpart (XCTest / XCUITest) | Android counterpart (JUnit / Compose UI / UIA) |
| --- | --- | --- |
| `BattleRewardCalc.test.ets::mapsMonsterLevelsToCoinValues` | Add `BattleRewardCalcTests.testMapsMonsterLevelsToCoinValues` | Add `BattleRewardCalcTest.mapsMonsterLevelsToCoinValues` |
| `BattleRewardCalc.test.ets::usesMonsterLevelScoreAsTheFinalAward` | Add `BattleRewardCalcTests.testUsesMonsterLevelScoreAsFinalAward` | Add `BattleRewardCalcTest.usesMonsterLevelScoreAsFinalAward` |
| `BattleRewardCalc.test.ets::retiredBonusMultiplierNeverAddsCoins` | Add `BattleRewardCalcTests.testRetiredBonusMultiplierNeverAddsCoins` | Add `BattleRewardCalcTest.retiredBonusMultiplierNeverAddsCoins` |
| `LocalUnit.test.ets::recordsMonsterLevelScoreAtKillTime` | Add `BattleEngineTests.testRecordsMonsterLevelScoreAtKillTime` | Add `BattleEngineTest.recordsMonsterLevelScoreAtKillTime` |
| `LocalUnit.test.ets::partialLossKeepsOnlyDefeatedMonsterLevelScore` | Add `BattleEngineTests.testPartialLossKeepsOnlyDefeatedMonsterLevelScore` | Add `BattleEngineTest.partialLossKeepsOnlyDefeatedMonsterLevelScore` |

### 2.6 Pitfalls / "do not repeat my mistakes"

- Do not recalculate reward from `defeatedMonsters`; use the level recorded at kill time so TodayPlan catalog slots stay authoritative.
- Bonus monster count remains, but `BattleResultBonusCoinRow` is intentionally retired because Bonus no longer adds coins.

## 3. Open Questions for the Replicas

No open questions. The written design states that monster-level score completely replaces star and Bonus coin formulas.

## 4. Human-Confirm Signature Block

> **iOS / Android agents:** if `replication_approved` is missing, blank, or `false`, refuse to start Stage 4 and ask the human owner. Do not proceed.

```yaml
approved_by: matianyi
approved_at: 2026-05-24
replication_approved: true
notes: Harmony acceptance testing passed; proceed with iOS and Android replication of the fully replacing coin reward rule.
```
