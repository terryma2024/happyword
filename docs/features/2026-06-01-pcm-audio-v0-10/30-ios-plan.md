# PCM Audio Mixing V0.10 — iOS Replication Plan

> Inputs: [`00-design.md`](00-design.md), [`20-replication-trigger.md`](20-replication-trigger.md)
> Owner: iOS replication subagent

## Tasks

- [ ] Verify `20-replication-trigger.md` has `replication_approved: true`.
- [ ] Inspect current iOS audio, battle, config, DevMenu, and UI test structure.
- [ ] Add/extend an iOS PCM battle audio mixer equivalent:
  - Voice playback must not stop BGM.
  - BGM normal volume `0.32`.
  - Speak-over-BGM lowered volume `0.50`.
  - SFX during voice volume `0.35`.
  - `resumeMusicAfterVoice=false`.
- [ ] Add/extend iOS config model persistence for `autoSpeak`, `playBgm`, `actionSfx`, and switch-based question type selection.
- [ ] Update SwiftUI config page:
  - Three audio switches.
  - Question type switches.
  - Switch alignment and grouping consistent with Harmony.
  - Parent action buttons use the learning-record blue style.
- [ ] Update debug menu:
  - `Domain Switch`, `PcmAudioLab`, and `MessageBubbleLab` are peer entries.
  - `PcmAudioLab` has no System TTS switch.
- [ ] Add XCTest/XCUITest parity coverage listed in trigger §2.5.
- [ ] Run commands from `.cursor/ios-dev-commands.md`.
- [ ] Update `50-parity-checklist.md` iOS column for rows that are implemented and green.

## Output Required

Return a summary with changed files, tests run, failures fixed, and remaining parity gaps.

