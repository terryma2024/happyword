import preferences from '@ohos.data.preferences';
import { BusinessError } from '@ohos.base';
import { common } from '@kit.AbilityKit';
import {
  CHECKIN_PREFS_KEY,
  CHECKIN_PREFS_NAME,
  CHECKIN_WEEKLY_BONUS_COINS,
  CheckInSnapshot,
} from '../models/CheckInSnapshot';
import { StringPreferencesLike } from './WrongAnswerStore';
import { formatDayKeyLocal } from '../models/CoinSnapshot';

interface CheckInSnapshotJson {
  version?: number;
  checkedDayKeys?: string[];
  weeklyBonusDayKeys?: string[];
  currentStreak?: number;
  bestStreak?: number;
  lastSyncedAtMs?: number;
  pendingSync?: boolean;
}

class RealPrefs implements StringPreferencesLike {
  private readonly handle: preferences.Preferences;

  constructor(handle: preferences.Preferences) {
    this.handle = handle;
  }

  async getString(key: string): Promise<string> {
    try {
      const v: preferences.ValueType = await this.handle.get(key, '');
      return typeof v === 'string' ? v : '';
    } catch (err) {
      console.error(`CheckInStore.RealPrefs.getString failed: ${JSON.stringify(err as BusinessError)}`);
      return '';
    }
  }

  async putString(key: string, value: string): Promise<void> {
    try {
      await this.handle.put(key, value);
    } catch (err) {
      console.error(`CheckInStore.RealPrefs.putString failed: ${JSON.stringify(err as BusinessError)}`);
    }
  }

  async flush(): Promise<void> {
    try {
      await this.handle.flush();
    } catch (err) {
      console.error(`CheckInStore.RealPrefs.flush failed: ${JSON.stringify(err as BusinessError)}`);
    }
  }
}

export class CheckInRecordResult {
  changed: boolean = false;
  dayKey: string = '';
  currentStreak: number = 0;
  bestStreak: number = 0;
  bonusCoins: number = 0;
  bonusDayKey: string = '';
}

export class CheckInStore {
  private prefs?: StringPreferencesLike;
  private snap: CheckInSnapshot = new CheckInSnapshot();
  private ready: boolean = false;

  injectPreferencesForTest(p: StringPreferencesLike): void {
    this.prefs = p;
    this.ready = true;
  }

  async init(ctx: common.UIAbilityContext): Promise<void> {
    if (this.ready && this.prefs !== undefined) {
      return;
    }
    try {
      const handle: preferences.Preferences = await preferences.getPreferences(ctx, CHECKIN_PREFS_NAME);
      this.prefs = new RealPrefs(handle);
      this.ready = true;
      const raw: string = await this.prefs.getString(CHECKIN_PREFS_KEY);
      this.snap = parseCheckInSnapshot(raw);
      this.recomputeStreaks();
    } catch (err) {
      console.error(`CheckInStore.init failed: ${JSON.stringify(err as BusinessError)}`);
    }
  }

  async recordWin(nowMs: number): Promise<CheckInRecordResult> {
    const result: CheckInRecordResult = this.recordWinSync(nowMs);
    await this.flushNow();
    return result;
  }

  recordWinSync(nowMs: number): CheckInRecordResult {
    const dayKey: string = formatDayKeyLocal(nowMs);
    const result: CheckInRecordResult = new CheckInRecordResult();
    result.dayKey = dayKey;
    if (containsString(this.snap.checkedDayKeys, dayKey)) {
      result.currentStreak = this.snap.currentStreak;
      result.bestStreak = this.snap.bestStreak;
      return result;
    }
    this.snap.checkedDayKeys.push(dayKey);
    this.snap.checkedDayKeys = sortedUnique(this.snap.checkedDayKeys);
    this.recomputeStreaks(dayKey);
    this.snap.pendingSync = true;

    result.changed = true;
    result.currentStreak = this.snap.currentStreak;
    result.bestStreak = this.snap.bestStreak;
    if (result.currentStreak > 0 &&
        result.currentStreak % 7 === 0 &&
        !containsString(this.snap.weeklyBonusDayKeys, dayKey)) {
      this.snap.weeklyBonusDayKeys.push(dayKey);
      this.snap.weeklyBonusDayKeys = sortedUnique(this.snap.weeklyBonusDayKeys);
      result.bonusCoins = CHECKIN_WEEKLY_BONUS_COINS;
      result.bonusDayKey = dayKey;
    }
    this.scheduleSave();
    return result;
  }

  async applyCloudMerge(
    checkedDayKeys: string[],
    weeklyBonusDayKeys: string[],
    serverNowMs: number,
  ): Promise<void> {
    this.snap.checkedDayKeys = sortedUnique(this.snap.checkedDayKeys.concat(checkedDayKeys));
    this.snap.weeklyBonusDayKeys = sortedUnique(this.snap.weeklyBonusDayKeys.concat(weeklyBonusDayKeys));
    this.snap.lastSyncedAtMs = serverNowMs;
    this.snap.pendingSync = false;
    this.recomputeStreaks();
    await this.flushNow();
  }

  markPendingSync(): void {
    this.snap.pendingSync = true;
    this.scheduleSave();
  }

  snapshot(): CheckInSnapshot {
    const out: CheckInSnapshot = new CheckInSnapshot();
    out.version = this.snap.version;
    out.checkedDayKeys = this.snap.checkedDayKeys.slice();
    out.weeklyBonusDayKeys = this.snap.weeklyBonusDayKeys.slice();
    out.currentStreak = this.snap.currentStreak;
    out.bestStreak = this.snap.bestStreak;
    out.lastSyncedAtMs = this.snap.lastSyncedAtMs;
    out.pendingSync = this.snap.pendingSync;
    return out;
  }

  async flushNow(): Promise<void> {
    if (!this.ready || this.prefs === undefined) {
      return;
    }
    await this.prefs.putString(CHECKIN_PREFS_KEY, JSON.stringify(this.snap));
    await this.prefs.flush();
  }

  private scheduleSave(): void {
    if (!this.ready || this.prefs === undefined) {
      return;
    }
    this.prefs.putString(CHECKIN_PREFS_KEY, JSON.stringify(this.snap))
      .catch((err: BusinessError): void => {
        console.error(`CheckInStore save failed: ${JSON.stringify(err)}`);
      });
  }

  private recomputeStreaks(anchorDayKey?: string): void {
    this.snap.checkedDayKeys = sortedUnique(this.snap.checkedDayKeys);
    this.snap.weeklyBonusDayKeys = sortedUnique(this.snap.weeklyBonusDayKeys);
    let best: number = 0;
    let currentRun: number = 0;
    let prev: string = '';
    for (let i = 0; i < this.snap.checkedDayKeys.length; i++) {
      const day: string = this.snap.checkedDayKeys[i];
      if (i === 0 || isNextLocalDay(prev, day)) {
        currentRun += 1;
      } else {
        currentRun = 1;
      }
      if (currentRun > best) {
        best = currentRun;
      }
      prev = day;
    }
    this.snap.bestStreak = best;
    const anchor: string = anchorDayKey !== undefined && anchorDayKey.length > 0
      ? anchorDayKey
      : lastString(this.snap.checkedDayKeys);
    this.snap.currentStreak = countStreakEndingAt(this.snap.checkedDayKeys, anchor);
    if (this.snap.currentStreak > this.snap.bestStreak) {
      this.snap.bestStreak = this.snap.currentStreak;
    }
  }
}

export function parseCheckInSnapshot(raw: string): CheckInSnapshot {
  const out: CheckInSnapshot = new CheckInSnapshot();
  if (raw.length === 0) {
    return out;
  }
  let parsed: CheckInSnapshotJson;
  try {
    parsed = JSON.parse(raw) as CheckInSnapshotJson;
  } catch (err) {
    console.error(`parseCheckInSnapshot failed: ${JSON.stringify(err as BusinessError)}`);
    return out;
  }
  if (typeof parsed.version === 'number') {
    out.version = parsed.version;
  }
  if (Array.isArray(parsed.checkedDayKeys)) {
    out.checkedDayKeys = sortedUnique(parsed.checkedDayKeys);
  }
  if (Array.isArray(parsed.weeklyBonusDayKeys)) {
    out.weeklyBonusDayKeys = sortedUnique(parsed.weeklyBonusDayKeys);
  }
  out.currentStreak = typeof parsed.currentStreak === 'number' ? parsed.currentStreak : 0;
  out.bestStreak = typeof parsed.bestStreak === 'number' ? parsed.bestStreak : 0;
  out.lastSyncedAtMs = typeof parsed.lastSyncedAtMs === 'number' ? parsed.lastSyncedAtMs : 0;
  out.pendingSync = typeof parsed.pendingSync === 'boolean' ? parsed.pendingSync : false;
  return out;
}

let globalStore: CheckInStore | undefined = undefined;

export function getCheckInStore(): CheckInStore {
  if (globalStore === undefined) {
    globalStore = new CheckInStore();
  }
  return globalStore;
}

export function __resetCheckInStoreForTest(): void {
  globalStore = undefined;
}

function containsString(items: string[], value: string): boolean {
  for (let i = 0; i < items.length; i++) {
    if (items[i] === value) {
      return true;
    }
  }
  return false;
}

function sortedUnique(items: string[]): string[] {
  const seen: Set<string> = new Set<string>();
  for (let i = 0; i < items.length; i++) {
    const value: string = items[i];
    if (value.length > 0) {
      seen.add(value);
    }
  }
  const out: string[] = [];
  seen.forEach((value: string): void => {
    out.push(value);
  });
  out.sort();
  return out;
}

function lastString(items: string[]): string {
  if (items.length === 0) {
    return '';
  }
  return items[items.length - 1];
}

function countStreakEndingAt(sortedDays: string[], dayKey: string): number {
  if (dayKey.length === 0 || !containsString(sortedDays, dayKey)) {
    return 0;
  }
  let count: number = 1;
  let cursor: string = dayKey;
  for (let i = sortedDays.length - 1; i >= 0; i--) {
    const d: string = sortedDays[i];
    if (d >= cursor) {
      continue;
    }
    if (isNextLocalDay(d, cursor)) {
      count += 1;
      cursor = d;
    } else {
      break;
    }
  }
  return count;
}

function isNextLocalDay(prevDayKey: string, nextDayKey: string): boolean {
  return dayNumber(nextDayKey) - dayNumber(prevDayKey) === 1;
}

function dayNumber(dayKey: string): number {
  const ms: number = Date.parse(`${dayKey}T00:00:00`);
  return Math.floor(ms / 86400000);
}
