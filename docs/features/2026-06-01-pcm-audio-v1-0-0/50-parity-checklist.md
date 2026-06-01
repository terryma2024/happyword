# PCM Audio Mixing V1.0.0 — Parity Checklist

> Inputs: [`00-design.md`](00-design.md), [`20-replication-trigger.md`](20-replication-trigger.md)

## 1. User flows

| Flow | Harmony | iOS | Android | Notes |
| --- | --- | --- | --- | --- |
| Speak over BGM lowers volume without stopping BGM | [x] | [x] | [x] | Automated policy/lane coverage is green; human listening still required on real iOS/Android devices. |
| Config audio settings are three switches | [x] | [x] | [x] | |
| Question type settings are switches | [x] | [x] | [x] | |
| DevMenu peer launcher structure | [x] | [x] | [x] | |
| PcmAudioLab has no System TTS switch | [x] | [x] | [x] | |
| Parent action buttons use learning-record blue style | [x] | [x] | [x] | |

## 2. Stable IDs

| ID | Harmony | iOS | Android | Notes |
| --- | --- | --- | --- | --- |
| `ConfigAutoSpeakSwitch` | [x] | [x] | [x] | |
| `ConfigPlayBgmSwitch` | [x] | [x] | [x] | |
| `ConfigActionSfxSwitch` | [x] | [x] | [x] | |
| `ConfigQuestionType_<typeId>` | [x] | [x] | [x] | |
| `ConfigParentPinButton` | [x] | [x] | [x] | |
| `ConfigCloudSyncButton` | [x] | [x] | [x] | |
| `ConfigParentAdminButton` | [x] | [x] | [x] | |
| `DevMenuDomainSwitchButton` | [x] | [x] | [x] | |
| `DevMenuAudioLabButton` | [x] | [x] | [x] | |
| `DevMenuMessageBubbleLabButton` | [x] | [x] | [x] | |
| `PcmAudioLabTitle` | [x] | [x] | [x] | |

## 3. Pure-rule tests

| HarmonyOS test | iOS counterpart | Android counterpart |
| --- | --- | --- |
| `BattleAudioMixer.test.ets` | `PronunciationServiceTests` | `BattleAudioMixerPolicyTest` |
| `AudioLabController.test.ets` | `WordMagicGameUITests` PcmAudioLab coverage | `AndroidScreenScreenshotTest` PcmAudioLab coverage |
| `ConfigPageLayout.test.ets` | `GameConfigTests` + `WordMagicGameUITests` config coverage | `ConfigLayoutPolicyTest` + `ConfigAudioSwitchFlowTest` |

## 4. Contract usage

No server/shared contract changes.

## 5. Screenshots

| Screen | `assets/screenshots/harmonyos/...` | `assets/screenshots/ios/...` | `assets/screenshots/android/...` |
| --- | --- | --- | --- |
| Config page | [x] | [x] | [x] |
| DevMenu | [x] | [x] | [x] |
| PcmAudioLab | [x] | [x] | [x] |

## 6. Versions

| Platform | Field | Value |
| --- | --- | --- |
| HarmonyOS | `versionName` / `versionCode` | `1.0.0` / `1010000` |
| iOS | `CFBundleShortVersionString` / `CFBundleVersion` | `1.0.0` / `1010000` |
| Android | `versionName` / `versionCode` | `1.0.0` / `1010000` |

## 7. Sign-off

- [x] Owner verified automated parity rows above are green.
- [ ] Owner ran human listening smoke pass on real iOS and Android devices.
- [x] Feature linked from [`docs/features/README.md`](../../features/README.md) is marked `Stage 5 human audio QA`.

```yaml
done_by: codex
done_at: 2026-06-01
notes: HarmonyOS full ohosTest 81/81, Android connectedDebugAndroidTest 44/44, iOS unit tests passed and previously killed UI cases passed in split reruns. Human listening remains for real-device audio mix quality.
```
