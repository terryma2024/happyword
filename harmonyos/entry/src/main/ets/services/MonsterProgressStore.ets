import preferences from '@ohos.data.preferences';
import { BusinessError } from '@ohos.base';
import { common } from '@kit.AbilityKit';
import { CoinAccount } from './CoinAccount';
import { StringPreferencesLike } from './WrongAnswerStore';

export const MONSTER_PROGRESS_PREFS_NAME: string = 'wordmagic_monster_progress';
export const MONSTER_PROGRESS_PREFS_KEY: string = 'monster_progress/snapshot_v1';
export const MONSTER_MYSTERY_ASSET: string = 'character/monster-mystery-question.svg';

export class MonsterProgressRecord {
  catalogIndex: number = 0;
  encountered: boolean = false;
  defeatCount: number = 0;
  claimedMilestones: number[] = [];
}

export class MonsterProgressSnapshot {
  version: number = 1;
  records: MonsterProgressRecord[] = [];
}

export class MonsterRewardState {
  milestone: number = 0;
  amount: number = 0;
  label: string = '';
  enabled: boolean = false;
  claimed: boolean = false;
}

interface MonsterProgressRecordJson {
  catalogIndex?: number;
  encountered?: boolean;
  defeatCount?: number;
  claimedMilestones?: number[];
}

interface MonsterProgressSnapshotJson {
  version?: number;
  records?: MonsterProgressRecordJson[];
}

class RealMonsterProgressPrefs implements StringPreferencesLike {
  private readonly handle: preferences.Preferences;
  constructor(handle: preferences.Preferences) {
    this.handle = handle;
  }

  async getString(key: string): Promise<string> {
    try {
      const value: preferences.ValueType = await this.handle.get(key, '');
      return typeof value === 'string' ? value : '';
    } catch (err) {
      console.error(`MonsterProgressPrefs.getString failed: ${JSON.stringify(err as BusinessError)}`);
      return '';
    }
  }

  async putString(key: string, value: string): Promise<void> {
    try {
      await this.handle.put(key, value);
    } catch (err) {
      console.error(`MonsterProgressPrefs.putString failed: ${JSON.stringify(err as BusinessError)}`);
    }
  }

  async flush(): Promise<void> {
    try {
      await this.handle.flush();
    } catch (err) {
      console.error(`MonsterProgressPrefs.flush failed: ${JSON.stringify(err as BusinessError)}`);
    }
  }
}

export function maskedQuestionMarks(source: string): string {
  let out: string = '';
  for (let i: number = 0; i < source.length; i++) {
    out += '?';
  }
  return out;
}

export function milestoneCoinAmount(milestone: number): number {
  if (milestone === 50) {
    return 50;
  }
  if (milestone === 100) {
    return 100;
  }
  return 0;
}

export function rewardStateForMilestone(defeatCount: number, claimed: boolean, milestone: number): MonsterRewardState {
  const state: MonsterRewardState = new MonsterRewardState();
  const amount: number = milestoneCoinAmount(milestone);
  state.milestone = milestone;
  state.amount = amount;
  state.claimed = claimed;
  if (claimed) {
    state.label = `已领 ${amount} 金币`;
    state.enabled = false;
    return state;
  }
  if (amount > 0 && defeatCount >= milestone) {
    state.label = `领 ${amount} 金币`;
    state.enabled = true;
    return state;
  }
  const safeDefeats: number = defeatCount > 0 ? Math.floor(defeatCount) : 0;
  state.label = `${amount} 金币 ${safeDefeats}/${milestone}`;
  state.enabled = false;
  return state;
}

export function parseMonsterProgressSnapshot(raw: string): MonsterProgressSnapshot {
  const snap: MonsterProgressSnapshot = new MonsterProgressSnapshot();
  if (raw.length === 0) {
    return snap;
  }
  let parsed: MonsterProgressSnapshotJson;
  try {
    parsed = JSON.parse(raw) as MonsterProgressSnapshotJson;
  } catch (err) {
    console.error(`parseMonsterProgressSnapshot failed: ${JSON.stringify(err as BusinessError)}`);
    return snap;
  }
  if (parsed === null || parsed === undefined) {
    return snap;
  }
  if (typeof parsed.version === 'number' && Number.isFinite(parsed.version)) {
    snap.version = Math.floor(parsed.version);
  }
  const rawRecords: MonsterProgressRecordJson[] | undefined = parsed.records;
  if (rawRecords === undefined || rawRecords === null) {
    return snap;
  }
  for (let i: number = 0; i < rawRecords.length; i++) {
    const rawRecord: MonsterProgressRecordJson = rawRecords[i];
    const idx: number = typeof rawRecord.catalogIndex === 'number' ? Math.floor(rawRecord.catalogIndex) : 0;
    if (idx <= 0 || findRecordIndex(snap.records, idx) >= 0) {
      continue;
    }
    const rec: MonsterProgressRecord = new MonsterProgressRecord();
    rec.catalogIndex = idx;
    rec.encountered = rawRecord.encountered === true;
    rec.defeatCount = typeof rawRecord.defeatCount === 'number' && rawRecord.defeatCount > 0
      ? Math.floor(rawRecord.defeatCount)
      : 0;
    rec.claimedMilestones = normalizeMilestones(rawRecord.claimedMilestones);
    snap.records.push(rec);
  }
  return snap;
}

export function serializeMonsterProgressSnapshot(snapshot: MonsterProgressSnapshot): string {
  return JSON.stringify(snapshot);
}

function normalizeMilestones(raw: number[] | undefined): number[] {
  const out: number[] = [];
  if (raw === undefined || raw === null) {
    return out;
  }
  for (let i: number = 0; i < raw.length; i++) {
    const milestone: number = Math.floor(raw[i]);
    if ((milestone === 50 || milestone === 100) && out.indexOf(milestone) < 0) {
      out.push(milestone);
    }
  }
  out.sort((a: number, b: number): number => a - b);
  return out;
}

function findRecordIndex(records: MonsterProgressRecord[], catalogIndex: number): number {
  for (let i: number = 0; i < records.length; i++) {
    if (records[i].catalogIndex === catalogIndex) {
      return i;
    }
  }
  return -1;
}

function cloneRecord(src: MonsterProgressRecord): MonsterProgressRecord {
  const out: MonsterProgressRecord = new MonsterProgressRecord();
  out.catalogIndex = src.catalogIndex;
  out.encountered = src.encountered;
  out.defeatCount = src.defeatCount;
  out.claimedMilestones = src.claimedMilestones.slice();
  return out;
}

function cloneSnapshot(src: MonsterProgressSnapshot): MonsterProgressSnapshot {
  const out: MonsterProgressSnapshot = new MonsterProgressSnapshot();
  out.version = src.version;
  for (let i: number = 0; i < src.records.length; i++) {
    out.records.push(cloneRecord(src.records[i]));
  }
  return out;
}

export class MonsterProgressStore {
  private prefs?: StringPreferencesLike;
  private ready: boolean = false;
  private snap: MonsterProgressSnapshot = new MonsterProgressSnapshot();

  injectPreferencesForTest(prefs: StringPreferencesLike): void {
    this.prefs = prefs;
    this.ready = true;
  }

  async init(ctx: common.UIAbilityContext): Promise<void> {
    if (this.ready && this.prefs !== undefined) {
      return;
    }
    try {
      const real: preferences.Preferences = await preferences.getPreferences(ctx, MONSTER_PROGRESS_PREFS_NAME);
      this.prefs = new RealMonsterProgressPrefs(real);
      this.ready = true;
      const raw: string = await this.prefs.getString(MONSTER_PROGRESS_PREFS_KEY);
      this.snap = parseMonsterProgressSnapshot(raw);
    } catch (err) {
      console.error(`MonsterProgressStore.init failed: ${JSON.stringify(err as BusinessError)}`);
    }
  }

  async rehydrateForTest(): Promise<void> {
    if (this.prefs === undefined) {
      return;
    }
    this.snap = parseMonsterProgressSnapshot(await this.prefs.getString(MONSTER_PROGRESS_PREFS_KEY));
  }

  recordFor(catalogIndex: number): MonsterProgressRecord {
    const idx: number = Math.floor(catalogIndex);
    const existing: number = findRecordIndex(this.snap.records, idx);
    if (existing < 0) {
      const empty: MonsterProgressRecord = new MonsterProgressRecord();
      empty.catalogIndex = idx;
      return empty;
    }
    return cloneRecord(this.snap.records[existing]);
  }

  recordEncounter(catalogIndex: number): void {
    const rec: MonsterProgressRecord | undefined = this.mutableRecord(catalogIndex);
    if (rec === undefined) {
      return;
    }
    rec.encountered = true;
    this.scheduleSave();
  }

  recordDefeat(catalogIndex: number): void {
    const rec: MonsterProgressRecord | undefined = this.mutableRecord(catalogIndex);
    if (rec === undefined) {
      return;
    }
    rec.encountered = true;
    rec.defeatCount += 1;
    this.scheduleSave();
  }

  rewardState(catalogIndex: number, milestone: number): MonsterRewardState {
    const rec: MonsterProgressRecord = this.recordFor(catalogIndex);
    return rewardStateForMilestone(rec.defeatCount, rec.claimedMilestones.indexOf(milestone) >= 0, milestone);
  }

  canClaim(catalogIndex: number, milestone: number): boolean {
    const rec: MonsterProgressRecord = this.recordFor(catalogIndex);
    return rec.encountered &&
      rec.defeatCount >= milestone &&
      milestoneCoinAmount(milestone) > 0 &&
      rec.claimedMilestones.indexOf(milestone) < 0;
  }

  claimReward(catalogIndex: number, milestone: number, coins: CoinAccount, nowMs: number): boolean {
    if (!this.canClaim(catalogIndex, milestone)) {
      return false;
    }
    const amount: number = milestoneCoinAmount(milestone);
    const txnId: string = `monster-codex:${milestone}:${catalogIndex}`;
    const credited: number = coins.creditCapFree(txnId, amount, nowMs);
    if (credited !== amount) {
      return false;
    }
    return this.markClaimed(catalogIndex, milestone);
  }

  markClaimed(catalogIndex: number, milestone: number): boolean {
    const rec: MonsterProgressRecord | undefined = this.mutableRecord(catalogIndex);
    if (rec === undefined || rec.claimedMilestones.indexOf(milestone) >= 0 || milestoneCoinAmount(milestone) <= 0) {
      return false;
    }
    rec.claimedMilestones.push(milestone);
    rec.claimedMilestones = normalizeMilestones(rec.claimedMilestones);
    this.scheduleSave();
    return true;
  }

  snapshot(): MonsterProgressSnapshot {
    return cloneSnapshot(this.snap);
  }

  async flushNow(): Promise<void> {
    if (!this.ready || this.prefs === undefined) {
      return;
    }
    await this.prefs.putString(MONSTER_PROGRESS_PREFS_KEY, serializeMonsterProgressSnapshot(this.snap));
    await this.prefs.flush();
  }

  private mutableRecord(catalogIndex: number): MonsterProgressRecord | undefined {
    const idx: number = Math.floor(catalogIndex);
    if (idx <= 0 || !Number.isFinite(idx)) {
      return undefined;
    }
    const found: number = findRecordIndex(this.snap.records, idx);
    if (found >= 0) {
      return this.snap.records[found];
    }
    const rec: MonsterProgressRecord = new MonsterProgressRecord();
    rec.catalogIndex = idx;
    this.snap.records.push(rec);
    return rec;
  }

  private scheduleSave(): void {
    if (!this.ready || this.prefs === undefined) {
      return;
    }
    this.prefs.putString(MONSTER_PROGRESS_PREFS_KEY, serializeMonsterProgressSnapshot(this.snap))
      .catch((err: BusinessError): void => {
        console.error(`MonsterProgressStore save failed: ${JSON.stringify(err)}`);
      });
  }
}

let globalStore: MonsterProgressStore | undefined = undefined;

export function getMonsterProgressStore(): MonsterProgressStore {
  if (globalStore === undefined) {
    globalStore = new MonsterProgressStore();
  }
  return globalStore;
}

export function __resetMonsterProgressStoreForTest(): void {
  globalStore = undefined;
}
