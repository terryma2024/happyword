import preferences from '@ohos.data.preferences';
import { BusinessError } from '@ohos.base';
import { common } from '@kit.AbilityKit';
import {
  CoinSnapshot,
  CoinTxn,
  COIN_PREFS_NAME,
  COIN_PREFS_KEY,
  DAILY_CAP,
  MAX_TXN_HISTORY,
  formatDayKeyLocal,
} from '../models/CoinSnapshot';
import { StringPreferencesLike } from './WrongAnswerStore';

interface CoinTxnJson {
  ts?: number;
  delta?: number;
  reason?: string;
  balanceAfter?: number;
}

interface CoinSnapshotJson {
  version?: number;
  totalCoins?: number;
  spentCoins?: number;
  todayDayKey?: string;
  todayCoinsEarned?: number;
  todayAdventureCompleted?: boolean;
  txns?: CoinTxnJson[];
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
 * Reason tag emitted by BattlePage on the first today-adventure
 * completion of a calendar day. CoinAccount.earn() recognizes it
 * and sets `todayAdventureCompleted = true` even when the daily
 * cap clamps the actual award to zero.
 */
export const COIN_REASON_TODAY_FIRST: string = 'today-first';

/**
 * CoinAccount — singleton-backed wallet that mirrors LearningRecorder's
 * preferences pattern. Mutations land on `snap` synchronously and a
 * fire-and-forget save is dispatched. Tests inject a Map-backed prefs
 * stand-in via `injectPreferencesForTest`.
 *
 * Daily cap behaviour: callers tag earnings with a `reason`; once
 * `todayCoinsEarned` reaches `DAILY_CAP`, subsequent earn() calls
 * return 0. The special `today-first` reason still flips the
 * `todayAdventureCompleted` flag even when the cap clamps the
 * award to zero — HomePage uses that flag to gate the badge.
 */
export class CoinAccount {
  private prefs?: StringPreferencesLike;
  private snap: CoinSnapshot = new CoinSnapshot();
  private ready: boolean = false;

  injectPreferencesForTest(p: StringPreferencesLike): void {
    this.prefs = p;
    this.ready = true;
  }

  async init(ctx: common.UIAbilityContext): Promise<void> {
    if (this.ready && this.prefs !== undefined) {
      return;
    }
    const real: preferences.Preferences = await preferences.getPreferences(ctx, COIN_PREFS_NAME);
    this.prefs = new RealPrefs(real);
    this.ready = true;
    const raw: string = await this.prefs.getString(COIN_PREFS_KEY);
    if (raw.length > 0) {
      this.snap = parseCoinSnapshot(raw);
    }
  }

  beginToday(nowMs: number): void {
    const key: string = formatDayKeyLocal(nowMs);
    if (this.snap.todayDayKey !== key) {
      this.snap.todayDayKey = key;
      this.snap.todayCoinsEarned = 0;
      this.snap.todayAdventureCompleted = false;
    }
  }

  earn(reason: string, amount: number, nowMs: number): number {
    if (amount <= 0) {
      if (reason === COIN_REASON_TODAY_FIRST) {
        this.snap.todayAdventureCompleted = true;
      }
      return 0;
    }
    const remaining: number = DAILY_CAP - this.snap.todayCoinsEarned;
    const actual: number = Math.max(0, Math.min(amount, remaining));
    if (actual > 0) {
      this.snap.totalCoins += actual;
      this.snap.todayCoinsEarned += actual;
      this.pushTxn(nowMs, actual, reason, this.balance());
    }
    if (reason === COIN_REASON_TODAY_FIRST) {
      this.snap.todayAdventureCompleted = true;
    }
    this.scheduleSave();
    return actual;
  }

  redeem(wishId: string, cost: number): boolean {
    if (cost <= 0) {
      return false;
    }
    if (this.balance() < cost) {
      return false;
    }
    this.snap.spentCoins += cost;
    this.pushTxn(Date.now(), -cost, `redeem:${wishId}`, this.balance());
    this.scheduleSave();
    return true;
  }

  balance(): number {
    return this.snap.totalCoins - this.snap.spentCoins;
  }

  todayAdventureCompleted(): boolean {
    return this.snap.todayAdventureCompleted;
  }

  todayCoinsEarned(): number {
    return this.snap.todayCoinsEarned;
  }

  remainingDailyCapacity(): number {
    const remaining: number = DAILY_CAP - this.snap.todayCoinsEarned;
    return remaining > 0 ? remaining : 0;
  }

  snapshot(): CoinSnapshot {
    const out: CoinSnapshot = new CoinSnapshot();
    out.version = this.snap.version;
    out.totalCoins = this.snap.totalCoins;
    out.spentCoins = this.snap.spentCoins;
    out.todayDayKey = this.snap.todayDayKey;
    out.todayCoinsEarned = this.snap.todayCoinsEarned;
    out.todayAdventureCompleted = this.snap.todayAdventureCompleted;
    out.txns = this.snap.txns.slice();
    return out;
  }

  async flushNow(): Promise<void> {
    if (!this.ready || this.prefs === undefined) {
      return;
    }
    const payload: string = JSON.stringify(this.snap);
    await this.prefs.putString(COIN_PREFS_KEY, payload);
    await this.prefs.flush();
  }

  private pushTxn(ts: number, delta: number, reason: string, balanceAfter: number): void {
    const t: CoinTxn = new CoinTxn();
    t.ts = ts;
    t.delta = delta;
    t.reason = reason;
    t.balanceAfter = balanceAfter;
    this.snap.txns.push(t);
    while (this.snap.txns.length > MAX_TXN_HISTORY) {
      this.snap.txns.shift();
    }
  }

  private scheduleSave(): void {
    if (!this.ready || this.prefs === undefined) {
      return;
    }
    this.prefs.putString(COIN_PREFS_KEY, JSON.stringify(this.snap))
      .catch((err: BusinessError): void => {
        console.error(`CoinAccount save failed: ${JSON.stringify(err)}`);
      });
  }
}

export function parseCoinSnapshot(raw: string): CoinSnapshot {
  const out: CoinSnapshot = new CoinSnapshot();
  if (raw.length === 0) {
    return out;
  }
  let parsed: CoinSnapshotJson;
  try {
    parsed = JSON.parse(raw) as CoinSnapshotJson;
  } catch (err) {
    console.error(`parseCoinSnapshot failed: ${JSON.stringify(err as BusinessError)}`);
    return out;
  }
  if (parsed === null || parsed === undefined) {
    return out;
  }
  if (typeof parsed.version === 'number') {
    out.version = parsed.version;
  }
  if (typeof parsed.totalCoins === 'number') {
    out.totalCoins = parsed.totalCoins;
  }
  if (typeof parsed.spentCoins === 'number') {
    out.spentCoins = parsed.spentCoins;
  }
  if (typeof parsed.todayDayKey === 'string') {
    out.todayDayKey = parsed.todayDayKey;
  }
  if (typeof parsed.todayCoinsEarned === 'number') {
    out.todayCoinsEarned = parsed.todayCoinsEarned;
  }
  if (typeof parsed.todayAdventureCompleted === 'boolean') {
    out.todayAdventureCompleted = parsed.todayAdventureCompleted;
  }
  const txns: CoinTxnJson[] | undefined = parsed.txns;
  if (txns !== undefined && txns !== null) {
    for (let i = 0; i < txns.length; i++) {
      const j: CoinTxnJson = txns[i];
      const t: CoinTxn = new CoinTxn();
      t.ts = typeof j.ts === 'number' ? j.ts : 0;
      t.delta = typeof j.delta === 'number' ? j.delta : 0;
      t.reason = typeof j.reason === 'string' ? j.reason : '';
      t.balanceAfter = typeof j.balanceAfter === 'number' ? j.balanceAfter : 0;
      out.txns.push(t);
    }
  }
  return out;
}

let globalAccount: CoinAccount | undefined = undefined;

export function getCoinAccount(): CoinAccount {
  if (globalAccount === undefined) {
    globalAccount = new CoinAccount();
  }
  return globalAccount;
}

export function __resetCoinAccountForTest(): void {
  globalAccount = undefined;
}
