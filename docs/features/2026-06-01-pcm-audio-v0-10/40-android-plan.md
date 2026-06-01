# PCM Audio Mixing V0.10 — Android Replication Plan

> Inputs: [`00-design.md`](00-design.md), [`20-replication-trigger.md`](20-replication-trigger.md)
> Owner: Android replication subagent

## Tasks

- [x] Verify `20-replication-trigger.md` has `replication_approved: true`.
- [x] Inspect current Android audio, battle, config, DevMenu, and UI test structure.
- [x] Add/extend an Android PCM battle audio mixer equivalent:
  - Voice playback must not stop BGM.
  - BGM normal volume `0.32`.
  - Speak-over-BGM lowered volume `0.50`.
  - SFX during voice volume `0.35`.
  - `resumeMusicAfterVoice=false`.
- [x] Add/extend Android config persistence for `autoSpeak`, `playBgm`, `actionSfx`, and switch-based question type selection.
- [x] Update Compose config page:
  - Three audio switches.
  - Question type switches.
  - Switch alignment and grouping consistent with Harmony.
  - Parent action buttons use the learning-record blue style.
- [x] Update debug menu:
  - `Domain Switch`, `PcmAudioLab`, and `MessageBubbleLab` are peer entries.
  - `PcmAudioLab` has no System TTS switch.
- [x] Add JVM/Compose UI parity coverage listed in trigger §2.5.
- [x] Run commands from `.cursor/android-dev-commands.md`.
- [x] Update `50-parity-checklist.md` Android column for rows that are implemented and green.

## Implementation Notes

- Production battle uses `AndroidBattleAudioMixer`: BGM is app-owned `MediaPlayer`, voice is synthesized to an app-local file and played through a separate `MediaPlayer`, and SFX cues use policy volumes so voice no longer stops music.
- Config persistence now includes `autoSpeak`, `playBgm`, `actionSfx`, and switch-based question type state.
- DevMenu uses peer entries for `Domain Switch`, `PcmAudioLab`, and `MessageBubbleLab`; backend routing lives on a separate domain-switch screen.
- Verification passed on the Android emulator: `testDebugUnitTest`, `assembleDebug`, focused screenshot class, and full `connectedDebugAndroidTest` (44 tests).
- Remaining acceptance point: human listening confirmation for real Android audio mix quality.

## Output Required

Return a summary with changed files, tests run, failures fixed, and remaining parity gaps.
