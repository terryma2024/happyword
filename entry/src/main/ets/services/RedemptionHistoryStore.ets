import preferences from '@ohos.data.preferences';
import { BusinessError } from '@ohos.base';
import { common } from '@kit.AbilityKit';
import {
  RedemptionRecord,
  RedemptionHistorySnapshot,
  REDEMPTION_PREFS_NAME,
  REDEMPTION_PREFS_KEY,
  REDEMPTION_HISTORY_CAP,
} from '../models/RedemptionRecord';
import { StringPreferencesLike } from './WrongAnswerStore';

interface RedemptionRecordJson {
  id?: string;
  ts?: number;
  wishId?: string;
  displayName?: string;
  iconEmoji?: string;
  costCoins?: number;
}

interface RedemptionHistorySnapshotJson {
  version?: number;
  records?: RedemptionRecordJson[];
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
 * V0.3.9: persistent log of every successful wishlist redemption.
 * Mirrors WishlistStore's preferences pattern — synchronous in-memory
 * mutations + fire-and-forget putString persistence. Tests inject a
 * Map-backed prefs stand-in via injectPreferencesForTest. The cap
 * is enforced on every add() by shifting the oldest entry out so
 * preferences can't grow unbounded across years of use.
 */
export class RedemptionHistoryStore {
  private prefs?: StringPreferencesLike;
  private snap: RedemptionHistorySnapshot = new RedemptionHistorySnapshot();
  private ready: boolean = false;

  injectPreferencesForTest(p: StringPreferencesLike): void {
    this.prefs = p;
    this.ready = true;
  }

  async init(ctx: common.UIAbilityContext): Promise<void> {
    if (this.ready && this.prefs !== undefined) {
      return;
    }
    const real: preferences.Preferences =
      await preferences.getPreferences(ctx, REDEMPTION_PREFS_NAME);
    this.prefs = new RealPrefs(real);
    this.ready = true;
    await this.rehydrateForTest();
  }

  /**
   * Rehydrate snapshot from preferences. Exposed publicly so unit
   * tests can simulate a cold start without spinning up a full
   * UIAbilityContext (kept the *ForTest suffix to make intent clear
   * even though init() also calls it).
   */
  async rehydrateForTest(): Promise<void> {
    if (this.prefs === undefined) {
      return;
    }
    const raw: string = await this.prefs.getString(REDEMPTION_PREFS_KEY);
    if (raw.length > 0) {
      this.snap = parseRedemptionHistorySnapshot(raw);
    }
  }

  add(record: RedemptionRecord): void {
    const copy: RedemptionRecord = cloneRecord(record);
    this.snap.records.push(copy);
    while (this.snap.records.length > REDEMPTION_HISTORY_CAP) {
      this.snap.records.shift();
    }
    this.scheduleSave();
  }

  /** Returns deep-cloned records sorted newest-first (ts desc). */
  list(): RedemptionRecord[] {
    const out: RedemptionRecord[] = [];
    for (let i = 0; i < this.snap.records.length; i++) {
      out.push(cloneRecord(this.snap.records[i]));
    }
    out.sort((a: RedemptionRecord, b: RedemptionRecord): number => b.ts - a.ts);
    return out;
  }

  async flushNow(): Promise<void> {
    if (!this.ready || this.prefs === undefined) {
      return;
    }
    await this.prefs.putString(
      REDEMPTION_PREFS_KEY, JSON.stringify(this.snap));
    await this.prefs.flush();
  }

  private scheduleSave(): void {
    if (!this.ready || this.prefs === undefined) {
      return;
    }
    this.prefs.putString(REDEMPTION_PREFS_KEY, JSON.stringify(this.snap))
      .catch((err: BusinessError): void => {
        console.error(`RedemptionHistoryStore save failed: ${JSON.stringify(err)}`);
      });
  }
}

function cloneRecord(src: RedemptionRecord): RedemptionRecord {
  const c: RedemptionRecord = new RedemptionRecord();
  c.id = src.id;
  c.ts = src.ts;
  c.wishId = src.wishId;
  c.displayName = src.displayName;
  c.iconEmoji = src.iconEmoji;
  c.costCoins = src.costCoins;
  return c;
}

export function parseRedemptionHistorySnapshot(raw: string): RedemptionHistorySnapshot {
  const out: RedemptionHistorySnapshot = new RedemptionHistorySnapshot();
  if (raw.length === 0) {
    return out;
  }
  let parsed: RedemptionHistorySnapshotJson;
  try {
    parsed = JSON.parse(raw) as RedemptionHistorySnapshotJson;
  } catch (err) {
    console.error(`parseRedemptionHistorySnapshot failed: ${JSON.stringify(err as BusinessError)}`);
    return out;
  }
  if (parsed === null || parsed === undefined) {
    return out;
  }
  if (typeof parsed.version === 'number') {
    out.version = parsed.version;
  }
  const xs: RedemptionRecordJson[] | undefined = parsed.records;
  if (xs !== undefined && xs !== null) {
    for (let i = 0; i < xs.length; i++) {
      const j: RedemptionRecordJson = xs[i];
      const r: RedemptionRecord = new RedemptionRecord();
      r.id = typeof j.id === 'string' ? j.id : '';
      r.ts = typeof j.ts === 'number' ? j.ts : 0;
      r.wishId = typeof j.wishId === 'string' ? j.wishId : '';
      r.displayName = typeof j.displayName === 'string' ? j.displayName : '';
      r.iconEmoji = typeof j.iconEmoji === 'string' ? j.iconEmoji : '';
      r.costCoins = typeof j.costCoins === 'number' ? j.costCoins : 0;
      if (r.id.length > 0) {
        out.records.push(r);
      }
    }
  }
  return out;
}

let globalStore: RedemptionHistoryStore | undefined = undefined;

export function getRedemptionHistoryStore(): RedemptionHistoryStore {
  if (globalStore === undefined) {
    globalStore = new RedemptionHistoryStore();
  }
  return globalStore;
}

export function __resetRedemptionHistoryStoreForTest(): void {
  globalStore = undefined;
}
