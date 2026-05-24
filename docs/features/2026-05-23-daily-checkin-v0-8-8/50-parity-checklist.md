# V0.8.8 — Daily Check-in Rewards — Parity Checklist

> Inputs (frozen): [`00-design.md`](00-design.md), [`20-replication-trigger.md`](20-replication-trigger.md)
>
> The feature is **Done** only when every row below is `[x]` in all three platform columns. A row that goes red after Done reopens the feature via [`60-followups.md`](60-followups.md).

## 1. User flows

| Flow | Harmony | iOS | Android | Notes |
| --- | --- | --- | --- | --- |
| Auto check-in after won Today Adventure | [x] | [x] | [x] | Harmony manually accepted 2026-05-24; iOS/Android implemented in battle finish paths. |
| Calendar review from Home | [x] | [x] | [x] | Entry lives in Today Plan, left of report entry, per delta letter. |
| Bound cloud sync / unbound local save | [x] | [x] | [x] | Cloud sync is best-effort when bound; local snapshot persists when unbound or offline. |

## 2. Stable IDs

| ID | Harmony | iOS | Android | Notes |
| --- | --- | --- | --- | --- |
| `TodayPlanCheckInButton` | [x] | [x] | [x] | |
| `CheckInPageTitle` | [x] | [x] | [x] | |
| `CheckInCurrentStreak` | [x] | [x] | [x] | |
| `CheckInBestStreak` | [x] | [x] | [x] | |
| `CheckInCloudState` | [x] | [x] | [x] | |
| `CheckInPrevMonthButton` | [x] | [x] | [x] | |
| `CheckInMonthLabel` | [x] | [x] | [x] | |
| `CheckInNextMonthButton` | [x] | [x] | [x] | |
| `CheckInCalendarGrid` | [x] | [x] | [x] | |
| `CheckInDay_<YYYY-MM-DD>` | [x] | [x] | [x] | Dynamic ID pattern. |
| `CheckInWeeklyBonusBanner` | [x] | [x] | [x] | |
| `ResultCheckInBonusRow` | [x] | [x] | [x] | |

## 3. Pure-rule tests

| HarmonyOS test | iOS counterpart | Android counterpart |
| --- | --- | --- |
| `harmonyos/entry/src/test/CheckInStore.test.ets` | [x] `LocalGrowthTests.testCheckInStoreAwardsWeeklyBonusOnceAfterSevenDayStreak` | [x] `GrowthStoresTest.checkInStoreAwardsWeeklyBonusOnceAfterSevenDayStreak` |
| `harmonyos/entry/src/test/CloudCheckInService.test.ets` | [x] `CloudSyncTests.testCheckInSyncPayloadMatchesContractShape` | [x] `CloudModelsTest.checkInSyncClientPostsCheckInsAndBonusTransactionsWithDeviceToken` |
| `harmonyos/entry/src/test/CoinAccount.test.ets` check-in transaction cases | [x] covered by `CoinAccount.creditCheckInWeeklyBonus` assertion in `LocalGrowthTests` | [x] covered by `CoinAccount.creditCheckInWeeklyBonus` assertion in `GrowthStoresTest` |

## 4. Contract usage

| Contract / fixture | Harmony | iOS | Android |
| --- | --- | --- |
| `shared/contracts/protocols/checkins-sync.md` | [x] | [x] | [x] |
| `shared/fixtures/child/checkins-sync.sample.json` | [x] | [x] | [x] |
| `shared/contracts/openapi/happyword-api.openapi.json` check-in paths | [x] | [x] | [x] |

## 5. Screenshots

| Screen | `assets/screenshots/harmonyos/...` | `assets/screenshots/ios/...` | `assets/screenshots/android/...` |
| --- | --- | --- | --- |
| Home streak entry | [ ] | [ ] | [ ] |
| Check-in calendar | [ ] | [ ] | [ ] |
| Result weekly bonus row | [ ] | [ ] | [ ] |

## 6. Versions

| Platform | Field | Value |
| --- | --- | --- |
| HarmonyOS | `harmonyos/AppScope/app.json5` `versionName` / `versionCode` | `0.8.8` / `1008008` |
| iOS | `CFBundleShortVersionString` / `CFBundleVersion` | `0.8.8` / `1008008` |
| Android | `android/app/build.gradle.kts` `versionName` / `versionCode` | `0.8.8` / `1008008` |

## 7. Sign-off

- [ ] Owner verified all rows above are green.
- [ ] Owner ran a smoke pass on at least one device per platform.
- [ ] Feature linked from [`docs/features/README.md`](../../features/README.md) is marked `Done`.

```yaml
done_by:
done_at:
notes:
```
