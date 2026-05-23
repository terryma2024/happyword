# V0.8.6 — 怪物等级积分金币 — Parity Checklist

> Inputs (frozen): [`00-design.md`](00-design.md), [`20-replication-trigger.md`](20-replication-trigger.md)
>
> The feature is **Done** only when every row below is `[x]` in all three platform columns. A row that goes red after Done reopens the feature via [`60-followups.md`](60-followups.md); do not silently fix-and-close.

## 1. User flows

| Flow | Harmony | iOS | Android | Notes |
| --- | --- | --- | --- | --- |
| Battle settlement awards coins from defeated monster levels | [ ] | [ ] | [ ] | Example: 2 level-1 + 2 level-2 + 1 level-3 = 9 coins before daily cap. |
| Loss after partial progress awards only killed monster score | [ ] | [ ] | [ ] | 0 kills earns 0. |
| Bonus monster kill does not add extra coins | [ ] | [ ] | [ ] | Bonus count/visuals remain. |

## 2. Stable IDs

No new stable IDs.

| ID | Harmony | iOS | Android | Notes |
| --- | --- | --- | --- | --- |
| Existing result/home coin labels | [ ] | [ ] | [ ] | Assert displayed earned coins and wallet balance with existing platform IDs/selectors. |

## 3. Pure-rule tests

| HarmonyOS test | iOS counterpart | Android counterpart |
| --- | --- | --- |
| Pending HarmonyOS implementation: monster-level score accumulates 1 + 2 + 3 + 4 by defeated monster level | [ ] | [ ] |
| Pending HarmonyOS implementation: result coins ignore stars and Bonus multiplier | [ ] | [ ] |
| Pending HarmonyOS implementation: partial-loss reward uses defeated monster score | [ ] | [ ] |

## 4. Contract usage

No shared contract or fixture changes.

| Contract / fixture | Harmony | iOS | Android |
| --- | --- | --- | --- |
| N/A | [x] | [x] | [x] |

## 5. Screenshots

| Screen | `assets/screenshots/harmonyos/...` | `assets/screenshots/ios/...` | `assets/screenshots/android/...` |
| --- | --- | --- | --- |
| Result screen coin reward | [ ] | [ ] | [ ] |
| Home screen coin balance | [ ] | [ ] | [ ] |

## 6. Versions

| Platform | Field | Value |
| --- | --- | --- |
| HarmonyOS | `harmonyos/AppScope/app.json5` `versionName` / `versionCode` | Pending HarmonyOS implementation |
| iOS | `CFBundleShortVersionString` / `CFBundleVersion` | Pending Stage 4a |
| Android | `android/app/build.gradle.kts` `versionName` / `versionCode` | Pending Stage 4b |

## 7. Sign-off

- [ ] Owner verified all rows above are green.
- [ ] Owner ran a smoke pass on at least one device per platform.
- [ ] Feature linked from [`docs/features/README.md`](../../features/README.md) is marked `Done`.

```yaml
done_by:
done_at:
notes:
```
