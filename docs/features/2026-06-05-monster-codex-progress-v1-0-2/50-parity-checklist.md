# Monster Codex Progress v1.0.2 — Parity Checklist

> Inputs (frozen): [`00-design.md`](00-design.md), [`20-replication-trigger.md`](20-replication-trigger.md)
>
> The feature is **Done** only when every row below is `[x]` in all three platform columns. A row that goes red after Done reopens the feature via [`60-followups.md`](60-followups.md); do not silently fix-and-close.

## 1. User flows

| Flow | Harmony | iOS | Android | Notes |
| --- | --- | --- | --- | --- |
| Locked codex entry hides image/name/lore/defeat/rewards | [ ] | [ ] | [ ] | |
| Encountered entry shows defeat count plus disabled under-threshold rewards | [ ] | [ ] | [ ] | |
| 50-defeat reward can be claimed once | [ ] | [ ] | [ ] | |
| 100-defeat entry can catch up and claim both rewards if 50 was skipped | [ ] | [ ] | [ ] | |
| Claimed rewards stay visible but disabled | [ ] | [ ] | [ ] | |

## 2. Stable IDs

| ID | Harmony | iOS | Android | Notes |
| --- | --- | --- | --- | --- |
| `CodexAvatar` | [ ] | [ ] | [ ] | Existing ID, now covers mystery image. |
| `CodexName` | [ ] | [ ] | [ ] | |
| `CodexKindLabel` | [ ] | [ ] | [ ] | |
| `CodexDescription` | [ ] | [ ] | [ ] | |
| `CodexPositionIndicator` | [ ] | [ ] | [ ] | |
| `CodexDefeatCount` | [ ] | [ ] | [ ] | New. |
| `CodexReward50Button` | [ ] | [ ] | [ ] | New. |
| `CodexReward100Button` | [ ] | [ ] | [ ] | New. |

## 3. Pure-rule tests

| HarmonyOS test | iOS counterpart | Android counterpart |
| --- | --- | --- |
| `MonsterProgressStore.test.ets` | [ ] | [ ] |
| `MonsterCodex.test.ets` display names and masking | [ ] | [ ] |
| `CoinAccount.test.ets` cap-free codex reward credit | [ ] | [ ] |

## 4. Contract usage

No shared contracts or fixtures.

## 5. Screenshots

| Screen | `assets/screenshots/harmonyos/...` | `assets/screenshots/ios/...` | `assets/screenshots/android/...` |
| --- | --- | --- | --- |
| Monster Codex locked state | [ ] | [ ] | [ ] |
| Monster Codex encountered reward state | [ ] | [ ] | [ ] |

## 6. Versions

| Platform | Field | Value |
| --- | --- | --- |
| HarmonyOS | `harmonyos/AppScope/app.json5` `versionName` / `versionCode` | `1.0.2` / `1020001` |
| iOS | `CFBundleShortVersionString` / `CFBundleVersion` | `1.0.2` / Stage 4 monotonic build number |
| Android | `android/app/build.gradle.kts` `versionName` / `versionCode` | `1.0.2` / Stage 4 monotonic version code |

## 7. Sign-off

- [ ] Owner verified all rows above are green.
- [ ] Owner ran a smoke pass on at least one device per platform.
- [ ] Feature linked from [`docs/features/README.md`](../../features/README.md) is marked `Done`.

```yaml
done_by:
done_at:
notes:
```
