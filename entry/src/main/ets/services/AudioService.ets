import media from '@ohos.multimedia.media';
import { BusinessError } from '@ohos.base';
import { common } from '@kit.AbilityKit';

/**
 * AudioService — lightweight SFX façade for BattlePage (spec §4.3, §7.3).
 *
 * One preloaded {@link media.AVPlayer} per SFX key. Every key is loaded
 * off a bundled OGG under `entry/src/main/resources/rawfile/sound/`;
 * playback on a hot player does a `seek(0) -> play()` so rapid-fire
 * taps replay from the start instead of queueing up.
 *
 * Error model:
 *   - `preload(ctx, keys)` never throws — per-key failures (missing
 *     asset, AVPlayer init error) are logged and the key is marked
 *     muted. Subsequent `play(key)` on a muted key is a no-op so one
 *     broken asset can't wedge the whole battle.
 *   - `play(key)` with an unknown key is a no-op + warn log. This keeps
 *     BattlePage free of defensive guards for keys it knows it loaded.
 *   - `dispose()` releases every AVPlayer and marks the service unusable.
 *
 * V0.3.5: replaced `sound/hit_crit.ogg` with an explosion-style sample.
 */

/**
 * Stable SFX keys. Keep the set small and explicit — every new key
 * requires a bundled asset and a BattlePage call site.
 *
 * Using a namespace + string-union-like const object (rather than a
 * TypeScript enum) because ArkTS strict mode rejects `const enum` and
 * plain string enums at module scope can't be used as literal types
 * by downstream services cleanly.
 */
export class SoundKeys {
  static readonly HIT_NORMAL: string = 'hit_normal';
  static readonly HIT_CRIT: string = 'hit_crit';
  static readonly ANSWER_WRONG: string = 'answer_wrong';
  /**
   * V0.4.8: short male grunt cue layered on top of ANSWER_WRONG when
   * the monster's counter-attack lands, so the projectile arrival has
   * a softer voice signal in addition to the buzzer.
   */
  static readonly PLAYER_HURT: string = 'player_hurt';
  static readonly MONSTER_DEFEAT: string = 'monster_defeat';
  static readonly VICTORY: string = 'victory';
  static readonly DEFEAT: string = 'defeat';
}

/**
 * Map of SFX key -> rawfile path (relative to `resources/rawfile/`).
 * Duplicated here rather than derived from SoundKeys so the asset
 * path stays explicit and greppable; any renamed OGG requires touching
 * this table.
 */
const SOUND_RAW_PATHS: Record<string, string> = {
  'hit_normal': 'sound/hit_normal.ogg',
  'hit_crit': 'sound/hit_crit.ogg',
  'answer_wrong': 'sound/answer_wrong.ogg',
  'player_hurt': 'sound/player_hurt.ogg',
  'monster_defeat': 'sound/monster_defeat.ogg',
  'victory': 'sound/victory.ogg',
  'defeat': 'sound/defeat.ogg',
};

/**
 * Factory signature used by {@link AudioService} to obtain an AVPlayer.
 * Real callers use `media.createAVPlayer`; unit tests inject a stub so
 * they can assert key dispatch without touching native audio.
 */
export type AVPlayerFactory = () => Promise<media.AVPlayer>;

const DEFAULT_FACTORY: AVPlayerFactory = (): Promise<media.AVPlayer> => media.createAVPlayer();

class PlayerSlot {
  player?: media.AVPlayer;
  /** True when we gave up on this key — play() becomes a no-op. */
  muted: boolean = false;
  /** True once AVPlayer.state === 'prepared' (or later). */
  ready: boolean = false;
}

export class AudioService {
  private readonly factory: AVPlayerFactory;
  private readonly slots: Map<string, PlayerSlot> = new Map<string, PlayerSlot>();
  private disposed: boolean = false;

  constructor(factory?: AVPlayerFactory) {
    this.factory = factory !== undefined ? factory : DEFAULT_FACTORY;
  }

  /**
   * Preload every supplied key. Resolves once all per-key attempts have
   * settled (successes become playable; failures become silently muted).
   * Idempotent — calling preload twice for the same key reuses the
   * existing slot, so BattlePage can call it unconditionally from
   * `aboutToAppear`.
   */
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
      const slot: PlayerSlot = new PlayerSlot();
      this.slots.set(key, slot);
      tasks.push(this.loadOne(ctx, key, slot));
    }
    await Promise.all(tasks);
  }

  private async loadOne(ctx: common.UIAbilityContext, key: string, slot: PlayerSlot): Promise<void> {
    const rawPath: string | undefined = SOUND_RAW_PATHS[key];
    if (rawPath === undefined) {
      console.warn(`AudioService: unknown key "${key}", muting.`);
      slot.muted = true;
      return;
    }
    try {
      const raw = await ctx.resourceManager.getRawFd(rawPath);
      const player: media.AVPlayer = await this.factory();
      slot.player = player;

      player.on('error', (err: BusinessError): void => {
        console.error(`AudioService[${key}] AVPlayer error: ${JSON.stringify(err)}`);
        slot.muted = true;
      });
      player.on('stateChange', (state: string): void => {
        if (state === 'initialized') {
          player.prepare().catch((err: BusinessError): void => {
            console.error(`AudioService[${key}] prepare failed: ${JSON.stringify(err)}`);
            slot.muted = true;
          });
        } else if (state === 'prepared') {
          slot.ready = true;
        }
      });

      const fdSrc: media.AVFileDescriptor = {
        fd: raw.fd,
        offset: raw.offset,
        length: raw.length
      };
      player.fdSrc = fdSrc;
    } catch (err) {
      console.error(`AudioService[${key}] preload failed: ${JSON.stringify(err as BusinessError)}`);
      slot.muted = true;
    }
  }

  /**
   * Fire-and-forget playback. Safe to call before `preload` resolves — if
   * the slot isn't `ready` yet, the call is dropped on the floor rather
   * than queued, because the common case (a tap burst during a crit) is
   * ok to drop: the visual feedback is the dominant signal and stacking
   * up stale audio would sound worse than silence.
   */
  play(key: string): void {
    if (this.disposed) {
      return;
    }
    const slot: PlayerSlot | undefined = this.slots.get(key);
    if (slot === undefined) {
      console.warn(`AudioService.play: key "${key}" not preloaded, dropping.`);
      return;
    }
    if (slot.muted || !slot.ready) {
      return;
    }
    const player: media.AVPlayer | undefined = slot.player;
    if (player === undefined) {
      return;
    }
    // On OpenHarmony AVPlayer does not auto-rewind after a completed
    // playback, so seek(0) is required before play() for replays.
    player.seek(0);
    player.play().catch((err: BusinessError): void => {
      console.error(`AudioService[${key}] play failed: ${JSON.stringify(err)}`);
    });
  }

  /** Release every preloaded player. Subsequent play() is a no-op. */
  async dispose(): Promise<void> {
    this.disposed = true;
    const releases: Promise<void>[] = [];
    this.slots.forEach((slot: PlayerSlot): void => {
      const player: media.AVPlayer | undefined = slot.player;
      slot.player = undefined;
      slot.ready = false;
      slot.muted = true;
      if (player !== undefined) {
        releases.push(player.release().catch((err: BusinessError): void => {
          console.error(`AudioService release failed: ${JSON.stringify(err)}`);
        }));
      }
    });
    this.slots.clear();
    await Promise.all(releases);
  }

  /** Test hook: whether a key is currently preloaded, regardless of muted state. */
  hasKey(key: string): boolean {
    return this.slots.has(key);
  }

  /** Test hook: whether a key is preloaded AND not muted. */
  isPlayable(key: string): boolean {
    const slot: PlayerSlot | undefined = this.slots.get(key);
    if (slot === undefined) {
      return false;
    }
    return !slot.muted;
  }
}

/**
 * Full SFX key set used by BattlePage — exported so the page can
 * `service.preload(ctx, ALL_SOUND_KEYS)` without hard-coding the list.
 */
export const ALL_SOUND_KEYS: string[] = [
  SoundKeys.HIT_NORMAL,
  SoundKeys.HIT_CRIT,
  SoundKeys.ANSWER_WRONG,
  SoundKeys.PLAYER_HURT,
  SoundKeys.MONSTER_DEFEAT,
  SoundKeys.VICTORY,
  SoundKeys.DEFEAT,
];
