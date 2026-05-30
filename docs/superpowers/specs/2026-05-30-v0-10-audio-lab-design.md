# V0.10 Audio Lab Technical Probe Design

- **Date:** 2026-05-30
- **Status:** Draft for user review
- **Scope:** HarmonyOS technical probe only
- **Related roadmap:** `docs/WordMagicGame_roadmap.md` V0.10 battle audio mixing
- **Predecessor design:** `docs/superpowers/specs/2026-04-30-battle-audio-mixer-design.md`

## 1. Goal

Build an isolated HarmonyOS audio lab module that lets developers experience and validate battle-style audio mixing before touching the production battle flow.

The lab must make BGM, short SFX, and TTS word pronunciation testable together on a debug/test page. It must not change current `BattlePage` behavior, production navigation, battle scoring, question flow, or release UI.

This is a technical feasibility probe for V0.10, not the final `BattleAudioMixer` product integration.

## 2. Non-Goals

- Do not modify `BattlePage` audio call sites.
- Do not replace the existing production `AudioService` / `PronunciationService` usage.
- Do not expose new controls in release builds.
- Do not implement three-platform replication yet.
- Do not register CoreSpeechKit listeners in the first probe.
- Do not listen to `audioInterrupt`.
- Do not add periodic BGM rescue / polling.
- Do not loosen `SpellQuestionFlow.ui.test.ets` polling as part of this probe.
- Do not implement PCM-level real mixing.

## 3. Product And SOP Boundary

This lab is a debug-only technical probe. It does not ship a child-facing product feature and therefore does not start the full three-platform feature lifecycle by itself.

If the lab proves feasible and the audio behavior is selected for production battle, V0.10 must then create the normal `docs/features/<feature-id>/` package and follow the Harmony-first replication gate before iOS and Android begin implementation.

## 4. Proposed Architecture

Use a standalone controller and three lane interfaces:

```text
AudioLabPage
  -> AudioLabController
      -> MusicLabLane: BGM loop, volume changes, single manual resume
      -> SfxLabLane: short battle SFX playback
      -> VoiceLabLane: TTS word pronunciation
```

The controller owns sequencing and timers. The page owns only UI controls and debug display. The lanes hide platform playback details behind small interfaces so the technical probe can later inform `BattleAudioMixer` without coupling it to the page.

Recommended files:

```text
harmonyos/entry/src/main/ets/audio_lab/
  AudioLabTypes.ets
  AudioLabController.ets
  lanes/
    MusicLabLane.ets
    SfxLabLane.ets
    VoiceLabLane.ets

harmonyos/entry/src/main/ets/pages/AudioLabPage.ets
```

The lab page should be reachable only from the existing debug/developer surface. Release builds must not expose it.

## 5. Naming Rule

The implementation should avoid exposing the term `duck` in public page-facing APIs. The audio concept is still ducking, but developer-facing methods should use explicit names:

- `lowerMusicForVoice`
- `lowerMusicTemporarily`
- `restoreMusicVolume`
- `resumeMusicOnce`

This keeps the test page understandable while preserving the underlying audio design.

## 6. Core Types

### 6.1 Config

```ts
export class AudioLabConfig {
  musicEnabled: boolean = true;
  sfxEnabled: boolean = true;
  voiceEnabled: boolean = true;

  masterVolume: number = 1.0;
  musicVolume: number = 0.32;
  musicLoweredVolume: number = 0.08;
  sfxVolume: number = 1.0;
  voiceVolume: number = 1.0;

  voiceLowerDurationMs: number = 1800;
  comboLowerDurationMs: number = 450;

  /**
   * Defaults to false. The first probe validates volume lowering without
   * actively fighting the system TTS focus behavior.
   */
  resumeMusicAfterVoice: boolean = false;
}
```

Volume inputs are normalized from `0.0` to `1.0`. The page may render them as sliders, but the controller stores normalized values.

### 6.2 Events

```ts
export enum AudioLabEvent {
  Enter = 'enter',
  Exit = 'exit',
  StartMusic = 'start_music',
  StopMusic = 'stop_music',
  NormalAttack = 'normal_attack',
  ComboAttack = 'combo_attack',
  PlayerHurt = 'player_hurt',
  MonsterDefeat = 'monster_defeat',
  Victory = 'victory',
  Defeat = 'defeat',
  SpeakWord = 'speak_word',
  LowerMusic = 'lower_music',
  RestoreMusic = 'restore_music',
  ResumeMusicOnce = 'resume_music_once',
  Error = 'error',
}
```

### 6.3 Snapshot

```ts
export class AudioLabSnapshot {
  musicState: string = 'idle';
  voiceActive: boolean = false;
  disposed: boolean = false;

  musicVolume: number = 0;
  lastEvent: string = '';
  lastError: string = '';

  pendingTimers: number = 0;
  resumeAttempts: number = 0;
}
```

The snapshot is for page display and manual debugging. It is not a persistence model and should not be stored in `AppStorage`.

### 6.4 Observer

```ts
export interface AudioLabObserver {
  onSnapshot(snapshot: AudioLabSnapshot): void;
  onEvent(event: AudioLabEvent, detail?: string): void;
}
```

The controller should call the observer after meaningful state changes. Observer failures must not break audio playback.

## 7. Controller Interface

```ts
export class AudioLabController {
  constructor(config?: AudioLabConfig, observer?: AudioLabObserver)

  async enter(ctx: common.UIAbilityContext): Promise<void>;
  async exit(): Promise<void>;

  updateConfig(next: AudioLabConfig): void;
  snapshot(): AudioLabSnapshot;

  startMusic(): void;
  stopMusic(): void;
  lowerMusicForVoice(): void;
  lowerMusicTemporarily(reason: string, durationMs: number): void;
  restoreMusicVolume(reason: string): void;
  resumeMusicOnce(reason: string): void;

  playNormalAttack(): void;
  playComboAttack(): void;
  playPlayerHurt(): void;
  playMonsterDefeat(): void;
  playVictory(): void;
  playDefeat(): void;

  speakWord(word: string): void;

  demoSpeakOverMusic(word: string): void;
  demoComboOverMusic(): void;
  demoWrongAnswerSequence(): void;
  demoVictorySequence(): void;
}
```

### 7.1 Lifecycle

`enter(ctx)` preloads music, SFX, and TTS best-effort. It must not throw for a missing single resource; failed lanes degrade independently.

`exit()` cancels every timer, stops music, releases players, disposes TTS, marks the controller disposed, and makes later callbacks no-op.

### 7.2 Music Controls

`startMusic()` starts the BGM loop if music is enabled and loaded.

`stopMusic()` stops BGM without disposing the controller.

`lowerMusicForVoice()` sets music volume to `musicLoweredVolume` and records voice-lowering intent. It must not pause the player.

`lowerMusicTemporarily(reason, durationMs)` lowers music volume and schedules a one-shot restore. A newer lower request cancels the previous restore timer.

`restoreMusicVolume(reason)` restores music to `musicVolume` if the controller is active.

`resumeMusicOnce(reason)` may call the music lane's single resume path. It is never called automatically unless `resumeMusicAfterVoice` is true.

### 7.3 Voice Flow

`speakWord(word)`:

```text
1. If voice is disabled or word is empty, no-op.
2. Increment a voice token.
3. Mark voiceActive.
4. lowerMusicForVoice().
5. VoiceLabLane.speak(word).
6. Schedule one timeout using voiceLowerDurationMs.
7. On timeout, if token is still current:
   - mark voice inactive
   - restoreMusicVolume('voice-timeout')
   - if resumeMusicAfterVoice is true, resumeMusicOnce('voice-timeout')
```

The first probe intentionally does not use a CoreSpeechKit completion listener. Timeout-based restoration is easier to validate and avoids the listener marshal cost that previously destabilized spell tap tests.

### 7.4 Demo Flows

Demo flows exist so a developer can experience realistic sequencing without entering battle:

- `demoSpeakOverMusic(word)`: start BGM, wait a short moment, speak word over lowered BGM.
- `demoComboOverMusic()`: start BGM, lower briefly, play combo SFX, restore.
- `demoWrongAnswerSequence()`: play wrong-answer SFX, then delayed player-hurt SFX.
- `demoVictorySequence()`: stop or lower BGM, then play victory fanfare.

Demo methods are convenience wrappers only. They must use the same public controller methods as the page buttons.

## 8. Lane Interfaces

### 8.1 MusicLabLane

```ts
export interface MusicLabLane {
  preload(ctx: common.UIAbilityContext, rawPath: string): Promise<void>;
  startLoop(): void;
  stop(): void;
  setVolume(value: number): void;
  resumeOnce(): void;
  state(): string;
  dispose(): Promise<void>;
}
```

The first implementation should use the existing bundled resource:

```text
sound/bgm_battle_loop.ogg
```

The lab must not use `sound/battle_bgm.mp3` as a runtime resource. If that MP3 is retained as source material, it should be moved under `assets/audio/` with a short README entry in a separate asset-cleanup change.

### 8.2 SfxLabLane

```ts
export interface SfxLabLane {
  preload(ctx: common.UIAbilityContext, keys: string[]): Promise<void>;
  play(key: string, volume?: number): void;
  dispose(): Promise<void>;
}
```

The first implementation may wrap or mirror `AudioService` behavior. The probe should not promise same-key polyphony; it only needs to verify that short SFX can be heard with BGM active and TTS flows nearby.

Initial SFX keys:

```text
hit_normal
hit_crit
answer_wrong
player_hurt
monster_defeat
victory
defeat
```

If a new `combo_attack.ogg` is later added, it can be inserted behind this interface without changing the page.

### 8.3 VoiceLabLane

```ts
export interface VoiceLabLane {
  init(): Promise<void>;
  speak(word: string): void;
  isAvailable(): boolean;
  dispose(): void;
}
```

The first implementation may delegate to `PronunciationService`. It must not add listener registration or new production behavior.

## 9. Audio Lab Page

The page should expose actual controls, not just logs:

```text
BGM:
  start / stop / lower for voice / lower temporarily / restore / resume once

SFX:
  normal attack / combo attack / wrong answer / player hurt /
  monster defeat / victory / defeat

Voice:
  word input / speak

Demos:
  speak over BGM / combo over BGM / wrong answer sequence / victory sequence

Settings:
  music enabled / sfx enabled / voice enabled / resume after voice
  music volume / lowered music volume / sfx volume / voice lower timeout

Debug:
  musicState / voiceActive / pendingTimers / resumeAttempts /
  lastEvent / lastError
```

The page can be utilitarian. It is a developer tool, so density and fast iteration matter more than decorative polish.

## 10. Error Handling

- Missing BGM: disable music lane, log error, keep SFX and voice usable.
- Missing SFX: mute only that key.
- TTS unavailable: voice controls no-op and show unavailable in the snapshot.
- Player error: record `lastError`, degrade the affected lane only.
- Disposed callback: no-op.
- Observer error: catch and log, do not break controller state.

Audio failure must never crash the lab page.

## 11. Verification Plan

### 11.1 Unit Tests

Use fake lanes to cover controller behavior without native audio:

- `enter()` initializes lanes best-effort.
- `exit()` clears pending timers and makes later callbacks no-op.
- `lowerMusicForVoice()` changes music volume without stopping music.
- `speakWord()` lowers music and restores after timeout.
- Stale voice timeout cannot restore after a newer speak token.
- `resumeMusicAfterVoice=false` never calls `resumeOnce`.
- `resumeMusicAfterVoice=true` calls `resumeOnce` at most once per speak timeout.
- SFX disabled blocks SFX play calls.
- Music disabled blocks BGM controls but does not block SFX / voice.

### 11.2 Manual Lab Validation

On HarmonyOS device or simulator:

- Start BGM and confirm loop playback.
- Play every SFX over BGM.
- Speak a word over BGM and confirm BGM volume lowers then restores.
- Toggle `resume after voice` and compare behavior.
- Run demo flows and confirm no stuck lowered volume after exit/re-enter.
- Navigate away from the lab and confirm BGM stops.

### 11.3 Production Regression Guard

Because the lab is isolated, the first implementation should still verify:

```text
cd harmonyos && hvigorw assembleHap
cd harmonyos && codelinter -c ./code-linter.json5 . --fix
```

The HAP build log must have zero `ArkTS:WARN` lines. Since the lab does not touch `BattlePage`, full `SpellQuestionFlow.ui.test.ets` looping is not a gate for the lab-only PR, but it remains required before production V0.10 battle audio integration.

## 12. Acceptance Criteria

- Audio lab module exists under `audio_lab/`.
- Debug-only page can start/stop BGM.
- Page can play current battle SFX over BGM.
- Page can speak a typed word while lowering BGM volume.
- Page can manually test `resumeMusicOnce`.
- `resumeMusicAfterVoice` defaults to false.
- Leaving the page stops BGM and releases resources.
- No production battle behavior changes.
- Release build does not expose the lab entry.
- Build and CodeLinter pass with zero ArkTS warnings.
