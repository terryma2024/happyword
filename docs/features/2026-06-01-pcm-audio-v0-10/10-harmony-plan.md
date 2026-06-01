# PCM Audio Mixing V0.10 — Harmony Plan

> Status: implemented on branch `codex/v0-10-audio-merge`.

HarmonyOS is the source implementation for this feature. The detailed task plan and post-implementation corrections live in [`docs/superpowers/plans/2026-05-30-v0-10-audio-lab.md`](../../superpowers/plans/2026-05-30-v0-10-audio-lab.md).

## Completed Scope

- [x] Add isolated `audio_lab/` controller and lane model.
- [x] Add PCM voice backend and remove the System TTS switch from the lab.
- [x] Add `PcmAudioLab` debug surface.
- [x] Split `DomainSwitchPage` from `DevMenuPage`; keep `Domain Switch`, `PcmAudioLab`, and `MessageBubbleLab` as peer launcher entries.
- [x] Integrate production `BattleAudioMixer` around the PCM controller/lane route.
- [x] Ensure speak-over-BGM lowers volume instead of stopping BGM.
- [x] Ensure victory/defeat/win sequence audio does not stop BGM.
- [x] Replace config audio playback options with three switches.
- [x] Replace question type chips with switches.
- [x] Align switch columns and use the PackManager switch color style.
- [x] Use clearer ConfigPage group spacing.
- [x] Match parent password/admin buttons to the learning-record blue style.

## Validation Evidence

- [x] `hvigorw -p module=entry@default test --no-daemon`
- [x] `hvigorw assembleHap --no-daemon`
- [x] `codelinter -c ./code-linter.json5 . --fix`
- [x] Installed `entry-default-signed.hap` on the HarmonyOS emulator and launched the app.

