# V0.10 Audio Lab Technical Probe Design

- **Date:** 2026-05-30
- **Last updated:** 2026-06-01
- **Status:** HarmonyOS probe accepted; HarmonyOS production battle integration in progress
- **Scope:** HarmonyOS PCM audio lab plus production battle audio adoption notes for iOS/Android replication
- **Related roadmap:** `docs/WordMagicGame_roadmap.md` V0.10 battle audio mixing
- **Predecessor design:** `docs/superpowers/specs/2026-04-30-battle-audio-mixer-design.md`

## 0. 2026-06-01 Harmony Delta For Replication

The original document described an isolated debug probe. Harmony validation has now selected the PCM route and started replacing production battle audio with the same controller/lane model. iOS and Android replicas should use this section as the frozen behavior delta over the earlier probe-only text.

Production battle audio:

- `BattlePage` uses a production `BattleAudioMixer` wrapper around `AudioLabController`; it no longer directly coordinates `AudioService` SFX and `PronunciationService` word playback.
- Voice uses PCM synthesis/playback only. Do not reintroduce a System TTS playback switch for battle or for the debug lab.
- BGM starts only when `GameConfig.playBgm=true`.
- Speaking a word must not stop BGM. It lowers current BGM volume and restores it after the voice timeout.
- Production battle BGM normal volume is `0.32`.
- Production battle speak-over-BGM lowered volume is `0.50`.
- `resumeMusicAfterVoice=false` for production battle. The PCM route should preserve BGM continuity without stop/resume fighting.
- SFX while voice is active uses `SfxDuringVoicePolicy.LowerVolume` at `0.35`.
- `GameConfig.actionSfx=false` suppresses battle SFX and must not trigger BGM lowering as a side effect.

Configuration page:

- The `发音播放` row is three switches:
  - `自动发音`, persisted as `GameConfig.autoSpeak`, default `true`.
  - `播放BGM`, persisted as `GameConfig.playBgm`, default `false`.
  - `动作特效音`, persisted as `GameConfig.actionSfx`, default `true`.
- `题型选择` is also switch-based, not orange selected chips. Each question type has a label plus a switch; at least one question type must remain enabled.

Debug tooling:

- `DevMenuPage` remains a launcher with peer entries `Domain Switch`, `PcmAudioLab`, and `MessageBubbleLab`.
- `DomainSwitchPage` owns backend environment switching.
- `PcmAudioLab` remains useful for manual listening and policy tuning, but it is not the production UI.

Replication requirement:

- iOS and Android must replicate the production semantics above, not the abandoned logical-mixer/System-TTS variants from earlier design notes.

## 1. Goal

Build an isolated HarmonyOS audio lab module that lets developers experience and validate battle-style audio mixing, then apply the selected PCM route to production battle audio.

The lab must make BGM, short SFX, and TTS word pronunciation testable together on a debug/test page. Production adoption may change `BattlePage` audio plumbing only; it must not change battle scoring, question flow, navigation, or release-only UI exposure.

This started as a technical feasibility probe for V0.10. After Harmony validation, the selected PCM route is also the source of truth for production `BattleAudioMixer` integration.

## 2. Non-Goals

- Do not reintroduce System TTS direct playback into battle or the lab.
- Do not expose new controls in release builds.
- Do not listen to `audioInterrupt`.
- Do not add periodic BGM rescue / polling.
- Do not loosen `SpellQuestionFlow.ui.test.ets` polling as part of this probe.
- Do not change iOS or Android independently before the Harmony delta is frozen and handed off through the replication plan.

## 3. Product And SOP Boundary

This lab began as a debug-only technical probe. The debug page itself still does not ship as a child-facing feature, but the selected PCM battle behavior is now a production behavior change and must be replicated through the normal three-platform handoff.

Before iOS and Android start implementation, create or update the normal `docs/features/<feature-id>/` package and follow the Harmony-first replication gate.

### 3.1 Harmony Debug Surface Delta For Replication

The Harmony probe now has a stable debug-entry structure that iOS and Android should mirror when they add their own debug audio labs:

```text
DevMenuPage
  -> Domain Switch
  -> PcmAudioLab
  -> MessageBubbleLab
```

`Domain Switch` is a separate page (`DomainSwitchPage`) that owns backend environment selection, Preview manifest cards, Bypass Secret, health probe status, and routing debug text. `DevMenuPage` itself is only a launcher page with the three peer entries above. The audio lab entry label is `PcmAudioLab`; the route/file name remains `AudioLabPage` on Harmony for compatibility with the existing route profile.

Replication rule:

- iOS and Android debug menus should treat `Domain Switch`, `PcmAudioLab`, and `MessageBubbleLab` as sibling tools, not nest the labs below domain switching.
- Domain/environment switching UI must be isolated from the audio lab. Audio lab testing must not require loading preview manifests or changing backend state.
- The PCM audio lab must not show a System TTS backend switch. Harmony testing proved that the System TTS direct-playback route can be silent or can interrupt/stop BGM, so the selected probe surface is PCM-only.
- Automated UI tests should not depend on the hidden DevMenu unlock gesture. Harmony covers the launcher model with a no-device unit test and keeps DevMenu/triple-tap out of ohosTest; iOS/Android should use the equivalent low-flake coverage for debug launcher ordering/routes.

## 4. Proposed Architecture

Use a standalone controller and three lane interfaces:

```text
AudioLabPage
  -> AudioLabController
      -> MusicLabLane: BGM loop, volume changes, single manual resume
      -> SfxLabLane: short battle SFX playback
      -> PcmVoiceLabLane: TTS synthesize-to-PCM, app-owned renderer playback
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
    PcmVoiceLabLane.ets

harmonyos/entry/src/main/ets/pages/AudioLabPage.ets
harmonyos/entry/src/main/ets/pages/DevMenuPage.ets
harmonyos/entry/src/main/ets/pages/DomainSwitchPage.ets
harmonyos/entry/src/main/ets/services/DevMenuToolEntries.ets
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

  sfxDuringVoicePolicy: SfxDuringVoicePolicy = SfxDuringVoicePolicy.LowerVolume;
  sfxDuringVoiceVolume: number = 0.35;

  /**
   * Defaults to false. The first probe validates volume lowering without
   * actively fighting the system TTS focus behavior.
   */
  resumeMusicAfterVoice: boolean = false;
}
```

Volume inputs are normalized from `0.0` to `1.0`. The page may render them as sliders, but the controller stores normalized values.

`AudioLabConfig.musicLoweredVolume=0.08` remains the generic lab default. Production battle overrides this via `BattleAudioMixer` to `0.50` for speak-over-BGM.

### 6.2 SFX During Voice Policy

The lab must explicitly test the overlap between short SFX and TTS. Every SFX call should pass through one controller policy gate instead of calling the SFX lane directly.

```ts
export enum SfxDuringVoicePolicy {
  PlayFull = 'play_full',
  LowerVolume = 'lower_volume',
  SuppressNonCritical = 'suppress_non_critical',
  DelayUntilVoiceEnds = 'delay_until_voice_ends',
}
```

Policy behavior:

| Policy | Behavior while `voiceActive=true` | Use |
| --- | --- | --- |
| `PlayFull` | Play the SFX at normal volume. | Baseline / A-B comparison. |
| `LowerVolume` | Play the SFX immediately using `sfxDuringVoiceVolume`. | Recommended lab default; preserves feedback without covering pronunciation. |
| `SuppressNonCritical` | Drop non-critical SFX; still allow critical cues. | Candidate production policy if pronunciation clarity needs stronger protection. |
| `DelayUntilVoiceEnds` | Queue one latest non-critical SFX and play it when the voice timeout ends. | Experimental; useful to hear whether delayed feedback feels confusing. |

Critical SFX:

```text
player_hurt
monster_defeat
victory
defeat
```

Non-critical SFX:

```text
hit_normal
hit_crit
answer_wrong
```

The delayed policy must keep at most one pending non-critical SFX. Newer delayed SFX replace older pending SFX so rapid taps cannot build an audio queue.

### 6.3 Events

```ts
export enum AudioLabEvent {
  Enter = 'enter',
  Exit = 'exit',
  StartMusic = 'start_music',
  StopMusic = 'stop_music',
  NormalAttack = 'normal_attack',
  ComboAttack = 'combo_attack',
  WrongAnswer = 'wrong_answer',
  PlayerHurt = 'player_hurt',
  MonsterDefeat = 'monster_defeat',
  Victory = 'victory',
  Defeat = 'defeat',
  SpeakWord = 'speak_word',
  LowerMusic = 'lower_music',
  RestoreMusic = 'restore_music',
  ResumeMusicOnce = 'resume_music_once',
  SfxLoweredForVoice = 'sfx_lowered_for_voice',
  SfxSuppressedForVoice = 'sfx_suppressed_for_voice',
  SfxDelayedForVoice = 'sfx_delayed_for_voice',
  SfxDelayedPlayed = 'sfx_delayed_played',
  Error = 'error',
}
```

### 6.4 Snapshot

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
  pendingDelayedSfx: string = '';
  sfxDuringVoicePolicy: string = 'lower_volume';
}
```

The snapshot is for page display and manual debugging. It is not a persistence model and should not be stored in `AppStorage`.

### 6.5 Observer

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
  playWrongAnswer(): void;
  playPlayerHurt(): void;
  playMonsterDefeat(): void;
  playVictory(): void;
  playDefeat(): void;

  speakWord(word: string): void;

  demoSpeakOverMusic(word: string): void;
  demoComboOverMusic(): void;
  demoWrongAnswerSequence(): void;
  demoVictorySequence(): void;
  demoSfxDuringVoice(word: string): void;
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
5. VoiceLabLane.speak(word) using the PCM implementation.
6. Schedule one timeout using voiceLowerDurationMs.
7. On timeout, if token is still current:
   - mark voice inactive
   - restoreMusicVolume('voice-timeout')
   - play any pending delayed SFX if the policy is DelayUntilVoiceEnds
   - if resumeMusicAfterVoice is true, resumeMusicOnce('voice-timeout')
```

The System TTS direct-playback route was removed after manual validation. It can be silent on the simulator and can still stop or interrupt BGM even when the controller only lowers volume. The selected lab route is therefore `PcmVoiceLabLane`: request TTS synthesis with `playType=0`, receive PCM chunks through `SpeakListener.onData`, and render them through an app-owned `AudioRenderer` stream. Timeout-based restoration remains in the controller so the lab can compare policy timing without depending on production battle flow.

### 7.4 SFX Policy Gate

All public SFX methods should route through one private controller method:

```ts
private playSfx(key: string, critical: boolean): void
```

Behavior:

```text
1. If disposed or SFX disabled, no-op.
2. If voiceActive is false, play at sfxVolume.
3. If voiceActive is true:
   - PlayFull: play at sfxVolume.
   - LowerVolume: play at sfxDuringVoiceVolume.
   - SuppressNonCritical:
       - if critical, play at sfxDuringVoiceVolume.
       - if non-critical, drop and emit SfxSuppressedForVoice.
   - DelayUntilVoiceEnds:
       - if critical, play at sfxDuringVoiceVolume.
       - if non-critical, store as pendingDelayedSfx and emit SfxDelayedForVoice.
```

This policy gate is part of the lab's core value. It lets developers compare whether the final production mixer should lower, suppress, or delay SFX during pronunciation.

### 7.5 Demo Flows

Demo flows exist so a developer can experience realistic sequencing without entering battle:

- `demoSpeakOverMusic(word)`: start BGM, wait a short moment, speak word over lowered BGM.
- `demoComboOverMusic()`: start BGM, lower briefly, play combo SFX, restore.
- `demoWrongAnswerSequence()`: play wrong-answer SFX, then delayed player-hurt SFX.
- `demoVictorySequence()`: stop or lower BGM, then play victory fanfare.
- `demoSfxDuringVoice(word)`: start BGM, speak word, trigger normal / combo / hurt SFX while `voiceActive=true` so the selected policy is audible.

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

The lab exposes one backend implementation:

- `PcmVoiceLabLane`: owns a CoreSpeechKit engine listener, buffers `onData` PCM chunks, and feeds an `AudioRenderer.writeData` callback. This is the candidate route for true BGM/SFX/voice overlap because pronunciation no longer asks CoreSpeechKit to own playback focus.

`PcmVoiceLabLane` was first isolated under `audio_lab/` for manual listening. Harmony production battle now reuses this route through `BattleAudioMixer`; new platform replicas should keep a similar app-owned PCM voice lane instead of using direct system TTS playback for battle.

## 9. PcmAudioLab Page

The page should expose actual controls, not just logs:

```text
BGM:
  start / stop / lower for voice / lower temporarily / restore / resume once

SFX:
  normal attack / combo attack / wrong answer / player hurt /
  monster defeat / victory / defeat

Voice:
  word selection / speak via PCM mix

Demos:
  speak over BGM / combo over BGM / wrong answer sequence /
  victory sequence / SFX during voice

Settings:
  music enabled / sfx enabled / voice enabled / resume after voice
  music volume / lowered music volume / sfx volume /
  SFX during voice policy / SFX during voice volume /
  voice lower timeout

Debug:
  musicState / voiceActive / pendingTimers / resumeAttempts /
  pendingDelayedSfx / selected SFX policy / lastEvent / lastError
```

The page can be utilitarian. It is a developer tool, so density and fast iteration matter more than decorative polish.

Layout and interaction requirements from Harmony validation:

- Keep the page compact enough for landscape simulator use; Mix/settings controls should sit below Transport and Voice rather than clipped off the right edge.
- Word chips must be real selectable controls; tapping a word changes the active word and the selected visual state.
- Mix policy controls and on/off toggles must update both controller config and visible state.
- Numeric volume controls must show visible `-` / `+` controls and update the displayed percentage immediately after taps.
- The page title and DevMenu entry must read `PcmAudioLab`, not generic `Audio Lab`, once the System TTS option is removed.
- `Speak over BGM`, `Win sequence`, and other demo flows must not stop current BGM unless the button is explicitly a BGM stop control.

## 10. Error Handling

- Missing BGM: disable music lane, log error, keep SFX and voice usable.
- Missing SFX: mute only that key.
- TTS unavailable: voice controls no-op and show unavailable in the snapshot.
- Unsupported TTS audio type: PCM voice lane logs and ignores the chunk.
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
- PCM chunk queue fills renderer buffers across TTS chunk boundaries and clears stale utterance data.
- SFX disabled blocks SFX play calls.
- Music disabled blocks BGM controls but does not block SFX / voice.
- `LowerVolume` policy plays SFX at `sfxDuringVoiceVolume` while voice is active.
- `SuppressNonCritical` drops non-critical SFX and still plays critical SFX.
- `DelayUntilVoiceEnds` keeps only the latest pending non-critical SFX.
- Voice timeout plays and clears pending delayed SFX.

### 11.2 Manual Lab Validation

On HarmonyOS device or simulator:

- Start BGM and confirm loop playback.
- Play every SFX over BGM.
- Speak a word over BGM and confirm BGM volume lowers then restores.
- Confirm BGM keeps playing while PCM voice is audible.
- While speaking, trigger normal / combo / hurt SFX under each SFX policy and compare clarity.
- Toggle `resume after voice` and compare behavior.
- Run demo flows and confirm no stuck lowered volume after exit/re-enter.
- Navigate away from the lab and confirm BGM stops.

### 11.3 Production Regression Guard

Because the lab is isolated, the first implementation should still verify:

```text
cd harmonyos && hvigorw assembleHap
cd harmonyos && codelinter -c ./code-linter.json5 . --fix
```

The HAP build log must have zero `ArkTS:WARN` lines. Lab-only work does not require full battle UI looping, but production battle integration must include battle audio unit coverage and focused manual listening for:

- BGM enabled, speak over BGM, BGM remains playing.
- BGM returns from `0.50` lowered volume to `0.32`.
- `Win sequence` / victory / defeat cues do not accidentally stop ongoing BGM unless the spec explicitly calls for terminal music stop.
- `actionSfx=false` suppresses SFX and does not lower BGM.
- Config page switches persist and affect the next battle.

## 12. Acceptance Criteria

- Audio lab module exists under `audio_lab/`.
- Debug-only page can start/stop BGM.
- Page can play current battle SFX over BGM.
- Page can speak a typed word while lowering BGM volume.
- Page uses the `PCM mix` voice backend only; no voice backend switch is shown.
- DevMenu shows `Domain Switch`, `PcmAudioLab`, and `MessageBubbleLab` as peer entries.
- Backend environment switching lives on `DomainSwitchPage`, not on `DevMenuPage`.
- Page can compare SFX/TTS overlap policies: full, lowered, suppressed, delayed.
- Page can manually test `resumeMusicOnce`.
- `resumeMusicAfterVoice` defaults to false.
- Leaving the page stops BGM and releases resources.
- Production battle uses `BattleAudioMixer` once the PCM route is selected.
- Production speak-over-BGM lowers BGM to `0.50`, then restores to `0.32`.
- Config page exposes the three audio switches and switch-based question type selection.
- Release build does not expose the lab entry.
- Build and CodeLinter pass with zero ArkTS warnings.

## 13. Replica Notes For iOS And Android

The production goal is cross-platform battle audio parity, but the debug probe should remain platform-native:

| Concern | Harmony source of truth | iOS replica guidance | Android replica guidance |
| --- | --- | --- | --- |
| Debug entry structure | `DevMenuPage` + `DevMenuToolEntries` | Add a debug launcher with peer entries: Domain Switch, PcmAudioLab, MessageBubbleLab. | Same peer launcher structure in debug tooling. |
| Domain switching | `DomainSwitchPage` | Keep environment switching outside the audio lab. | Keep environment switching outside the audio lab. |
| Voice backend | `PcmVoiceLabLane` only | Prefer synthesized/decoded PCM rendered through app-owned audio output. Do not expose a broken System TTS comparison toggle. | Prefer synthesized/decoded PCM rendered through app-owned audio output. Do not expose a broken System TTS comparison toggle. |
| Production config | `GameConfig.autoSpeak/playBgm/actionSfx` | Add the same three persisted switches: auto speak default on, BGM default off, action SFX default on. | Same three persisted switches in Settings/Config. |
| Question type settings | `ConfigPage` switch controls | Use switch controls, not selected chips/buttons; enforce at least one enabled type. | Same switch controls and invariant. |
| BGM behavior | `BattleAudioMixer` + `MusicLabLane.setVolume`, no pause on voice | Speaking over BGM lowers music to 50% and restores to 32%; it must not stop BGM. | Speaking over BGM lowers music to 50% and restores to 32%; it must not stop BGM. |
| SFX during voice | Controller policy gate | Preserve full/lower/suppress/delay policy semantics. | Preserve full/lower/suppress/delay policy semantics. |
| Test strategy | no-device controller + launcher-model tests; DevMenu not in ohosTest | Unit-test controller policy and debug launcher model; keep hidden debug gesture out of flaky UI automation. | Unit-test controller policy and debug launcher model; keep hidden debug gesture out of flaky UI automation. |

Do not replicate the abandoned System TTS direct-playback branch. It was useful as a probe, but it created confusion and did not provide reliable audible output with BGM.
