import media from '@ohos.multimedia.media';
import audio from '@ohos.multimedia.audio';
import { BusinessError } from '@ohos.base';
import { common } from '@kit.AbilityKit';
import { MusicLabLane } from '../AudioLabTypes';

export class RealMusicLabLane implements MusicLabLane {
  private player?: media.AVPlayer;
  private ready: boolean = false;
  private muted: boolean = false;
  private currentState: string = 'idle';
  private currentVolume: number = 0.32;
  private wantsLoop: boolean = false;

  async preload(ctx: common.UIAbilityContext, rawPath: string): Promise<void> {
    if (this.player !== undefined) {
      return;
    }
    try {
      const raw = await ctx.resourceManager.getRawFd(rawPath);
      const player: media.AVPlayer = await media.createAVPlayer();
      this.player = player;
      player.audioInterruptMode = audio.InterruptMode.SHARE_MODE;
      player.on('error', (err: BusinessError): void => {
        this.currentState = 'error';
        this.muted = true;
        console.error(`RealMusicLabLane error: ${JSON.stringify(err)}`);
      });
      player.on('audioInterrupt', (info: audio.InterruptEvent): void => {
        console.info(`RealMusicLabLane interrupt: ${JSON.stringify(info)}`);
        if (info.eventType === audio.InterruptType.INTERRUPT_TYPE_END
          && info.hintType === audio.InterruptHint.INTERRUPT_HINT_RESUME
          && this.wantsLoop) {
          this.startLoop();
        }
      });
      player.on('stateChange', (state: string): void => {
        this.currentState = state;
        if (state === 'initialized') {
          player.prepare().catch((err: BusinessError): void => {
            this.muted = true;
            console.error(`RealMusicLabLane prepare failed: ${JSON.stringify(err)}`);
          });
        } else if (state === 'prepared') {
          this.ready = true;
          player.loop = true;
          player.setVolume(this.currentVolume);
          if (this.wantsLoop) {
            this.playPrepared(player);
          }
        }
      });
      player.fdSrc = {
        fd: raw.fd,
        offset: raw.offset,
        length: raw.length,
      };
    } catch (err) {
      this.currentState = 'error';
      this.muted = true;
      console.error(`RealMusicLabLane preload failed: ${JSON.stringify(err as BusinessError)}`);
    }
  }

  startLoop(): void {
    this.wantsLoop = true;
    if (this.muted || !this.ready || this.player === undefined) {
      return;
    }
    this.currentState = 'playing';
    this.player.loop = true;
    this.player.setVolume(this.currentVolume);
    this.playPrepared(this.player);
  }

  stop(): void {
    this.wantsLoop = false;
    if (this.currentState === 'playing') {
      this.currentState = 'paused';
    }
    if (this.player === undefined) {
      return;
    }
    this.player.pause().catch((err: BusinessError): void => {
      console.error(`RealMusicLabLane pause failed: ${JSON.stringify(err)}`);
    });
  }

  setVolume(value: number): void {
    this.currentVolume = Math.max(0, Math.min(1, value));
    if (this.player !== undefined) {
      this.player.setVolume(this.currentVolume);
    }
  }

  resumeOnce(): void {
    if (this.wantsLoop) {
      this.startLoop();
    }
  }

  state(): string {
    return this.currentState;
  }

  async dispose(): Promise<void> {
    const player: media.AVPlayer | undefined = this.player;
    this.player = undefined;
    this.ready = false;
    this.muted = true;
    this.wantsLoop = false;
    this.currentState = 'released';
    if (player !== undefined) {
      await player.release().catch((err: BusinessError): void => {
        console.error(`RealMusicLabLane release failed: ${JSON.stringify(err)}`);
      });
    }
  }

  private playPrepared(player: media.AVPlayer): void {
    player.play().catch((err: BusinessError): void => {
      console.error(`RealMusicLabLane play failed: ${JSON.stringify(err)}`);
    });
  }
}
