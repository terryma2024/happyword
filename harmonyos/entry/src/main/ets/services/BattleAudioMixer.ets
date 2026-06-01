import { common } from '@kit.AbilityKit';
import {
  AudioLabConfig,
  AudioLabControllerDeps,
  SfxDuringVoicePolicy,
} from '../audio_lab/AudioLabTypes';
import { AudioLabController } from '../audio_lab/AudioLabController';
import { GameConfig } from '../models/GameConfig';
import { SoundKeys } from './AudioService';

export function battleAudioConfigFromGameConfig(cfg: GameConfig): AudioLabConfig {
  const out: AudioLabConfig = new AudioLabConfig();
  out.voiceEnabled = true;
  out.musicEnabled = cfg.playBgm;
  out.sfxEnabled = cfg.actionSfx;
  out.musicVolume = 0.32;
  out.musicLoweredVolume = 0.5;
  out.sfxDuringVoicePolicy = SfxDuringVoicePolicy.LowerVolume;
  out.sfxDuringVoiceVolume = 0.35;
  out.resumeMusicAfterVoice = false;
  return out;
}

export class BattleAudioMixer {
  private controller: AudioLabController;

  constructor(deps?: AudioLabControllerDeps) {
    this.controller = new AudioLabController(new AudioLabConfig(), undefined, deps);
  }

  async enter(ctx: common.UIAbilityContext, cfg: GameConfig): Promise<void> {
    this.updateFromGameConfig(cfg);
    await this.controller.enter(ctx);
    if (cfg.playBgm) {
      this.controller.startMusic();
    }
  }

  updateFromGameConfig(cfg: GameConfig): void {
    this.controller.updateConfig(battleAudioConfigFromGameConfig(cfg));
  }

  isVoiceAvailable(): boolean {
    return this.controller.isVoiceAvailable();
  }

  speakWord(word: string): void {
    this.controller.speakWord(word);
  }

  play(key: string): void {
    if (key === SoundKeys.HIT_NORMAL) {
      this.controller.playNormalAttack();
    } else if (key === SoundKeys.HIT_CRIT) {
      this.controller.playComboAttack();
    } else if (key === SoundKeys.ANSWER_WRONG) {
      this.controller.playWrongAnswer();
    } else if (key === SoundKeys.PLAYER_HURT) {
      this.controller.playPlayerHurt();
    } else if (key === SoundKeys.MONSTER_DEFEAT) {
      this.controller.playMonsterDefeat();
    } else if (key === SoundKeys.VICTORY) {
      this.controller.playVictory();
    } else if (key === SoundKeys.DEFEAT) {
      this.controller.playDefeat();
    }
  }

  async exit(): Promise<void> {
    await this.controller.exit();
  }
}
