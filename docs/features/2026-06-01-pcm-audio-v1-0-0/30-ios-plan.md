# PCM Audio Mixing V1.0.0 — iOS Replication Plan

> Inputs: [`00-design.md`](00-design.md), [`20-replication-trigger.md`](20-replication-trigger.md)
> Owner: iOS replication subagent

## Tasks

- [x] Verify `20-replication-trigger.md` has `replication_approved: true`.
- [x] Inspect current iOS audio, battle, config, DevMenu, and UI test structure.
- [x] Add/extend an iOS PCM battle audio mixer equivalent:
  - Voice playback must not stop BGM.
  - BGM normal volume `0.32`.
  - Speak-over-BGM lowered volume `0.50`.
  - SFX during voice volume `0.35`.
  - `resumeMusicAfterVoice=false`.
- [x] Add/extend iOS config model persistence for `autoSpeak`, `playBgm`, `actionSfx`, and switch-based question type selection.
- [x] Update SwiftUI config page:
  - Three audio switches.
  - Question type switches.
  - Switch alignment and grouping consistent with Harmony.
  - Parent action buttons use the learning-record blue style.
- [x] Update debug menu:
  - `Domain Switch`, `PcmAudioLab`, and `MessageBubbleLab` are peer entries.
  - `PcmAudioLab` has no System TTS switch.
- [x] Add XCTest/XCUITest parity coverage listed in trigger §2.5.
- [x] Run commands from `.cursor/ios-dev-commands.md`.
- [x] Report iOS parity rows to coordinator after verification.

## Implementation Notes

- Production battle uses `PcmBattleAudioMixer`; default iOS voice playback uses `AVSpeechSynthesizer.write` to produce `AVAudioPCMBuffer` chunks and plays them through an app-owned `AVAudioEngine` lane.
- Config page now exposes `ConfigAutoSpeakSwitch`, `ConfigPlayBgmSwitch`, `ConfigActionSfxSwitch`, and switch-based `ConfigQuestionType_<typeId>` controls.
- DevMenu is a peer launcher; backend routing moved into `DomainSwitchView`, and the debug lab title is `PcmAudioLab`.
- Verification passed on iPhone 17 Pro simulator: unit tests, focused mixer/config/debug UI coverage, and split reruns of the 7 UI cases that the full XCUITest runner killed under one monolithic invocation.
- Temporary screenshots captured for handoff: `/private/tmp/wordmagic-ios-pcm-audio-lab-v010.png` and `/private/tmp/wordmagic-ios-config-v010.png`.
- Remaining acceptance point: human listening confirmation for real iOS audio mix quality.

## Output Required

Return a summary with changed files, tests run, failures fixed, and remaining parity gaps.
