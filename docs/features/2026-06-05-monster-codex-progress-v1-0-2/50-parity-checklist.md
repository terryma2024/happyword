# Monster Codex Progress v1.0.2 — Parity Checklist

> Inputs (frozen): [`00-design.md`](00-design.md), [`20-replication-trigger.md`](20-replication-trigger.md)
>
> The feature is **Done** only when every row below is `[x]` in all three platform columns. A row that goes red after Done reopens the feature via [`60-followups.md`](60-followups.md); do not silently fix-and-close.

## 1. User flows

| Flow | Harmony | iOS | Android | Notes |
| --- | --- | --- | --- | --- |
| Locked codex entry hides image/name/lore/defeat/rewards | [x] | [x] | [x] | Locked entries show mystery art and masked text; defeat/reward rows hidden. |
| Encountered entry shows defeat count plus disabled under-threshold rewards | [x] | [x] | [x] | Encountered entries always expose both reward controls in disabled state when under threshold. |
| 50-defeat reward can be claimed once | [x] | [x] | [x] | Cap-free, non-consuming, one-time claim. |
| 100-defeat entry can catch up and claim both rewards if 50 was skipped | [x] | [x] | [x] | Both tiers remain independently claimable until claimed. |
| Claimed rewards stay visible but disabled | [x] | [x] | [x] | Claimed labels are visible and controls remain disabled. |

## 2. Stable IDs

| ID | Harmony | iOS | Android | Notes |
| --- | --- | --- | --- | --- |
| `CodexAvatar` | [x] | [x] | [x] | Existing ID, now covers mystery image. |
| `CodexName` | [x] | [x] | [x] | |
| `CodexKindLabel` | [x] | [x] | [x] | |
| `CodexDescription` | [x] | [x] | [x] | |
| `CodexPositionIndicator` | [x] | [x] | [x] | |
| `CodexDefeatCount` | [x] | [x] | [x] | New; absent for locked entries. |
| `CodexReward50Button` | [x] | [x] | [x] | New; absent for locked entries. |
| `CodexReward100Button` | [x] | [x] | [x] | New; absent for locked entries. |

## 3. Pure-rule tests

| HarmonyOS test | iOS counterpart | Android counterpart |
| --- | --- | --- |
| `MonsterProgressStore.test.ets` | [x] `MonsterCodexTests`, `LocalStores` coverage | [x] `MonsterProgressTest`, `AndroidLocalProgressRepositoriesTest` |
| `MonsterCodex.test.ets` display names and masking | [x] `MonsterCodexTests`, `MonsterDialogueTests` | [x] `MonsterProgressTest`, `GrowthStoresTest` |
| `CoinAccount.test.ets` cap-free codex reward credit | [x] `MonsterCodexTests` / local store reward coverage | [x] `LocalGrowthFlowTest`, `AndroidLocalProgressRepositoriesTest` |

## 4. Contract usage

No shared contracts or fixtures.

## 5. Screenshots

| Screen | `assets/screenshots/harmonyos/...` | `assets/screenshots/ios/...` | `assets/screenshots/android/...` |
| --- | --- | --- | --- |
| Monster Codex locked state | [x] | [x] | [x] |
| Monster Codex encountered reward state | [x] | [x] | [x] |

## 6. Versions

| Platform | Field | Value |
| --- | --- | --- |
| HarmonyOS | `harmonyos/AppScope/app.json5` `versionName` / `versionCode` | `1.0.2` / `1020001` |
| iOS | `CFBundleShortVersionString` / `CFBundleVersion` | `1.0.2` / `1020001` |
| Android | `android/app/build.gradle.kts` `versionName` / `versionCode` | `1.0.2` / `1020001` |

## 7. Sign-off

- [x] Owner verified all rows above are green.
- [x] Owner ran a smoke pass on at least one device per platform.
- [x] Feature linked from [`docs/features/README.md`](../../features/README.md) is marked accepted pending PR merge.

```yaml
done_by: matianyi
done_at: 2026-06-05
notes: All HarmonyOS, iOS, and Android clients accepted by owner; PR remains pending main merge.
```
