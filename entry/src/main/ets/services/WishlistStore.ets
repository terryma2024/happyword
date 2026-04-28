import preferences from '@ohos.data.preferences';
import { BusinessError } from '@ohos.base';
import { common } from '@kit.AbilityKit';
import {
  MagicWish,
  WishState,
  WishlistSnapshot,
  WISHLIST_PREFS_NAME,
  WISHLIST_PREFS_KEY,
} from '../models/MagicWish';
import { getWishCatalogClone } from '../data/WishlistCatalog';
import { CoinAccount } from './CoinAccount';
import { StringPreferencesLike } from './WrongAnswerStore';

interface MagicWishJson {
  id?: string;
  displayName?: string;
  costCoins?: number;
  iconEmoji?: string;
  state?: string;
  requestedAt?: number;
  confirmedAt?: number;
}

interface WishlistSnapshotJson {
  version?: number;
  wishes?: MagicWishJson[];
}

class RealPrefs implements StringPreferencesLike {
  private readonly handle: preferences.Preferences;
  constructor(handle: preferences.Preferences) {
    this.handle = handle;
  }
  async getString(key: string): Promise<string> {
    const v: preferences.ValueType = await this.handle.get(key, '');
    return typeof v === 'string' ? v : '';
  }
  putString(key: string, value: string): Promise<void> {
    return this.handle.put(key, value);
  }
  flush(): Promise<void> {
    return this.handle.flush();
  }
}

/**
 * Local persistent store for wishes. Mirrors the recorder/coin
 * pattern: in-memory mutations are synchronous, persistence happens
 * via a fire-and-forget putString. Tests inject a Map-backed prefs
 * stand-in via `injectPreferencesForTest`.
 *
 * State machine per wish:
 *   Idle ─request─▶ Pending ─confirmByParent─▶ Confirmed
 *      ◀──acknowledge── Confirmed
 *      ◀──cancel─── Pending
 *
 * `confirmByParent` invokes `CoinAccount.redeem` and only advances
 * state when the redeem succeeds.
 */
export class WishlistStore {
  private prefs?: StringPreferencesLike;
  private snap: WishlistSnapshot = new WishlistSnapshot();
  private ready: boolean = false;

  injectPreferencesForTest(p: StringPreferencesLike): void {
    this.prefs = p;
    this.ready = true;
    if (this.snap.wishes.length === 0) {
      this.snap.wishes = getWishCatalogClone();
    }
  }

  async init(ctx: common.UIAbilityContext): Promise<void> {
    if (this.ready && this.prefs !== undefined) {
      return;
    }
    const real: preferences.Preferences =
      await preferences.getPreferences(ctx, WISHLIST_PREFS_NAME);
    this.prefs = new RealPrefs(real);
    this.ready = true;
    const raw: string = await this.prefs.getString(WISHLIST_PREFS_KEY);
    if (raw.length > 0) {
      this.snap = parseWishlistSnapshot(raw);
    }
    if (this.snap.wishes.length === 0) {
      this.snap.wishes = getWishCatalogClone();
      return;
    }
    // Backfill any wishes added to catalog after the user last
    // wrote a snapshot. Keeps existing requestedAt/confirmedAt
    // intact for already-known wishes.
    const seen: Set<string> = new Set<string>();
    for (let i = 0; i < this.snap.wishes.length; i++) {
      seen.add(this.snap.wishes[i].id);
    }
    const additions: MagicWish[] = getWishCatalogClone();
    for (let i = 0; i < additions.length; i++) {
      if (!seen.has(additions[i].id)) {
        this.snap.wishes.push(additions[i]);
      }
    }
  }

  list(): MagicWish[] {
    const out: MagicWish[] = [];
    for (let i = 0; i < this.snap.wishes.length; i++) {
      const src: MagicWish = this.snap.wishes[i];
      const c: MagicWish = new MagicWish();
      c.id = src.id;
      c.displayName = src.displayName;
      c.costCoins = src.costCoins;
      c.iconEmoji = src.iconEmoji;
      c.state = src.state;
      c.requestedAt = src.requestedAt;
      c.confirmedAt = src.confirmedAt;
      out.push(c);
    }
    return out;
  }

  request(wishId: string, account: CoinAccount, nowMs: number): boolean {
    const w: MagicWish | undefined = this.findWish(wishId);
    if (w === undefined) {
      return false;
    }
    if (w.state !== WishState.Idle) {
      return false;
    }
    if (account.balance() < w.costCoins) {
      return false;
    }
    w.state = WishState.Pending;
    w.requestedAt = nowMs;
    this.scheduleSave();
    return true;
  }

  confirmByParent(wishId: string, account: CoinAccount, nowMs: number): boolean {
    const w: MagicWish | undefined = this.findWish(wishId);
    if (w === undefined) {
      return false;
    }
    if (w.state !== WishState.Pending) {
      return false;
    }
    const ok: boolean = account.redeem(w.id, w.costCoins);
    if (!ok) {
      return false;
    }
    w.state = WishState.Confirmed;
    w.confirmedAt = nowMs;
    this.scheduleSave();
    return true;
  }

  cancel(wishId: string): void {
    const w: MagicWish | undefined = this.findWish(wishId);
    if (w === undefined) {
      return;
    }
    if (w.state === WishState.Pending) {
      w.state = WishState.Idle;
      w.requestedAt = 0;
      this.scheduleSave();
    }
  }

  acknowledge(wishId: string): void {
    const w: MagicWish | undefined = this.findWish(wishId);
    if (w === undefined) {
      return;
    }
    if (w.state === WishState.Confirmed) {
      w.state = WishState.Idle;
      w.requestedAt = 0;
      w.confirmedAt = 0;
      this.scheduleSave();
    }
  }

  async flushNow(): Promise<void> {
    if (!this.ready || this.prefs === undefined) {
      return;
    }
    await this.prefs.putString(WISHLIST_PREFS_KEY, JSON.stringify(this.snap));
    await this.prefs.flush();
  }

  private findWish(wishId: string): MagicWish | undefined {
    for (let i = 0; i < this.snap.wishes.length; i++) {
      if (this.snap.wishes[i].id === wishId) {
        return this.snap.wishes[i];
      }
    }
    return undefined;
  }

  private scheduleSave(): void {
    if (!this.ready || this.prefs === undefined) {
      return;
    }
    this.prefs.putString(WISHLIST_PREFS_KEY, JSON.stringify(this.snap))
      .catch((err: BusinessError): void => {
        console.error(`WishlistStore save failed: ${JSON.stringify(err)}`);
      });
  }
}

export function parseWishlistSnapshot(raw: string): WishlistSnapshot {
  const out: WishlistSnapshot = new WishlistSnapshot();
  if (raw.length === 0) {
    return out;
  }
  let parsed: WishlistSnapshotJson;
  try {
    parsed = JSON.parse(raw) as WishlistSnapshotJson;
  } catch (err) {
    console.error(`parseWishlistSnapshot failed: ${JSON.stringify(err as BusinessError)}`);
    return out;
  }
  if (parsed === null || parsed === undefined) {
    return out;
  }
  if (typeof parsed.version === 'number') {
    out.version = parsed.version;
  }
  const xs: MagicWishJson[] | undefined = parsed.wishes;
  if (xs !== undefined && xs !== null) {
    for (let i = 0; i < xs.length; i++) {
      const j: MagicWishJson = xs[i];
      const w: MagicWish = new MagicWish();
      w.id = typeof j.id === 'string' ? j.id : '';
      w.displayName = typeof j.displayName === 'string' ? j.displayName : '';
      w.costCoins = typeof j.costCoins === 'number' ? j.costCoins : 0;
      w.iconEmoji = typeof j.iconEmoji === 'string' ? j.iconEmoji : '';
      w.state = coerceState(typeof j.state === 'string' ? j.state : '');
      w.requestedAt = typeof j.requestedAt === 'number' ? j.requestedAt : 0;
      w.confirmedAt = typeof j.confirmedAt === 'number' ? j.confirmedAt : 0;
      if (w.id.length > 0) {
        out.wishes.push(w);
      }
    }
  }
  return out;
}

function coerceState(label: string): WishState {
  if (label === WishState.Pending) return WishState.Pending;
  if (label === WishState.Confirmed) return WishState.Confirmed;
  return WishState.Idle;
}

let globalStore: WishlistStore | undefined = undefined;

export function getWishlistStore(): WishlistStore {
  if (globalStore === undefined) {
    globalStore = new WishlistStore();
  }
  return globalStore;
}

export function __resetWishlistStoreForTest(): void {
  globalStore = undefined;
}
