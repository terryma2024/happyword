# PCM Audio Mixing V0.10 — Replication Trigger

> Inputs (frozen): [`00-design.md`](00-design.md), [`10-harmony-plan.md`](10-harmony-plan.md)
>
> iOS and Android agents may start from this document. The human owner approved replication in chat on 2026-06-01 with: "好，现在开两个subagent，开始复刻ios和android上同样的模块和功能。"

## 1. Soft Gate

- [x] **No-device unit tests green** — `cd harmonyos && hvigorw -p module=entry@default test --no-daemon`
  - Evidence: local run on branch `codex/v0-10-audio-merge`, final UI/style commit `b17dd49`.
- [ ] **ohosTest UI tests green** — `scripts/run_ui_tests.sh`
  - Evidence: delegated to HarmonyOS UI automation subagent for full run and fixes.
- [x] **0 `ArkTS:WARN` lines in HAP build** — `cd harmonyos && hvigorw assembleHap --no-daemon`
  - Evidence: local run on branch `codex/v0-10-audio-merge`; build successful, no `ArkTS:WARN`.
- [x] **CodeLinter clean** — `cd harmonyos && codelinter -c ./code-linter.json5 . --fix`
  - Evidence: `No defects found in your code.`
- [ ] **Version bumped** — `harmonyos/AppScope/app.json5`
  - Evidence: not yet bumped on this branch.
- [ ] **Feature merged to main**
  - Evidence: draft PR [#154](https://github.com/terryma2024/happyword/pull/154) open, not merged.
- [ ] **Screenshots refreshed**
  - Evidence: visual screenshot refresh pending after iOS/Android replication and Harmony UI suite.
- [x] **Server contracts up to date**
  - Evidence: N/A; client-only feature.

## 2. Delta Letter

### 2.1 New / changed code

| Layer | HarmonyOS files |
| --- | --- |
| Audio lab | `harmonyos/entry/src/main/ets/audio_lab/**` |
| Battle audio | `harmonyos/entry/src/main/ets/services/BattleAudioMixer.ets`, `harmonyos/entry/src/main/ets/pages/BattlePage.ets` |
| Config model | `harmonyos/entry/src/main/ets/models/GameConfig.ets`, `harmonyos/entry/src/main/ets/services/GameConfigPersistence.ets` |
| Config UI | `harmonyos/entry/src/main/ets/pages/ConfigPage.ets`, `harmonyos/entry/src/main/ets/components/ConfigPageLayout.ets`, `harmonyos/entry/src/main/ets/components/SwitchStyle.ets` |
| Debug tools | `harmonyos/entry/src/main/ets/pages/DevMenuPage.ets`, `harmonyos/entry/src/main/ets/pages/DomainSwitchPage.ets`, `harmonyos/entry/src/main/ets/services/DevMenuToolEntries.ets` |
| Tests | `harmonyos/entry/src/test/BattleAudioMixer.test.ets`, `harmonyos/entry/src/test/AudioLabController.test.ets`, `harmonyos/entry/src/test/ConfigPageLayout.test.ets`, relevant DevMenu/config UI tests |

### 2.2 Persistence keys

| Key | Type | Default | Migration notes |
| --- | --- | --- | --- |
| `autoSpeak` | boolean | `true` | Missing older snapshots backfill to `true`. |
| `playBgm` | boolean | `false` | Missing older snapshots backfill to `false`. |
| `actionSfx` | boolean | `true` | Missing older snapshots backfill to `true`. |
| `enabledQuestionTypes` | string array | all supported defaults | Sanitize to at least one supported type. |

### 2.3 Stable IDs introduced or changed

See [`00-design.md`](00-design.md) §5.

### 2.4 Edge cases discovered during stabilization

- System TTS direct playback can be silent or interrupt BGM; do not expose it.
- Speak-over-BGM must lower BGM to `0.50`, not stop/resume BGM.
- Production battle uses `resumeMusicAfterVoice=false`.
- `GameConfig.actionSfx=false` suppresses SFX and must not lower BGM.
- Win/victory/defeat sequence SFX must not stop BGM.
- Switch button visuals must update on tap; labels and switch columns must stay aligned.

### 2.5 Tests requiring parity counterparts

| HarmonyOS test | iOS counterpart | Android counterpart |
| --- | --- | --- |
| `BattleAudioMixer.test.ets` | XCTest for battle audio mixer policy | JVM/unit test for battle audio mixer policy |
| `AudioLabController.test.ets` | XCTest for PCM lab/controller policy | JVM/unit test for PCM lab/controller policy |
| `ConfigPageLayout.test.ets` | XCTest or snapshot/layout assertion for settings style constants | JVM/layout constants test or Compose UI assertion |
| Config page UI automation | XCUITest config switches | Compose UI test config switches |
| DevMenu route test | XCUITest debug launcher ordering/routes | Compose UI test debug launcher ordering/routes |

### 2.6 Pitfalls

- Do not implement voice by pausing BGM, even if platform audio focus APIs make that easier.
- Do not put Domain Switch contents back inside DevMenu.
- Do not use the old orange selected-chip treatment for question types.
- Do not give parent password/admin buttons yellow warning styling; they are normal parent actions and match learning record.

## 3. Open Questions for Replicas

None.

## 4. Human-Confirm Signature Block

```yaml
approved_by: matianyi
approved_at: 2026-06-01
replication_approved: true
notes: Approved by explicit chat instruction to start iOS and Android replication subagents.
```

