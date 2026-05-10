/**
 * Lifecycle of one wish:
 *   Idle    — published in the wishlist, child has not asked for it yet
 *   Pending — child tapped "wish for it"; awaiting parent long-press
 *   Confirmed — parent gate cleared and CoinAccount.redeem succeeded
 */
export enum WishState {
  Idle = 'idle',
  Pending = 'pending',
  Confirmed = 'confirmed',
}

/**
 * MagicWish is the value object the wishlist UI renders. The store
 * keeps a copy per active wish; the parent long-press gate uses
 * `state` to decide whether to show the confirm or cancel layout.
 *
 * V0.4.7 adds `isCustom`. Default catalog wishes (see WishlistCatalog.ets)
 * are `isCustom=false`; wishes the parent created at runtime are
 * `isCustom=true`. Only custom wishes can be removed via
 * `WishlistStore.removeCustomWish`. Persisted snapshots written before
 * V0.4.7 (version=1) default every wish to `isCustom=false` on rehydrate.
 */
export class MagicWish {
  id: string = '';
  displayName: string = '';
  costCoins: number = 0;
  iconEmoji: string = '';
  state: WishState = WishState.Idle;
  requestedAt: number = 0;
  confirmedAt: number = 0;
  isCustom: boolean = false;
}

export class WishlistSnapshot {
  version: number = 2;
  wishes: MagicWish[] = [];
}

export const WISHLIST_PREFS_NAME: string = 'wordmagic_wishlist';
export const WISHLIST_PREFS_KEY: string = 'snapshot_v1';
