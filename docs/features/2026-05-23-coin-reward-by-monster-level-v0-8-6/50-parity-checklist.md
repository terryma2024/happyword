# V0.8.6 — 怪物等级积分金币 — Parity Checklist

> Inputs (frozen): [`00-design.md`](00-design.md), [`20-replication-trigger.md`](20-replication-trigger.md)
>
> The feature is **Done** only when every row below is `[x]` in all three platform columns. A row that goes red after Done reopens the feature via [`60-followups.md`](60-followups.md); do not silently fix-and-close.

## 1. User flows

| Flow | Harmony | iOS | Android | Notes |
| --- | --- | --- | --- | --- |
| Battle settlement awards coins from defeated monster levels | [x] | [x] | [x] | Pure tests cover 1 + 2 + 3 + 4 = 10; product example remains 2 level-1 + 2 level-2 + 1 level-3 = 9 coins before daily cap. |
| Loss after partial progress awards only killed monster score | [x] | [x] | [x] | Pure tests cover one Advanced kill -> 3 coins on loss. |
| Bonus monster kill does not add extra coins | [x] | [x] | [x] | Retired Bonus delta = 0; Bonus count remains for telemetry / battle state, but extra-coin result rows are removed. |

## 2. Stable IDs

No new stable IDs.

| ID | Harmony | iOS | Android | Notes |
| --- | --- | --- | --- | --- |
| Existing result/home coin labels | [x] | [x] | [x] | Harmony and iOS keep existing result/home coin labels; Android keeps the existing result coin stat. |

## 3. Pure-rule tests

| HarmonyOS test | iOS counterpart | Android counterpart |
| --- | --- | --- |
| `BattleRewardCalc.test.ets::mapsMonsterLevelsToCoinValues` | [x] | [x] |
| `BattleRewardCalc.test.ets::usesMonsterLevelScoreAsTheFinalAward` | [x] | [x] |
| `BattleRewardCalc.test.ets::retiredBonusMultiplierNeverAddsCoins` | [x] | [x] |
| `LocalUnit.test.ets::recordsMonsterLevelScoreAtKillTime` | [x] | [x] |
| `LocalUnit.test.ets::partialLossKeepsOnlyDefeatedMonsterLevelScore` | [x] | [x] |

## 4. Contract usage

No shared contract or fixture changes.

| Contract / fixture | Harmony | iOS | Android |
| --- | --- | --- | --- |
| N/A | [x] | [x] | [x] |

## 5. Screenshots

Owner explicitly skipped screenshot artifact refresh on 2026-05-24 after simulator acceptance.

| Screen | `assets/screenshots/harmonyos/...` | `assets/screenshots/ios/...` | `assets/screenshots/android/...` |
| --- | --- | --- | --- |
| Result screen coin reward | N/A | N/A | N/A |
| Home screen coin balance | N/A | N/A | N/A |

## 6. Versions

| Platform | Field | Value |
| --- | --- | --- |
| HarmonyOS | `harmonyos/AppScope/app.json5` `versionName` / `versionCode` | `0.8.6` / `1008006` |
| iOS | `CFBundleShortVersionString` / `CFBundleVersion` | `0.8.6` / `1008006` |
| Android | `android/app/build.gradle.kts` `versionName` / `versionCode` | `0.8.6` / `1008006` |

## 7. Sign-off

- [x] Owner verified the implemented rows above are green.
- [x] Owner ran simulator acceptance after the iOS and Android builds were installed and launched on 2026-05-24.
- [x] Feature linked from [`docs/features/README.md`](../../features/README.md) is marked `Done`.

```yaml
done_by: matianyi
done_at: 2026-05-24
notes: Simulator acceptance completed after installing the iOS and Android builds. Owner explicitly skipped screenshot artifact refresh.
```
