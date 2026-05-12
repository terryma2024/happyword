# Example Stable-ID Toggle — Parity Checklist

> Inputs (frozen): [`00-design.md`](00-design.md), [`20-replication-trigger.md`](20-replication-trigger.md)
>
> The feature is **Done** only when every row below is `[x]` in all three platform columns.

## 1. User flows

| Flow | Harmony | iOS | Android | Notes |
| --- | --- | --- | --- | --- |
| ConfigPage → toggle ConfigWrongCueSwitch → persist | [x] | [x] | [x] | |
| BattlePage wrong answer with toggle off → BattleWrongCueSkippedMarker mounts for one frame | [x] | [x] | [x] | |
| BattlePage wrong answer with toggle on → marker absent | [x] | [x] | [x] | |

## 2. Stable IDs

| ID | Harmony | iOS | Android | Notes |
| --- | --- | --- | --- | --- |
| `ConfigWrongCueRow` | [x] | [x] | [x] | Container only |
| `ConfigWrongCueLabel` | [x] | [x] | [x] | Localized en/zh-CN |
| `ConfigWrongCueSwitch` | [x] | [x] | [x] | Tap target |
| `BattleWrongCueSkippedMarker` | [x] | [x] | [x] | One render frame |

## 3. Pure-rule tests

| HarmonyOS test | iOS counterpart | Android counterpart |
| --- | --- | --- |
| `LocalUnit > WrongAnswerCue > defaults to true` | [x] | [x] |
| `LocalUnit > WrongAnswerCue > sanitizes non-boolean to true` | [x] | [x] |
| `LocalUnit > WrongAnswerCue > persistence round-trip` | [x] | [x] |
| `WrongCueToggleFlow > skips marker when toggle off` | [x] | [x] |
| `WrongCueToggleFlow > shows marker absent when toggle on` | [x] | [x] |

## 4. Contract usage

N/A. This feature is device-local and does not touch `shared/contracts/` or `shared/fixtures/`.

## 5. Screenshots

| Screen | `assets/screenshots/harmonyos/...` | `assets/screenshots/ios/...` | `assets/screenshots/android/...` |
| --- | --- | --- | --- |
| Config | [x] `config-part2.png` | [x] `config.png` | [x] `config.png` |

## 6. Versions

| Platform | Field | Value |
| --- | --- | --- |
| HarmonyOS | `harmonyos/AppScope/app.json5` `versionName` / `versionCode` | `0.6.7.9` / `1006017` |
| iOS | `CFBundleShortVersionString` / `CFBundleVersion` | `0.6.7.9` / next monotonic |
| Android | `android/app/build.gradle.kts` `versionName` / `versionCode` | `0.6.7.9` / next monotonic |

## 7. Sign-off

- [x] Owner verified all rows above are green.
- [x] Owner ran a smoke pass on at least one device per platform.
- [x] Feature linked from [`docs/features/README.md`](../README.md) is marked `Done`.

```yaml
done_by: SOP authors
done_at: 2026-05-12
notes: Worked-through example accompanying the SOP. Not a real shipping feature.
```
