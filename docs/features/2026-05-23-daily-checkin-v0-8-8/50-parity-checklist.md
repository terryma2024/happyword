# V0.8.8 — Daily Check-in Rewards — Parity Checklist

> Inputs (frozen): [`00-design.md`](00-design.md), [`20-replication-trigger.md`](20-replication-trigger.md)
>
> The feature is **Done** only when every row below is `[x]` in all three platform columns. A row that goes red after Done reopens the feature via [`60-followups.md`](60-followups.md).

## 1. User flows

| Flow | Harmony | iOS | Android | Notes |
| --- | --- | --- | --- | --- |
| Auto check-in after won Today Adventure | [ ] | [ ] | [ ] | |
| Calendar review from Home | [ ] | [ ] | [ ] | |
| Bound cloud sync / unbound local save | [ ] | [ ] | [ ] | |

## 2. Stable IDs

| ID | Harmony | iOS | Android | Notes |
| --- | --- | --- | --- | --- |
| `TodayPlanCheckInButton` | [ ] | [ ] | [ ] | |
| `CheckInPageTitle` | [ ] | [ ] | [ ] | |
| `CheckInCurrentStreak` | [ ] | [ ] | [ ] | |
| `CheckInBestStreak` | [ ] | [ ] | [ ] | |
| `CheckInCloudState` | [ ] | [ ] | [ ] | |
| `CheckInPrevMonthButton` | [ ] | [ ] | [ ] | |
| `CheckInMonthLabel` | [ ] | [ ] | [ ] | |
| `CheckInNextMonthButton` | [ ] | [ ] | [ ] | |
| `CheckInCalendarGrid` | [ ] | [ ] | [ ] | |
| `CheckInDay_<YYYY-MM-DD>` | [ ] | [ ] | [ ] | Dynamic ID pattern. |
| `CheckInWeeklyBonusBanner` | [ ] | [ ] | [ ] | |
| `ResultCheckInBonusRow` | [ ] | [ ] | [ ] | |

## 3. Pure-rule tests

| HarmonyOS test | iOS counterpart | Android counterpart |
| --- | --- | --- |
| `harmonyos/entry/src/test/CheckInStore.test.ets` | [ ] | [ ] |
| `harmonyos/entry/src/test/CloudCheckInService.test.ets` | [ ] | [ ] |
| `harmonyos/entry/src/test/CoinAccount.test.ets` check-in transaction cases | [ ] | [ ] |

## 4. Contract usage

| Contract / fixture | Harmony | iOS | Android |
| --- | --- | --- |
| `shared/contracts/protocols/checkins-sync.md` | [ ] | [ ] | [ ] |
| `shared/fixtures/child/checkins-sync.sample.json` | [ ] | [ ] | [ ] |
| `shared/contracts/openapi/happyword-api.openapi.json` check-in paths | [ ] | [ ] | [ ] |

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
| iOS | `CFBundleShortVersionString` / `CFBundleVersion` | pending signed replication |
| Android | `android/app/build.gradle.kts` `versionName` / `versionCode` | pending signed replication |

## 7. Sign-off

- [ ] Owner verified all rows above are green.
- [ ] Owner ran a smoke pass on at least one device per platform.
- [ ] Feature linked from [`docs/features/README.md`](../../features/README.md) is marked `Done`.

```yaml
done_by:
done_at:
notes:
```
