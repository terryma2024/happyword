import { common } from '@kit.AbilityKit';

export enum SfxDuringVoicePolicy {
  PlayFull = 'play_full',
  LowerVolume = 'lower_volume',
  SuppressNonCritical = 'suppress_non_critical',
  DelayUntilVoiceEnds = 'delay_until_voice_ends',
}

export enum AudioLabVoiceBackend {
  PcmTts = 'pcm_tts',
  SystemTts = 'system_tts',
}

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
  resumeMusicAfterVoice: boolean = false;
}

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
  sfxDuringVoicePolicy: string = SfxDuringVoicePolicy.LowerVolume;
}

export interface AudioLabObserver {
  onSnapshot(snapshot: AudioLabSnapshot): void;
  onEvent(event: AudioLabEvent, detail?: string): void;
}

export interface MusicLabLane {
  preload(ctx: common.UIAbilityContext, rawPath: string): Promise<void>;
  startLoop(): void;
  stop(): void;
  setVolume(value: number): void;
  resumeOnce(): void;
  state(): string;
  dispose(): Promise<void>;
}

export interface SfxLabLane {
  preload(ctx: common.UIAbilityContext, keys: string[]): Promise<void>;
  play(key: string, volume?: number): void;
  dispose(): Promise<void>;
}

export interface VoiceLabLane {
  init(): Promise<void>;
  speak(word: string): void;
  isAvailable(): boolean;
  dispose(): void;
}

export interface AudioLabTimerDriver {
  setTimeout(cb: () => void, ms: number): number;
  clearTimeout(id: number): void;
}

export class RealAudioLabTimerDriver implements AudioLabTimerDriver {
  setTimeout(cb: () => void, ms: number): number {
    return setTimeout(cb, ms);
  }

  clearTimeout(id: number): void {
    clearTimeout(id);
  }
}

export class AudioLabControllerDeps {
  music?: MusicLabLane;
  sfx?: SfxLabLane;
  voice?: VoiceLabLane;
  timer?: AudioLabTimerDriver;
}

export const AUDIO_LAB_BGM_RAW_PATH: string = 'sound/bgm_battle_loop.ogg';
export const AUDIO_LAB_SFX_KEYS: string[] = [
  'hit_normal',
  'hit_crit',
  'answer_wrong',
  'player_hurt',
  'monster_defeat',
  'victory',
  'defeat',
];
