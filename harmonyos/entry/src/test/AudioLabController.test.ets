import { describe, it, expect } from '@ohos/hypium';
import { common } from '@kit.AbilityKit';
import { AudioLabController } from '../main/ets/audio_lab/AudioLabController';
import {
  AudioLabConfig,
  AudioLabControllerDeps,
  AudioLabTimerDriver,
  MusicLabLane,
  SfxDuringVoicePolicy,
  SfxLabLane,
  VoiceLabLane,
} from '../main/ets/audio_lab/AudioLabTypes';

class FakeTimerTask {
  id: number = 0;
  ms: number = 0;
  active: boolean = true;
  cb: () => void = (): void => {};
}

class FakeTimer implements AudioLabTimerDriver {
  nextId: number = 1;
  tasks: FakeTimerTask[] = [];

  setTimeout(cb: () => void, ms: number): number {
    const t: FakeTimerTask = new FakeTimerTask();
    t.id = this.nextId;
    this.nextId += 1;
    t.ms = ms;
    t.cb = cb;
    this.tasks.push(t);
    return t.id;
  }

  clearTimeout(id: number): void {
    for (let i = 0; i < this.tasks.length; i++) {
      if (this.tasks[i].id === id) {
        this.tasks[i].active = false;
      }
    }
  }

  activeCount(): number {
    let count: number = 0;
    for (let i = 0; i < this.tasks.length; i++) {
      if (this.tasks[i].active) {
        count += 1;
      }
    }
    return count;
  }

  runLatest(): void {
    for (let i = this.tasks.length - 1; i >= 0; i--) {
      if (this.tasks[i].active) {
        this.tasks[i].active = false;
        this.tasks[i].cb();
        return;
      }
    }
  }
}

class FakeMusicLane implements MusicLabLane {
  preloadedPath: string = '';
  started: number = 0;
  stopped: number = 0;
  disposed: number = 0;
  volumes: number[] = [];
  resumes: number = 0;

  preload(_ctx: common.UIAbilityContext, rawPath: string): Promise<void> {
    this.preloadedPath = rawPath;
    return Promise.resolve();
  }

  startLoop(): void {
    this.started += 1;
  }

  stop(): void {
    this.stopped += 1;
  }

  setVolume(value: number): void {
    this.volumes.push(value);
  }

  resumeOnce(): void {
    this.resumes += 1;
  }

  state(): string {
    return this.started > this.stopped ? 'playing' : 'ready';
  }

  dispose(): Promise<void> {
    this.disposed += 1;
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
  disposed: number = 0;

  init(): Promise<void> {
    return Promise.resolve();
  }

  speak(word: string): void {
    this.spoken.push(word);
  }

  isAvailable(): boolean {
    return this.available;
  }

  dispose(): void {
    this.disposed += 1;
  }
}

class TestRig {
  music: FakeMusicLane = new FakeMusicLane();
  sfx: FakeSfxLane = new FakeSfxLane();
  voice: FakeVoiceLane = new FakeVoiceLane();
  timer: FakeTimer = new FakeTimer();
  controller: AudioLabController;

  constructor(config?: AudioLabConfig) {
    const deps: AudioLabControllerDeps = new AudioLabControllerDeps();
    deps.music = this.music;
    deps.sfx = this.sfx;
    deps.voice = this.voice;
    deps.timer = this.timer;
    this.controller = new AudioLabController(config, undefined, deps);
  }
}

export default function audioLabControllerTest(): void {
  describe('AudioLabController', () => {
    it('speakWordLowersMusicThenRestoresOnTimeout', 0, () => {
      const rig: TestRig = new TestRig();

      rig.controller.speakWord('apple');
      expect(rig.voice.spoken[0]).assertEqual('apple');
      expect(rig.music.volumes[0]).assertEqual(0.08);
      expect(rig.controller.snapshot().voiceActive).assertTrue();

      rig.timer.runLatest();
      expect(rig.music.volumes[1]).assertEqual(0.32);
      expect(rig.controller.snapshot().voiceActive).assertFalse();
    });

    it('lowerVolumePolicyPlaysSfxAtReducedVolumeDuringVoice', 0, () => {
      const rig: TestRig = new TestRig();

      rig.controller.speakWord('apple');
      rig.controller.playComboAttack();

      expect(rig.sfx.plays[0]).assertEqual('hit_crit');
      expect(rig.sfx.volumes[0]).assertEqual(0.35);
    });

    it('suppressPolicyDropsNonCriticalAndAllowsCritical', 0, () => {
      const cfg: AudioLabConfig = new AudioLabConfig();
      cfg.sfxDuringVoicePolicy = SfxDuringVoicePolicy.SuppressNonCritical;
      const rig: TestRig = new TestRig(cfg);

      rig.controller.speakWord('apple');
      rig.controller.playNormalAttack();
      rig.controller.playPlayerHurt();

      expect(rig.sfx.plays.length).assertEqual(1);
      expect(rig.sfx.plays[0]).assertEqual('player_hurt');
      expect(rig.sfx.volumes[0]).assertEqual(0.35);
    });

    it('delayPolicyKeepsOnlyLatestNonCriticalSfx', 0, () => {
      const cfg: AudioLabConfig = new AudioLabConfig();
      cfg.sfxDuringVoicePolicy = SfxDuringVoicePolicy.DelayUntilVoiceEnds;
      const rig: TestRig = new TestRig(cfg);

      rig.controller.speakWord('apple');
      rig.controller.playNormalAttack();
      rig.controller.playComboAttack();
      expect(rig.sfx.plays.length).assertEqual(0);
      expect(rig.controller.snapshot().pendingDelayedSfx).assertEqual('hit_crit');

      rig.timer.runLatest();
      expect(rig.sfx.plays.length).assertEqual(1);
      expect(rig.sfx.plays[0]).assertEqual('hit_crit');
      expect(rig.controller.snapshot().pendingDelayedSfx).assertEqual('');
    });

    it('resumeAfterVoiceCallsResumeOnceOnlyWhenEnabled', 0, () => {
      const cfg: AudioLabConfig = new AudioLabConfig();
      cfg.resumeMusicAfterVoice = true;
      const rig: TestRig = new TestRig(cfg);

      rig.controller.speakWord('apple');
      rig.timer.runLatest();

      expect(rig.music.resumes).assertEqual(1);
      expect(rig.controller.snapshot().resumeAttempts).assertEqual(1);
    });

    it('exitClearsPendingTimersAndDisposesLanes', 0, async () => {
      const rig: TestRig = new TestRig();

      rig.controller.speakWord('apple');
      await rig.controller.exit();

      expect(rig.controller.snapshot().disposed).assertTrue();
      expect(rig.timer.activeCount()).assertEqual(0);
      expect(rig.music.disposed).assertEqual(1);
      expect(rig.voice.disposed).assertEqual(1);
    });
  });
}
