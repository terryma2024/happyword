# PCM Audio Mixing V0.10 — Parity Checklist

> Inputs: [`00-design.md`](00-design.md), [`20-replication-trigger.md`](20-replication-trigger.md)

## 1. User flows

| Flow | Harmony | iOS | Android | Notes |
| --- | --- | --- | --- | --- |
| Speak over BGM lowers volume without stopping BGM | [x] | [ ] | [ ] | Human listening still required on all platforms. |
| Config audio settings are three switches | [x] | [ ] | [ ] | |
| Question type settings are switches | [x] | [ ] | [ ] | |
| DevMenu peer launcher structure | [x] | [ ] | [ ] | |
| PcmAudioLab has no System TTS switch | [x] | [ ] | [ ] | |
| Parent action buttons use learning-record blue style | [x] | [ ] | [ ] | |

## 2. Stable IDs

| ID | Harmony | iOS | Android | Notes |
| --- | --- | --- | --- | --- |
| `ConfigAutoSpeakSwitch` | [x] | [ ] | [ ] | |
| `ConfigPlayBgmSwitch` | [x] | [ ] | [ ] | |
| `ConfigActionSfxSwitch` | [x] | [ ] | [ ] | |
| `ConfigQuestionType_<typeId>` | [x] | [ ] | [ ] | |
| `ConfigParentPinButton` | [x] | [ ] | [ ] | |
| `ConfigCloudSyncButton` | [x] | [ ] | [ ] | |
| `ConfigParentAdminButton` | [x] | [ ] | [ ] | |
| `DevMenuDomainSwitchButton` | [x] | [ ] | [ ] | |
| `DevMenuAudioLabButton` | [x] | [ ] | [ ] | |
| `DevMenuMessageBubbleLabButton` | [x] | [ ] | [ ] | |
| `PcmAudioLabTitle` | [x] | [ ] | [ ] | |

## 3. Pure-rule tests

| HarmonyOS test | iOS counterpart | Android counterpart |
| --- | --- | --- |
| `BattleAudioMixer.test.ets` | [ ] | [ ] |
| `AudioLabController.test.ets` | [ ] | [ ] |
| `ConfigPageLayout.test.ets` | [ ] | [ ] |

## 4. Contract usage

No server/shared contract changes.

## 5. Screenshots

| Screen | `assets/screenshots/harmonyos/...` | `assets/screenshots/ios/...` | `assets/screenshots/android/...` |
| --- | --- | --- | --- |
| Config page | [ ] | [ ] | [ ] |
| DevMenu | [ ] | [ ] | [ ] |
| PcmAudioLab | [ ] | [ ] | [ ] |

## 6. Versions

| Platform | Field | Value |
| --- | --- | --- |
| HarmonyOS | `versionName` / `versionCode` | pending |
| iOS | `CFBundleShortVersionString` / `CFBundleVersion` | pending |
| Android | `versionName` / `versionCode` | pending |

## 7. Sign-off

- [ ] Owner verified all rows above are green.
- [ ] Owner ran a smoke pass on at least one device per platform.
- [ ] Feature linked from [`docs/features/README.md`](../../features/README.md) is marked `Done`.

```yaml
done_by:
done_at:
notes:
```

