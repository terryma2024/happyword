import { describe, it, expect } from '@ohos/hypium';
import { common } from '@kit.AbilityKit';
import {
  AudioLabControllerDeps,
  AudioLabConfig,
  AudioLabTimerDriver,
  MusicLabLane,
  SfxLabLane,
  VoiceLabLane,
} from '../main/ets/audio_lab/AudioLabTypes';
import { GameConfig } from '../main/ets/models/GameConfig';
import {
  BattleAudioMixer,
  battleAudioConfigFromGameConfig,
} from '../main/ets/services/BattleAudioMixer';
import { SoundKeys } from '../main/ets/services/AudioService';

class FakeTimerTask {
  id: number = 0;
  active: boolean = true;
  cb: () => void = (): void => {};
}

class FakeTimer implements AudioLabTimerDriver {
  nextId: number = 1;
  tasks: FakeTimerTask[] = [];

  setTimeout(cb: () => void, _ms: number): number {
    const task: FakeTimerTask = new FakeTimerTask();
    task.id = this.nextId;
    this.nextId += 1;
    task.cb = cb;
    this.tasks.push(task);
    return task.id;
  }

  clearTimeout(id: number): void {
    for (let i: number = 0; i < this.tasks.length; i++) {
      if (this.tasks[i].id === id) {
        this.tasks[i].active = false;
      }
    }
  }

  runLatest(): void {
    for (let i: number = this.tasks.length - 1; i >= 0; i--) {
      if (this.tasks[i].active) {
        this.tasks[i].active = false;
        this.tasks[i].cb();
        return;
      }
    }
  }
}

class FakeMusicLane implements MusicLabLane {
  starts: number = 0;
  stops: number = 0;
  volumes: number[] = [];

  preload(_ctx: common.UIAbilityContext, _rawPath: string): Promise<void> {
    return Promise.resolve();
  }

  startLoop(): void {
    this.starts += 1;
  }

  stop(): void {
    this.stops += 1;
  }

  setVolume(value: number): void {
    this.volumes.push(value);
  }

  resumeOnce(): void {}

  state(): string {
    return this.starts > this.stops ? 'playing' : 'ready';
  }

  dispose(): Promise<void> {
    return Promise.resolve();
  }
}

class FakeSfxLane implements SfxLabLane {
  plays: string[] = [];
  volumes: number[] = [];

  preload(_ctx: common.UIAbilityContext, _keys: string[]): Promise<void> {
    return Promise.resolve();
  }

  play(key: string, volume?: number): void {
    this.plays.push(key);
    this.volumes.push(volume !== undefined ? volume : -1);
  }

  dispose(): Promise<void> {
    return Promise.resolve();
  }
}

class FakeVoiceLane implements VoiceLabLane {
  spoken: string[] = [];
  available: boolean = true;

  init(): Promise<void> {
    return Promise.resolve();
  }

  speak(word: string): void {
    this.spoken.push(word);
  }

  isAvailable(): boolean {
    return this.available;
  }

  dispose(): void {}
}

class MixerRig {
  music: FakeMusicLane = new FakeMusicLane();
  sfx: FakeSfxLane = new FakeSfxLane();
  voice: FakeVoiceLane = new FakeVoiceLane();
  timer: FakeTimer = new FakeTimer();
  mixer: BattleAudioMixer;

  constructor() {
    const deps: AudioLabControllerDeps = new AudioLabControllerDeps();
    deps.music = this.music;
    deps.sfx = this.sfx;
    deps.voice = this.voice;
    deps.timer = this.timer;
    this.mixer = new BattleAudioMixer(deps);
  }
}

export default function battleAudioMixerTest(): void {
  describe('BattleAudioMixer', () => {
    it('mapsGameConfigToPcmAudioPolicyDefaults', 0, () => {
      const cfg: GameConfig = new GameConfig();
      const audio: AudioLabConfig = battleAudioConfigFromGameConfig(cfg);

      expect(audio.voiceEnabled).assertTrue();
      expect(audio.musicEnabled).assertFalse();
      expect(audio.sfxEnabled).assertTrue();
    });

    it('startsBgmOnlyWhenConfigEnablesIt', 0, async () => {
      const rig: MixerRig = new MixerRig();
      const cfg: GameConfig = new GameConfig();

      await rig.mixer.enter({} as common.UIAbilityContext, cfg);
      expect(rig.music.starts).assertEqual(0);

      cfg.playBgm = true;
      await rig.mixer.enter({} as common.UIAbilityContext, cfg);
      expect(rig.music.starts).assertEqual(1);
    });

    it('actionSfxSwitchSuppressesBattleSfx', 0, () => {
      const rig: MixerRig = new MixerRig();
      const cfg: GameConfig = new GameConfig();
      cfg.actionSfx = false;
      rig.mixer.updateFromGameConfig(cfg);

      rig.mixer.play(SoundKeys.HIT_NORMAL);

      expect(rig.sfx.plays.length).assertEqual(0);
    });

    it('mutedActionSfxDoesNotDuckBgmForCombo', 0, () => {
      const rig: MixerRig = new MixerRig();
      const cfg: GameConfig = new GameConfig();
      cfg.playBgm = true;
      cfg.actionSfx = false;
      rig.mixer.updateFromGameConfig(cfg);

      rig.mixer.play(SoundKeys.HIT_CRIT);

      expect(rig.sfx.plays.length).assertEqual(0);
      expect(rig.music.volumes.length).assertEqual(0);
    });

    it('speaksThroughPcmVoiceAndRestoresLoweredBgm', 0, () => {
      const rig: MixerRig = new MixerRig();
      const cfg: GameConfig = new GameConfig();
      cfg.playBgm = true;
      rig.mixer.updateFromGameConfig(cfg);

      rig.mixer.speakWord('apple');
      expect(rig.voice.spoken[0]).assertEqual('apple');
      expect(rig.music.volumes[0]).assertEqual(0.08);

      rig.timer.runLatest();
      expect(rig.music.volumes[1]).assertEqual(0.32);
    });
  });
}
