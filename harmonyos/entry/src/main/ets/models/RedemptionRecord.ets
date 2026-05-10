/**
 * V0.3.9: one redemption recorded after the parent PIN gate clears
 * and CoinAccount.redeem succeeds. Persisted by RedemptionHistoryStore
 * in preferences (cap REDEMPTION_HISTORY_CAP, oldest-shifted FIFO).
 *
 * Schema is intentionally minimal — spec §5/§8.1 chose
 * "time + emoji+name + cost" as the smallest set that gives the
 * parent enough context to reconcile what was redeemed.
 */
export class RedemptionRecord {
  /** Unique id: `${ts}-${random4hex}`; collisions improbable single-device. */
  id: string = '';
  /** Date.now() at the moment markConfirmed succeeds. */
  ts: number = 0;
  wishId: string = '';
  displayName: string = '';
  iconEmoji: string = '';
  costCoins: number = 0;
}

export class RedemptionHistorySnapshot {
  version: number = 1;
  records: RedemptionRecord[] = [];
}

export const REDEMPTION_PREFS_NAME: string = 'wordmagic_redemption_history';
export const REDEMPTION_PREFS_KEY: string = 'snapshot_v1';
export const REDEMPTION_HISTORY_CAP: number = 50;

/**
 * Format a Date.now() millisecond value as `YYYY-MM-DD HH:mm` in the
 * device's local timezone. Two-digit zero-padding throughout. Pure —
 * used by RedemptionHistoryPage row rendering.
 */
export function formatLocalTimestamp(ms: number): string {
  const d: Date = new Date(ms);
  const yyyy: string = `${d.getFullYear()}`;
  const mm: string = pad2(d.getMonth() + 1);
  const dd: string = pad2(d.getDate());
  const hh: string = pad2(d.getHours());
  const mi: string = pad2(d.getMinutes());
  return `${yyyy}-${mm}-${dd} ${hh}:${mi}`;
}

function pad2(n: number): string {
  return n < 10 ? `0${n}` : `${n}`;
}
