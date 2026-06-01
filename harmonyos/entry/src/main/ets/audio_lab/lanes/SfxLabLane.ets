import media from '@ohos.multimedia.media';
import { BusinessError } from '@ohos.base';
import { common } from '@kit.AbilityKit';
import { SfxLabLane } from '../AudioLabTypes';

const SFX_RAW_PATHS: Record<string, string> = {
  'hit_normal': 'sound/hit_normal.ogg',
  'hit_crit': 'sound/hit_crit.ogg',
  'answer_wrong': 'sound/answer_wrong.ogg',
  'player_hurt': 'sound/player_hurt.ogg',
  'monster_defeat': 'sound/monster_defeat.ogg',
  'victory': 'sound/victory.ogg',
  'defeat': 'sound/defeat.ogg',
};

class LabSfxSlot {
  player?: media.AVPlayer;
  ready: boolean = false;
  muted: boolean = false;
}

export class RealSfxLabLane implements SfxLabLane {
  private slots: Map<string, LabSfxSlot> = new Map<string, LabSfxSlot>();
  private disposed: boolean = false;

  async preload(ctx: common.UIAbilityContext, keys: string[]): Promise<void> {
    if (this.disposed) {
      return;
    }
    const tasks: Promise<void>[] = [];
    for (let i = 0; i < keys.length; i++) {
      const key: string = keys[i];
      if (this.slots.has(key)) {
        continue;
      }
      const slot: LabSfxSlot = new LabSfxSlot();
      this.slots.set(key, slot);
      tasks.push(this.loadOne(ctx, key, slot));
    }
    await Promise.all(tasks);
  }

  play(key: string, volume?: number): void {
    if (this.disposed) {
      return;
    }
    const slot: LabSfxSlot | undefined = this.slots.get(key);
    if (slot === undefined || slot.muted || !slot.ready || slot.player === undefined) {
      return;
    }
    const effective: number = volume !== undefined ? Math.max(0, Math.min(1, volume)) : 1;
    slot.player.setVolume(effective);
    slot.player.seek(0);
    slot.player.play().catch((err: BusinessError): void => {
      console.error(`RealSfxLabLane[${key}] play failed: ${JSON.stringify(err)}`);
    });
  }

  async dispose(): Promise<void> {
    this.disposed = true;
    const releases: Promise<void>[] = [];
    this.slots.forEach((slot: LabSfxSlot): void => {
      const player: media.AVPlayer | undefined = slot.player;
      slot.player = undefined;
      slot.ready = false;
      slot.muted = true;
      if (player !== undefined) {
        releases.push(player.release().catch((err: BusinessError): void => {
          console.error(`RealSfxLabLane release failed: ${JSON.stringify(err)}`);
        }));
      }
    });
    this.slots.clear();
    await Promise.all(releases);
  }

  private async loadOne(ctx: common.UIAbilityContext, key: string, slot: LabSfxSlot): Promise<void> {
    const rawPath: string | undefined = SFX_RAW_PATHS[key];
    if (rawPath === undefined) {
      console.warn(`RealSfxLabLane: unknown key "${key}", muting.`);
      slot.muted = true;
      return;
    }
    try {
      const raw = await ctx.resourceManager.getRawFd(rawPath);
      const player: media.AVPlayer = await media.createAVPlayer();
      slot.player = player;
      player.on('error', (err: BusinessError): void => {
        slot.muted = true;
        console.error(`RealSfxLabLane[${key}] error: ${JSON.stringify(err)}`);
      });
      player.on('stateChange', (state: string): void => {
        if (state === 'initialized') {
          player.prepare().catch((err: BusinessError): void => {
            slot.muted = true;
            console.error(`RealSfxLabLane[${key}] prepare failed: ${JSON.stringify(err)}`);
          });
        } else if (state === 'prepared') {
          slot.ready = true;
        }
      });
      player.fdSrc = {
        fd: raw.fd,
        offset: raw.offset,
        length: raw.length,
      };
    } catch (err) {
      slot.muted = true;
      console.error(`RealSfxLabLane[${key}] preload failed: ${JSON.stringify(err as BusinessError)}`);
    }
  }
}
