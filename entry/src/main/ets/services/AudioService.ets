import media from '@ohos.multimedia.media';
import audio from '@ohos.multimedia.audio';
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
  /**
   * V0.4.8 follow-up: looping battle background music. Driven through
   * the dedicated {@link AudioService.playLoop} / {@link AudioService.stopLoop}
   * pair (instead of {@link AudioService.play}) so SFX and BGM share
   * the same preload + dispose lifecycle without colliding on
   * `seek(0)` rewinds.
   */
  static readonly BGM_FIGHT: string = 'bgm_fight';
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
  'bgm_fight': 'sound/bgm_fight.ogg',
};

/**
 * Volume applied to looping BGM tracks. Keeps the music a measurable
 * step below SFX (≈ −9 dB) so victory/defeat cues stay legible without
 * needing a per-call duck. When V0.6 introduces the parental settings
 * panel this becomes a slider and the constant is gone.
 */
const BGM_VOLUME: number = 0.35;

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
  /**
   * Loop-mode bookkeeping (V0.4.8 follow-up).
   *
   * `started` is set the first time a `playLoop` actually kicks off
   * playback, and reset by `stopLoop` so a subsequent `playLoop` after
   * a battle re-entry can replay from the top. It also makes
   * `playLoop` idempotent — repeated calls during a single battle
   * don't seek the running BGM back to zero.
   *
   * `wantsLoop` covers the early-call case: `BattlePage.aboutToAppear`
   * fires `playLoop` immediately after `preload`, but the underlying
   * AVPlayer is still racing through `initialized -> prepared`. We
   * stash the intent here and let the `prepared` callback honour it.
   */
  started: boolean = false;
  wantsLoop: boolean = false;
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
          // V0.4.8 follow-up: configure stream type + interrupt mode
          // BEFORE prepare() so the BGM AVPlayer doesn't grab exclusive
          // audio focus and silence the SFX players (the default
          // SHARE_MODE causes a "latest play wins" race that made the
          // BGM cut out the moment the user tapped an answer).
          //   - audioRendererInfo must be set in 'initialized' state.
          //   - audioInterruptMode is also valid here.
          // The BGM uses MUSIC, SFX use GAME — both of these stream
          // types coexist with system focus rules; the per-player
          // INDEPENDENT_MODE further disables the in-app same-stream
          // mutual interruption.
          try {
            player.audioInterruptMode = audio.InterruptMode.INDEPENDENT_MODE;
            player.audioRendererInfo = {
              usage: key === SoundKeys.BGM_FIGHT
                ? audio.StreamUsage.STREAM_USAGE_MUSIC
                : audio.StreamUsage.STREAM_USAGE_GAME,
              rendererFlags: 0
            };
          } catch (cfgErr) {
            console.error(`AudioService[${key}] audio focus config failed: ${JSON.stringify(cfgErr as BusinessError)}`);
          }
          player.prepare().catch((err: BusinessError): void => {
            console.error(`AudioService[${key}] prepare failed: ${JSON.stringify(err)}`);
            slot.muted = true;
          });
        } else if (state === 'prepared') {
          slot.ready = true;
          // V0.4.8: BGM key gets loop + reduced volume baked in once,
          // and any queued playLoop() request is honoured here so the
          // page lifecycle hook doesn't have to await `prepared`.
          if (key === SoundKeys.BGM_FIGHT) {
            try {
              player.loop = true;
              player.setVolume(BGM_VOLUME);
            } catch (err) {
              console.error(`AudioService[${key}] loop/volume init failed: ${JSON.stringify(err as BusinessError)}`);
            }
            if (slot.wantsLoop && !slot.started) {
              slot.wantsLoop = false;
              slot.started = true;
              player.play().catch((err: BusinessError): void => {
                console.error(`AudioService[${key}] deferred loop play failed: ${JSON.stringify(err)}`);
                slot.started = false;
              });
            }
          }
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

  /**
   * Start (or re-start) a long-running loop for `key`. Idempotent — a
   * second call while playback is already active is a no-op rather
   * than a `seek(0)` that would cut the BGM back to the top. Safe to
   * call before `preload` resolves: the request is queued via
   * `wantsLoop` and the `prepared` state callback will honour it.
   *
   * Used by BattlePage.aboutToAppear for `bgm_fight`. Not appropriate
   * for one-shot SFX — those still go through `play()`.
   */
  playLoop(key: string): void {
    if (this.disposed) {
      return;
    }
    const slot: PlayerSlot | undefined = this.slots.get(key);
    if (slot === undefined) {
      console.warn(`AudioService.playLoop: key "${key}" not preloaded, dropping.`);
      return;
    }
    if (slot.muted) {
      return;
    }
    if (!slot.ready) {
      slot.wantsLoop = true;
      return;
    }
    if (slot.started) {
      return;
    }
    const player: media.AVPlayer | undefined = slot.player;
    if (player === undefined) {
      return;
    }
    try {
      player.loop = true;
      player.setVolume(BGM_VOLUME);
    } catch (err) {
      console.error(`AudioService.playLoop[${key}] loop/volume failed: ${JSON.stringify(err as BusinessError)}`);
    }
    slot.started = true;
    player.play().catch((err: BusinessError): void => {
      console.error(`AudioService.playLoop[${key}] play failed: ${JSON.stringify(err)}`);
      slot.started = false;
    });
  }

  /**
   * Pause a loop previously started by `playLoop`. Releases nothing —
   * the AVPlayer stays prepared so a later `playLoop` (e.g. on the
   * next battle) can resume without a new fdSrc. Use `dispose()` for
   * actual teardown.
   */
  stopLoop(key: string): void {
    const slot: PlayerSlot | undefined = this.slots.get(key);
    if (slot === undefined) {
      return;
    }
    slot.wantsLoop = false;
    if (!slot.started) {
      return;
    }
    slot.started = false;
    const player: media.AVPlayer | undefined = slot.player;
    if (player === undefined) {
      return;
    }
    player.pause().catch((err: BusinessError): void => {
      console.error(`AudioService.stopLoop[${key}] pause failed: ${JSON.stringify(err)}`);
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
  SoundKeys.BGM_FIGHT,
];
