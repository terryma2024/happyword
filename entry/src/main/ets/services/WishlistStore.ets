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
  isCustom?: boolean;
}

interface WishlistSnapshotJson {
  version?: number;
  wishes?: MagicWishJson[];
}

/**
 * V0.4.7 — id prefix used to mark wishes the parent created at
 * runtime. `addCustomWish` always generates ids using this prefix
 * (never collides with the closed catalog ids `wish-…`). The
 * `removeCustomWish` guard also requires the wish to have
 * `isCustom === true`, so renaming a catalog wish to start with
 * this prefix wouldn't accidentally make it removable.
 */
const CUSTOM_WISH_ID_PREFIX: string = 'custom-';

/** UI validation bounds, also enforced inside `addCustomWish`. */
export const CUSTOM_WISH_NAME_MIN_CHARS: number = 1;
export const CUSTOM_WISH_NAME_MAX_CHARS: number = 12;
export const CUSTOM_WISH_COST_MIN: number = 5;
export const CUSTOM_WISH_COST_MAX: number = 200;
export const CUSTOM_WISH_DEFAULT_EMOJI: string = '⭐';

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
 *
 * V0.3.9 update: the Idle → Pending → Confirmed chain has been
 * flattened. WishlistPage now redeems via the new
 * `markConfirmed(wishId, nowMs)` after a parent-PIN gate clears
 * (see ParentPinDialog) and CoinAccount.redeem succeeds — the
 * caller is responsible for the redeem. `request` and
 * `confirmByParent` are kept as @deprecated for one version so
 * downstream tests can migrate. `coerceState` reads in any
 * legacy `'pending'` snapshot as Idle (the redemption did not
 * happen, so reverting to Idle is the safe migration default).
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
    // V0.4.7: bump version marker so future migrations can branch on it.
    this.snap.version = 2;
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
      c.isCustom = src.isCustom;
      out.push(c);
    }
    return out;
  }

  /**
   * V0.4.7 — append a parent-created custom wish. Returns the new
   * wish id on success, or an empty string on validation failure.
   * Validation rules:
   *  - displayName trimmed length in [CUSTOM_WISH_NAME_MIN_CHARS,
   *    CUSTOM_WISH_NAME_MAX_CHARS] characters.
   *  - costCoins integer in [CUSTOM_WISH_COST_MIN, CUSTOM_WISH_COST_MAX].
   *  - iconEmoji trimmed to length 1 or 2; empty string falls back to
   *    `CUSTOM_WISH_DEFAULT_EMOJI`.
   * The generated id starts with `custom-` and includes nowMs plus
   * a per-call counter so two adds in the same millisecond don't
   * collide. Caller's nowMs is the source of truth for clock so the
   * unit tests stay deterministic.
   */
  addCustomWish(name: string, costCoins: number, iconEmoji: string, nowMs: number): string {
    const trimmedName: string = name.trim();
    if (trimmedName.length < CUSTOM_WISH_NAME_MIN_CHARS) {
      return '';
    }
    if (trimmedName.length > CUSTOM_WISH_NAME_MAX_CHARS) {
      return '';
    }
    if (!Number.isFinite(costCoins)) {
      return '';
    }
    const cost: number = Math.floor(costCoins);
    if (cost < CUSTOM_WISH_COST_MIN || cost > CUSTOM_WISH_COST_MAX) {
      return '';
    }
    let emoji: string = iconEmoji.trim();
    if (emoji.length === 0) {
      emoji = CUSTOM_WISH_DEFAULT_EMOJI;
    }
    if (emoji.length > 4) {
      // 4 chars covers most multi-codepoint emoji combos (e.g. 🐻‍❄️ is
      // 5 UTF-16 code units; we cap conservatively to keep the wish
      // name bar from wrapping). Reject rather than silently truncate.
      return '';
    }
    const newId: string = this.generateCustomWishId(nowMs);
    const w: MagicWish = new MagicWish();
    w.id = newId;
    w.displayName = trimmedName;
    w.costCoins = cost;
    w.iconEmoji = emoji;
    w.state = WishState.Idle;
    w.isCustom = true;
    this.snap.wishes.push(w);
    this.scheduleSave();
    return newId;
  }

  /**
   * V0.4.7 — remove a custom wish. Refuses any wish that is not
   * `isCustom=true` so the parent can't accidentally drop one of the
   * baked-in default wishes. Returns true on success.
   */
  removeCustomWish(wishId: string): boolean {
    if (wishId.length === 0) {
      return false;
    }
    let idx: number = -1;
    for (let i = 0; i < this.snap.wishes.length; i++) {
      if (this.snap.wishes[i].id === wishId) {
        idx = i;
        break;
      }
    }
    if (idx < 0) {
      return false;
    }
    if (!this.snap.wishes[idx].isCustom) {
      return false;
    }
    this.snap.wishes.splice(idx, 1);
    this.scheduleSave();
    return true;
  }

  private generateCustomWishId(nowMs: number): string {
    let suffix: number = Math.floor(Math.random() * 0xfffff);
    let candidate: string = `${CUSTOM_WISH_ID_PREFIX}${nowMs}-${suffix.toString(16)}`;
    while (this.findWish(candidate) !== undefined) {
      suffix = (suffix + 1) & 0xfffff;
      candidate = `${CUSTOM_WISH_ID_PREFIX}${nowMs}-${suffix.toString(16)}`;
    }
    return candidate;
  }

  /**
   * @deprecated V0.3.9 retired the Pending middle state in favour of
   * a parent-PIN gate (see WishlistPage + ParentPinDialog). Callers
   * should now build the redemption flow on `markConfirmed` after
   * directly invoking `CoinAccount.redeem`. Kept for one version so
   * downstream tests can migrate without a hard break.
   */
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

  /**
   * @deprecated V0.3.9: see `request`. Use `markConfirmed` after
   * `CoinAccount.redeem` succeeds.
   */
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

  /**
   * V0.3.9: idempotent Idle → Confirmed transition. The caller has
   * already cleared the parent PIN and invoked `CoinAccount.redeem`,
   * so this method does *not* touch coin balance — it only flips
   * state and stamps the confirmation timestamp. Returns false when
   * the wish is unknown or already non-Idle (so callers can skip
   * the GiftBox modal on a stale redeem click).
   */
  markConfirmed(wishId: string, nowMs: number): boolean {
    const w: MagicWish | undefined = this.findWish(wishId);
    if (w === undefined) {
      return false;
    }
    if (w.state !== WishState.Idle) {
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

  /**
   * V0.3.9: expose the cold-start parsing path so unit tests can
   * simulate a persisted snapshot without spinning up a real
   * UIAbilityContext. Production code uses `init(ctx)` which calls
   * the same logic plus catalog backfill.
   */
  async rehydrateForTest(): Promise<void> {
    if (this.prefs === undefined) {
      return;
    }
    const raw: string = await this.prefs.getString(WISHLIST_PREFS_KEY);
    if (raw.length > 0) {
      this.snap = parseWishlistSnapshot(raw);
    }
    this.snap.version = 2;
    if (this.snap.wishes.length === 0) {
      this.snap.wishes = getWishCatalogClone();
      return;
    }
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
      w.isCustom = typeof j.isCustom === 'boolean' ? j.isCustom : false;
      if (w.id.length > 0) {
        out.wishes.push(w);
      }
    }
  }
  return out;
}

function coerceState(label: string): WishState {
  if (label === WishState.Confirmed) return WishState.Confirmed;
  // V0.3.9: Pending state retired — a legacy 'pending' literal in
  // persisted JSON normalises to Idle. The redemption never happened
  // (CoinAccount didn't debit), so reverting is the safe migration.
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
