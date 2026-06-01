import { common } from '@kit.AbilityKit';
import {
  AUDIO_LAB_BGM_RAW_PATH,
  AUDIO_LAB_SFX_KEYS,
  AudioLabConfig,
  AudioLabControllerDeps,
  AudioLabEvent,
  AudioLabObserver,
  AudioLabSnapshot,
  AudioLabTimerDriver,
  MusicLabLane,
  RealAudioLabTimerDriver,
  SfxDuringVoicePolicy,
  SfxLabLane,
  VoiceLabLane,
} from './AudioLabTypes';
import { RealMusicLabLane } from './lanes/MusicLabLane';
import { RealSfxLabLane } from './lanes/SfxLabLane';
import { PcmVoiceLabLane } from './lanes/PcmVoiceLabLane';

const KEY_HIT_NORMAL: string = 'hit_normal';
const KEY_HIT_CRIT: string = 'hit_crit';
const KEY_ANSWER_WRONG: string = 'answer_wrong';
const KEY_PLAYER_HURT: string = 'player_hurt';
const KEY_MONSTER_DEFEAT: string = 'monster_defeat';
const KEY_VICTORY: string = 'victory';
const KEY_DEFEAT: string = 'defeat';

export class AudioLabController {
  private config: AudioLabConfig;
  private observer?: AudioLabObserver;
  private music: MusicLabLane;
  private sfx: SfxLabLane;
  private voice: VoiceLabLane;
  private timer: AudioLabTimerDriver;
  private snap: AudioLabSnapshot = new AudioLabSnapshot();
  private musicRestoreTimer: number = -1;
  private voiceTimer: number = -1;
  private voiceToken: number = 0;

  constructor(config?: AudioLabConfig, observer?: AudioLabObserver, deps?: AudioLabControllerDeps) {
    this.config = config !== undefined ? config : new AudioLabConfig();
    this.observer = observer;
    this.music = deps?.music !== undefined ? deps.music : new RealMusicLabLane();
    this.sfx = deps?.sfx !== undefined ? deps.sfx : new RealSfxLabLane();
    this.voice = deps?.voice !== undefined ? deps.voice : new PcmVoiceLabLane();
    this.timer = deps?.timer !== undefined ? deps.timer : new RealAudioLabTimerDriver();
    this.snap.sfxDuringVoicePolicy = this.config.sfxDuringVoicePolicy;
  }

  async enter(ctx: common.UIAbilityContext): Promise<void> {
    if (this.snap.disposed) {
      return;
    }
    await Promise.all([
      this.music.preload(ctx, AUDIO_LAB_BGM_RAW_PATH).catch((err: Error): void => {
        this.recordError('music preload', err);
      }),
      this.sfx.preload(ctx, AUDIO_LAB_SFX_KEYS).catch((err: Error): void => {
        this.recordError('sfx preload', err);
      }),
      this.voice.init().catch((err: Error): void => {
        this.recordError('voice init', err);
      }),
    ]);
    this.emit(AudioLabEvent.Enter);
  }

  async exit(): Promise<void> {
    this.snap.disposed = true;
    this.snap.voiceActive = false;
    this.clearMusicRestoreTimer();
    this.clearVoiceTimer();
    this.snap.pendingDelayedSfx = '';
    this.music.stop();
    await Promise.all([
      this.music.dispose(),
      this.sfx.dispose(),
    ]);
    this.voice.dispose();
    this.emit(AudioLabEvent.Exit);
  }

  updateConfig(next: AudioLabConfig): void {
    this.config = next;
    this.snap.sfxDuringVoicePolicy = next.sfxDuringVoicePolicy;
    this.emitSnapshot();
  }

  snapshot(): AudioLabSnapshot {
    const out: AudioLabSnapshot = new AudioLabSnapshot();
    out.musicState = this.music.state();
    out.voiceActive = this.snap.voiceActive;
    out.disposed = this.snap.disposed;
    out.musicVolume = this.snap.musicVolume;
    out.lastEvent = this.snap.lastEvent;
    out.lastError = this.snap.lastError;
    out.pendingTimers = this.pendingTimerCount();
    out.resumeAttempts = this.snap.resumeAttempts;
    out.pendingDelayedSfx = this.snap.pendingDelayedSfx;
    out.sfxDuringVoicePolicy = this.config.sfxDuringVoicePolicy;
    return out;
  }

  isVoiceAvailable(): boolean {
    return this.voice.isAvailable();
  }

  startMusic(): void {
    if (this.snap.disposed || !this.config.musicEnabled) {
      return;
    }
    this.music.setVolume(this.config.musicVolume * this.config.masterVolume);
    this.snap.musicVolume = this.config.musicVolume;
    this.music.startLoop();
    this.emit(AudioLabEvent.StartMusic);
  }

  stopMusic(): void {
    if (this.snap.disposed) {
      return;
    }
    this.music.stop();
    this.emit(AudioLabEvent.StopMusic);
  }

  lowerMusicForVoice(): void {
    this.lowerMusicVolume('voice');
  }

  lowerMusicTemporarily(reason: string, durationMs: number): void {
    if (this.snap.disposed || !this.config.musicEnabled) {
      return;
    }
    this.lowerMusicVolume(reason);
    this.clearMusicRestoreTimer();
    this.musicRestoreTimer = this.timer.setTimeout((): void => {
      this.musicRestoreTimer = -1;
      if (!this.snap.voiceActive) {
        this.restoreMusicVolume(reason);
      }
    }, durationMs);
  }

  restoreMusicVolume(reason: string): void {
    if (this.snap.disposed || !this.config.musicEnabled) {
      return;
    }
    this.music.setVolume(this.config.musicVolume * this.config.masterVolume);
    this.snap.musicVolume = this.config.musicVolume;
    this.emit(AudioLabEvent.RestoreMusic, reason);
  }

  resumeMusicOnce(reason: string): void {
    if (this.snap.disposed || !this.config.musicEnabled) {
      return;
    }
    this.snap.resumeAttempts += 1;
    this.music.resumeOnce();
    this.emit(AudioLabEvent.ResumeMusicOnce, reason);
  }

  playNormalAttack(): void {
    this.playSfx(KEY_HIT_NORMAL, false, AudioLabEvent.NormalAttack);
  }

  playComboAttack(): void {
    if (!this.config.sfxEnabled) {
      return;
    }
    this.lowerMusicTemporarily('combo', this.config.comboLowerDurationMs);
    this.playSfx(KEY_HIT_CRIT, false, AudioLabEvent.ComboAttack);
  }

  playWrongAnswer(): void {
    this.playSfx(KEY_ANSWER_WRONG, false, AudioLabEvent.WrongAnswer);
  }

  playPlayerHurt(): void {
    this.playSfx(KEY_PLAYER_HURT, true, AudioLabEvent.PlayerHurt);
  }

  playMonsterDefeat(): void {
    this.playSfx(KEY_MONSTER_DEFEAT, true, AudioLabEvent.MonsterDefeat);
  }

  playVictory(): void {
    this.playSfx(KEY_VICTORY, true, AudioLabEvent.Victory);
  }

  playDefeat(): void {
    this.playSfx(KEY_DEFEAT, true, AudioLabEvent.Defeat);
  }

  speakWord(word: string): void {
    if (this.snap.disposed || !this.config.voiceEnabled) {
      return;
    }
    const trimmed: string = word.trim();
    if (trimmed.length === 0 || !this.voice.isAvailable()) {
      return;
    }
    this.voiceToken += 1;
    const token: number = this.voiceToken;
    this.snap.voiceActive = true;
    this.lowerMusicForVoice();
    this.voice.speak(trimmed);
    this.emit(AudioLabEvent.SpeakWord, trimmed);
    this.clearVoiceTimer();
    this.voiceTimer = this.timer.setTimeout((): void => {
      this.finishVoice(token);
    }, this.config.voiceLowerDurationMs);
  }

  demoSpeakOverMusic(word: string): void {
    this.startMusic();
    this.speakWord(word);
  }

  demoComboOverMusic(): void {
    this.startMusic();
    this.playComboAttack();
  }

  demoWrongAnswerSequence(): void {
    this.playWrongAnswer();
    this.playPlayerHurt();
  }

  demoVictorySequence(): void {
    this.playVictory();
  }

  demoSfxDuringVoice(word: string): void {
    this.startMusic();
    this.speakWord(word);
    this.playNormalAttack();
    this.playComboAttack();
    this.playPlayerHurt();
  }

  private finishVoice(token: number): void {
    if (this.snap.disposed || token !== this.voiceToken) {
      return;
    }
    this.voiceTimer = -1;
    this.snap.voiceActive = false;
    this.restoreMusicVolume('voice-timeout');
    if (this.config.sfxDuringVoicePolicy === SfxDuringVoicePolicy.DelayUntilVoiceEnds
      && this.snap.pendingDelayedSfx.length > 0) {
      const delayed: string = this.snap.pendingDelayedSfx;
      this.snap.pendingDelayedSfx = '';
      this.sfx.play(delayed, this.config.sfxVolume * this.config.masterVolume);
      this.emit(AudioLabEvent.SfxDelayedPlayed, delayed);
    }
    if (this.config.resumeMusicAfterVoice) {
      this.resumeMusicOnce('voice-timeout');
    }
  }

  private playSfx(key: string, critical: boolean, event: AudioLabEvent): void {
    if (this.snap.disposed || !this.config.sfxEnabled) {
      return;
    }
    if (!this.snap.voiceActive) {
      this.sfx.play(key, this.config.sfxVolume * this.config.masterVolume);
      this.emit(event, key);
      return;
    }
    if (this.config.sfxDuringVoicePolicy === SfxDuringVoicePolicy.PlayFull) {
      this.sfx.play(key, this.config.sfxVolume * this.config.masterVolume);
      this.emit(event, key);
      return;
    }
    if (this.config.sfxDuringVoicePolicy === SfxDuringVoicePolicy.LowerVolume) {
      this.sfx.play(key, this.config.sfxDuringVoiceVolume * this.config.masterVolume);
      this.emit(AudioLabEvent.SfxLoweredForVoice, key);
      return;
    }
    if (this.config.sfxDuringVoicePolicy === SfxDuringVoicePolicy.SuppressNonCritical) {
      if (critical) {
        this.sfx.play(key, this.config.sfxDuringVoiceVolume * this.config.masterVolume);
        this.emit(AudioLabEvent.SfxLoweredForVoice, key);
      } else {
        this.emit(AudioLabEvent.SfxSuppressedForVoice, key);
      }
      return;
    }
    if (critical) {
      this.sfx.play(key, this.config.sfxDuringVoiceVolume * this.config.masterVolume);
      this.emit(AudioLabEvent.SfxLoweredForVoice, key);
    } else {
      this.snap.pendingDelayedSfx = key;
      this.emit(AudioLabEvent.SfxDelayedForVoice, key);
    }
  }

  private lowerMusicVolume(reason: string): void {
    if (this.snap.disposed || !this.config.musicEnabled) {
      return;
    }
    this.music.setVolume(this.config.musicLoweredVolume * this.config.masterVolume);
    this.snap.musicVolume = this.config.musicLoweredVolume;
    this.emit(AudioLabEvent.LowerMusic, reason);
  }

  private clearMusicRestoreTimer(): void {
    if (this.musicRestoreTimer >= 0) {
      this.timer.clearTimeout(this.musicRestoreTimer);
      this.musicRestoreTimer = -1;
    }
  }

  private clearVoiceTimer(): void {
    if (this.voiceTimer >= 0) {
      this.timer.clearTimeout(this.voiceTimer);
      this.voiceTimer = -1;
    }
  }

  private pendingTimerCount(): number {
    let count: number = 0;
    if (this.musicRestoreTimer >= 0) {
      count += 1;
    }
    if (this.voiceTimer >= 0) {
      count += 1;
    }
    return count;
  }

  private recordError(context: string, err: Error): void {
    this.snap.lastError = `${context}: ${err.message}`;
    this.emit(AudioLabEvent.Error, this.snap.lastError);
  }

  private emit(event: AudioLabEvent, detail?: string): void {
    this.snap.lastEvent = event;
    if (this.observer !== undefined) {
      try {
        this.observer.onEvent(event, detail);
        this.observer.onSnapshot(this.snapshot());
      } catch (err) {
        console.error(`AudioLabController observer failed: ${JSON.stringify(err as Error)}`);
      }
    }
  }

  private emitSnapshot(): void {
    if (this.observer !== undefined) {
      try {
        this.observer.onSnapshot(this.snapshot());
      } catch (err) {
        console.error(`AudioLabController observer snapshot failed: ${JSON.stringify(err as Error)}`);
      }
    }
  }
}
