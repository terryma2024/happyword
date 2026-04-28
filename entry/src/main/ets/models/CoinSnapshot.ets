/**
 * Single transaction in the coin ledger. `delta` is positive on
 * earnings (today-adventure rewards) and negative on redemptions
 * (parent-confirmed wish purchases). `balanceAfter` is the running
 * total post-application; capturing it here lets ResultPage and
 * WishlistPage avoid replaying the whole log to display history.
 */
export class CoinTxn {
  ts: number = 0;
  delta: number = 0;
  reason: string = '';
  balanceAfter: number = 0;
}

/**
 * Persisted form of the magic-coin wallet. `todayDayKey` is the
 * local YYYY-MM-DD string of the day on which `todayCoinsEarned`
 * accumulated; CoinAccount.beginToday compares it against
 * `formatDayKeyLocal(now)` to detect day rollovers and reset the
 * daily cap.
 */
export class CoinSnapshot {
  version: number = 1;
  totalCoins: number = 0;
  spentCoins: number = 0;
  todayDayKey: string = '';
  todayCoinsEarned: number = 0;
  todayAdventureCompleted: boolean = false;
  txns: CoinTxn[] = [];
}

export const COIN_PREFS_NAME: string = 'wordmagic_coins';
export const COIN_PREFS_KEY: string = 'snapshot_v1';
/** Daily earning cap, in magic coins. */
export const DAILY_CAP: number = 20;
/** Hard cap on retained CoinTxn history; older entries are truncated on save. */
export const MAX_TXN_HISTORY: number = 50;

/**
 * Local-midnight day-key. Mirrors `localDayKey` from
 * TodayAdventureBuilder; we duplicate the helper here so the
 * coin layer doesn't depend on the adventure-plan layer.
 */
export function formatDayKeyLocal(nowMs: number): string {
  const d: Date = new Date(nowMs);
  const y: number = d.getFullYear();
  const m: number = d.getMonth() + 1;
  const day: number = d.getDate();
  const mm: string = m < 10 ? `0${m}` : `${m}`;
  const dd: string = day < 10 ? `0${day}` : `${day}`;
  return `${y}-${mm}-${dd}`;
}
