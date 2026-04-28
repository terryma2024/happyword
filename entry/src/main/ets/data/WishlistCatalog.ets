import { MagicWish, WishState } from '../models/MagicWish';

/**
 * Default wishes shipped with V0.3. Costs are calibrated against the
 * 20-coin daily cap so that:
 *  - "看 iPad 20 分钟" is reachable in roughly half a day's play
 *  - the higher-effort wishes encourage multi-day saving
 */
function makeWish(id: string, name: string, cost: number, emoji: string): MagicWish {
  const w: MagicWish = new MagicWish();
  w.id = id;
  w.displayName = name;
  w.costCoins = cost;
  w.iconEmoji = emoji;
  w.state = WishState.Idle;
  return w;
}

export const WISHLIST_CATALOG: MagicWish[] = [
  makeWish('wish-ipad-20min', '看 iPad 20 分钟', 10, '📱'),
  makeWish('wish-watch-topup-10', '手表零钱充值 10 元', 25, '⌚'),
  makeWish('wish-small-gift', '买一个礼物 (≤20 元)', 50, '🎁'),
];

/**
 * Return a deep-enough copy of the catalog so callers can safely
 * mutate `state`/`requestedAt`/`confirmedAt` without contaminating
 * the canonical entries.
 */
export function getWishCatalogClone(): MagicWish[] {
  const out: MagicWish[] = [];
  for (let i = 0; i < WISHLIST_CATALOG.length; i++) {
    const src: MagicWish = WISHLIST_CATALOG[i];
    out.push(makeWish(src.id, src.displayName, src.costCoins, src.iconEmoji));
  }
  return out;
}
