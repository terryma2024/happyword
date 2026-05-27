import preferences from '@ohos.data.preferences';
import { BusinessError } from '@ohos.base';
import { common } from '@kit.AbilityKit';
import { WordEntry } from '../models/WordEntry';
import { MemoryState } from './MemoryScheduler';
import { StringPreferencesLike, WordStat } from './WrongAnswerStore';

const PREFS_NAME: string = 'daily_learning_state';
const PREFS_KEY: string = 'snapshot_v1';
const DAY_MS: number = 24 * 60 * 60 * 1000;
const REVIEW_LIMIT: number = 50;
const RECENT_WRONG_DAYS: number = 7;

export enum ReviewReason {
  DueReview = 'due_review',
  RecentWrong = 'recent_wrong',
  WeakWord = 'weak_word',
}

export class DailyReviewItem {
  wordId: string = '';
  reasons: ReviewReason[] = [];
  primaryReason: ReviewReason = ReviewReason.DueReview;
  score: number = 0;
  lastAnsweredMs: number = 0;
}

export class DailyReviewSnapshot {
  dayKey: string = '';
  generatedAtMs: number = 0;
  sourceCutoffMs: number = 0;
  wordIds: string[] = [];
  reviewedWordIds: string[] = [];
  items: DailyReviewItem[] = [];
}

export class DailyLearningState {
  dayKey: string = '';
  packBattleWon: boolean = false;
  reviewAllDone: boolean = true;
  reviewSnapshot: DailyReviewSnapshot = new DailyReviewSnapshot();
}

export class HomeDailyStatus {
  label: string = '';
  remainingReviewCount: number = 0;
  todayAdventureCompleted: boolean = false;
  dailyCheckInCompleted: boolean = false;
}

interface DailyReviewItemJson {
  wordId?: string;
  reasons?: string[];
  primaryReason?: string;
  score?: number;
  lastAnsweredMs?: number;
}

interface DailyReviewSnapshotJson {
  dayKey?: string;
  generatedAtMs?: number;
  sourceCutoffMs?: number;
  wordIds?: string[];
  reviewedWordIds?: string[];
  items?: DailyReviewItemJson[];
}

interface DailyLearningStateJson {
  dayKey?: string;
  packBattleWon?: boolean;
  reviewAllDone?: boolean;
  reviewSnapshot?: DailyReviewSnapshotJson;
}

class RealDailyPrefs implements StringPreferencesLike {
  private readonly handle: preferences.Preferences;

  constructor(handle: preferences.Preferences) {
    this.handle = handle;
  }

  async getString(key: string): Promise<string> {
    try {
      const value: preferences.ValueType = await this.handle.get(key, '');
      return typeof value === 'string' ? value : '';
    } catch (err) {
      console.error(`DailyLearningStateService.getString failed: ${JSON.stringify(err as BusinessError)}`);
      return '';
    }
  }

  async putString(key: string, value: string): Promise<void> {
    try {
      await this.handle.put(key, value);
    } catch (err) {
      console.error(`DailyLearningStateService.putString failed: ${JSON.stringify(err as BusinessError)}`);
    }
  }

  async flush(): Promise<void> {
    try {
      await this.handle.flush();
    } catch (err) {
      console.error(`DailyLearningStateService.flush failed: ${JSON.stringify(err as BusinessError)}`);
    }
  }
}

export function compactDayKey(nowMs: number): string {
  const d: Date = new Date(nowMs);
  const y: number = d.getFullYear();
  const m: number = d.getMonth() + 1;
  const day: number = d.getDate();
  const mm: string = m < 10 ? '0' + m.toString() : m.toString();
  const dd: string = day < 10 ? '0' + day.toString() : day.toString();
  return `${y}${mm}${dd}`;
}

export function decideHomeDailyStatus(state: DailyLearningState): HomeDailyStatus {
  const out: HomeDailyStatus = new HomeDailyStatus();
  const remaining: number = remainingReviewCount(state.reviewSnapshot);
  const packDone: boolean = state.packBattleWon;
  const reviewDone: boolean = remaining === 0;
  out.remainingReviewCount = remaining;
  out.todayAdventureCompleted = packDone && reviewDone;
  out.dailyCheckInCompleted = packDone || reviewDone;
  if (out.todayAdventureCompleted) {
    out.label = '已完成';
  } else if (packDone) {
    out.label = `请点击复习加战斗(${remaining})`;
  } else {
    out.label = '请选择一个场景加战斗';
  }
  return out;
}

export function reviewMonsterCount(
  requiredWordCount: number,
  monsterHp: number,
  configuredTotal: number,
  defaultMonsterHp: number,
): number {
  if (requiredWordCount <= 0) {
    return 1;
  }
  const hp: number = monsterHp > 0 ? monsterHp : defaultMonsterHp;
  const safeHp: number = hp > 0 ? hp : 5;
  const answersPerMonster: number = safeHp * 4 / 3;
  let count: number = Math.ceil(requiredWordCount / answersPerMonster);
  if (count < 1) {
    count = 1;
  }
  const maxCount: number = configuredTotal > 0 ? configuredTotal : 1;
  if (count > maxCount) {
    return maxCount;
  }
  return count;
}

export class ReviewQueueBuilder {
  buildSnapshot(
    words: WordEntry[],
    stats: WordStat[],
    nowMs: number,
    selectedWordIds: string[],
  ): DailyReviewSnapshot {
    const snapshot: DailyReviewSnapshot = new DailyReviewSnapshot();
    snapshot.dayKey = compactDayKey(nowMs);
    snapshot.generatedAtMs = nowMs;
    snapshot.sourceCutoffMs = localStartOfDay(nowMs);

    const wordIds: string[] = uniqueWordIds(words);
    const selected: Set<string> = toStringSet(selectedWordIds);
    const statById: Map<string, WordStat> = new Map<string, WordStat>();
    for (let i = 0; i < stats.length; i++) {
      if (stats[i].wordId.length > 0) {
        statById.set(stats[i].wordId, stats[i]);
      }
    }

    const items: DailyReviewItem[] = [];
    for (let i = 0; i < wordIds.length; i++) {
      const id: string = wordIds[i];
      const stat: WordStat | undefined = statById.get(id);
      if (stat === undefined || stat.lastAnsweredMs >= snapshot.sourceCutoffMs) {
        continue;
      }
      const item: DailyReviewItem = buildReviewItem(id, stat, snapshot.sourceCutoffMs, selected.has(id));
      if (item.reasons.length > 0) {
        items.push(item);
      }
    }

    items.sort((a: DailyReviewItem, b: DailyReviewItem): number => {
      if (b.score !== a.score) {
        return b.score - a.score;
      }
      if (b.lastAnsweredMs !== a.lastAnsweredMs) {
        return b.lastAnsweredMs - a.lastAnsweredMs;
      }
      if (a.wordId < b.wordId) {
        return -1;
      }
      if (a.wordId > b.wordId) {
        return 1;
      }
      return 0;
    });

    const capped: DailyReviewItem[] = [];
    for (let i = 0; i < items.length && i < REVIEW_LIMIT; i++) {
      capped.push(items[i]);
      snapshot.wordIds.push(items[i].wordId);
    }
    snapshot.items = capped;
    snapshot.reviewedWordIds = [];
    return snapshot;
  }
}

export class DailyLearningStateService {
  private prefs?: StringPreferencesLike;
  private state: DailyLearningState = new DailyLearningState();
  private ready: boolean = false;

  injectPreferencesForTest(prefs: StringPreferencesLike): void {
    this.prefs = prefs;
    this.ready = true;
  }

  async init(ctx: common.UIAbilityContext): Promise<void> {
    if (this.ready && this.prefs !== undefined) {
      return;
    }
    try {
      const handle: preferences.Preferences = await preferences.getPreferences(ctx, PREFS_NAME);
      this.prefs = new RealDailyPrefs(handle);
      this.ready = true;
      const raw: string = await this.prefs.getString(PREFS_KEY);
      this.state = parseDailyLearningState(raw);
    } catch (err) {
      console.error(`DailyLearningStateService.init failed: ${JSON.stringify(err as BusinessError)}`);
    }
  }

  snapshot(): DailyLearningState {
    return cloneDailyLearningState(this.state);
  }

  async ensureForDay(
    words: WordEntry[],
    stats: WordStat[],
    nowMs: number,
    selectedWordIds: string[],
  ): Promise<DailyLearningState> {
    const dayKey: string = compactDayKey(nowMs);
    if (this.state.dayKey !== dayKey) {
      this.state = new DailyLearningState();
      this.state.dayKey = dayKey;
      this.state.reviewSnapshot = new ReviewQueueBuilder()
        .buildSnapshot(words, stats, nowMs, selectedWordIds);
      this.state.reviewAllDone = this.state.reviewSnapshot.wordIds.length === 0;
      await this.flushNow();
    }
    return cloneDailyLearningState(this.state);
  }

  async markPackBattleWon(nowMs: number): Promise<void> {
    const dayKey: string = compactDayKey(nowMs);
    this.resetIfNeeded(dayKey);
    this.markPackBattleWonInMemory(this.state);
    await this.flushNow();
  }

  async markReviewedWords(nowMs: number, wordIds: string[]): Promise<void> {
    const dayKey: string = compactDayKey(nowMs);
    this.resetIfNeeded(dayKey);
    this.markReviewedWordsInMemory(this.state, wordIds);
    await this.flushNow();
  }

  markPackBattleWonInMemory(state: DailyLearningState): void {
    state.packBattleWon = true;
  }

  markReviewedWordsInMemory(state: DailyLearningState, wordIds: string[]): void {
    const expected: Set<string> = toStringSet(state.reviewSnapshot.wordIds);
    const reviewed: Set<string> = toStringSet(state.reviewSnapshot.reviewedWordIds);
    for (let i = 0; i < wordIds.length; i++) {
      const id: string = wordIds[i];
      if (expected.has(id) && !reviewed.has(id)) {
        reviewed.add(id);
        state.reviewSnapshot.reviewedWordIds.push(id);
      }
    }
    state.reviewAllDone = remainingReviewCount(state.reviewSnapshot) === 0;
  }

  async flushNow(): Promise<void> {
    if (!this.ready || this.prefs === undefined) {
      return;
    }
    await this.prefs.putString(PREFS_KEY, JSON.stringify(this.state));
    await this.prefs.flush();
  }

  async clearForTest(): Promise<void> {
    this.state = new DailyLearningState();
    await this.flushNow();
  }

  private resetIfNeeded(dayKey: string): void {
    if (this.state.dayKey === dayKey) {
      return;
    }
    this.state = new DailyLearningState();
    this.state.dayKey = dayKey;
    this.state.reviewAllDone = true;
  }
}

export function parseDailyLearningState(raw: string): DailyLearningState {
  const out: DailyLearningState = new DailyLearningState();
  if (raw.length === 0) {
    return out;
  }
  let parsed: DailyLearningStateJson;
  try {
    parsed = JSON.parse(raw) as DailyLearningStateJson;
  } catch (err) {
    console.error(`parseDailyLearningState failed: ${JSON.stringify(err as BusinessError)}`);
    return out;
  }
  out.dayKey = typeof parsed.dayKey === 'string' ? parsed.dayKey : '';
  out.packBattleWon = parsed.packBattleWon === true;
  out.reviewSnapshot = parseDailyReviewSnapshot(parsed.reviewSnapshot);
  out.reviewAllDone = parsed.reviewAllDone === true || remainingReviewCount(out.reviewSnapshot) === 0;
  return out;
}

function parseDailyReviewSnapshot(raw?: DailyReviewSnapshotJson): DailyReviewSnapshot {
  const out: DailyReviewSnapshot = new DailyReviewSnapshot();
  if (raw === undefined || raw === null) {
    return out;
  }
  out.dayKey = typeof raw.dayKey === 'string' ? raw.dayKey : '';
  out.generatedAtMs = typeof raw.generatedAtMs === 'number' ? raw.generatedAtMs : 0;
  out.sourceCutoffMs = typeof raw.sourceCutoffMs === 'number' ? raw.sourceCutoffMs : 0;
  out.wordIds = stringArray(raw.wordIds);
  out.reviewedWordIds = filteredKnownIds(stringArray(raw.reviewedWordIds), out.wordIds);
  if (Array.isArray(raw.items)) {
    for (let i = 0; i < raw.items.length; i++) {
      const item: DailyReviewItem = parseDailyReviewItem(raw.items[i]);
      if (item.wordId.length > 0) {
        out.items.push(item);
      }
    }
  }
  return out;
}

function parseDailyReviewItem(raw: DailyReviewItemJson): DailyReviewItem {
  const out: DailyReviewItem = new DailyReviewItem();
  out.wordId = typeof raw.wordId === 'string' ? raw.wordId : '';
  out.reasons = parseReasons(raw.reasons);
  out.primaryReason = parseReason(raw.primaryReason, ReviewReason.DueReview);
  out.score = typeof raw.score === 'number' ? raw.score : 0;
  out.lastAnsweredMs = typeof raw.lastAnsweredMs === 'number' ? raw.lastAnsweredMs : 0;
  return out;
}

function buildReviewItem(
  wordId: string,
  stat: WordStat,
  sourceCutoffMs: number,
  selectedBoost: boolean,
): DailyReviewItem {
  const item: DailyReviewItem = new DailyReviewItem();
  item.wordId = wordId;
  item.lastAnsweredMs = stat.lastAnsweredMs;

  if (isDue(stat, sourceCutoffMs)) {
    item.reasons.push(ReviewReason.DueReview);
    item.score += 100;
    const overdueDays: number = Math.floor((sourceCutoffMs - stat.nextReviewMs) / DAY_MS);
    item.score += clampNumber(overdueDays, 0, 14) * 4;
  }
  if (isRecentWrong(stat, sourceCutoffMs)) {
    item.reasons.push(ReviewReason.RecentWrong);
    item.score += 80;
    const ageDays: number = Math.floor((sourceCutoffMs - stat.lastAnsweredMs) / DAY_MS);
    if (ageDays <= 1) {
      item.score += 20;
    } else if (ageDays <= 3) {
      item.score += 10;
    } else if (ageDays <= 7) {
      item.score += 5;
    }
  }
  if (isWeakWord(stat)) {
    item.reasons.push(ReviewReason.WeakWord);
    item.score += 50;
  }
  if (selectedBoost) {
    item.score += 5;
  }
  if (item.reasons.length > 0) {
    item.primaryReason = item.reasons[0];
  }
  return item;
}

function isDue(stat: WordStat, sourceCutoffMs: number): boolean {
  return stat.nextReviewMs > 0 && stat.nextReviewMs <= sourceCutoffMs;
}

function isRecentWrong(stat: WordStat, sourceCutoffMs: number): boolean {
  if (inferLastOutcome(stat) !== 'wrong') {
    return false;
  }
  return stat.lastAnsweredMs > 0 &&
    sourceCutoffMs - stat.lastAnsweredMs <= RECENT_WRONG_DAYS * DAY_MS;
}

function isWeakWord(stat: WordStat): boolean {
  if (stat.memoryState === MemoryState.Mastered) {
    return false;
  }
  if (stat.seenCount >= 3 && stat.correctCount / stat.seenCount < 0.6) {
    return true;
  }
  if (stat.wrongCount >= 2 && stat.correctCount <= stat.wrongCount) {
    return true;
  }
  return stat.seenCount >= 2 && stat.mastery <= 0.35;
}

function inferLastOutcome(stat: WordStat): string {
  if (stat.lastOutcome === 'correct' || stat.lastOutcome === 'wrong') {
    return stat.lastOutcome;
  }
  if (stat.consecutiveWrong > 0) {
    return 'wrong';
  }
  if (stat.consecutiveCorrect > 0) {
    return 'correct';
  }
  return 'unknown';
}

function remainingReviewCount(snapshot: DailyReviewSnapshot): number {
  const reviewed: Set<string> = toStringSet(snapshot.reviewedWordIds);
  let remaining: number = 0;
  for (let i = 0; i < snapshot.wordIds.length; i++) {
    if (!reviewed.has(snapshot.wordIds[i])) {
      remaining += 1;
    }
  }
  return remaining;
}

function localStartOfDay(nowMs: number): number {
  const d: Date = new Date(nowMs);
  const start: Date = new Date(d.getFullYear(), d.getMonth(), d.getDate(), 0, 0, 0, 0);
  return start.getTime();
}

function uniqueWordIds(words: WordEntry[]): string[] {
  const out: string[] = [];
  const seen: Set<string> = new Set<string>();
  for (let i = 0; i < words.length; i++) {
    const id: string = words[i].id;
    if (id.length > 0 && !seen.has(id)) {
      seen.add(id);
      out.push(id);
    }
  }
  return out;
}

function toStringSet(values: string[]): Set<string> {
  const out: Set<string> = new Set<string>();
  for (let i = 0; i < values.length; i++) {
    if (values[i].length > 0) {
      out.add(values[i]);
    }
  }
  return out;
}

function stringArray(values?: string[]): string[] {
  const out: string[] = [];
  if (!Array.isArray(values)) {
    return out;
  }
  for (let i = 0; i < values.length; i++) {
    if (typeof values[i] === 'string' && values[i].length > 0 && out.indexOf(values[i]) < 0) {
      out.push(values[i]);
    }
  }
  return out;
}

function filteredKnownIds(values: string[], knownIds: string[]): string[] {
  const known: Set<string> = toStringSet(knownIds);
  const out: string[] = [];
  for (let i = 0; i < values.length; i++) {
    if (known.has(values[i]) && out.indexOf(values[i]) < 0) {
      out.push(values[i]);
    }
  }
  return out;
}

function parseReasons(values?: string[]): ReviewReason[] {
  const out: ReviewReason[] = [];
  if (!Array.isArray(values)) {
    return out;
  }
  for (let i = 0; i < values.length; i++) {
    const reason: ReviewReason = parseReason(values[i], ReviewReason.DueReview);
    if (out.indexOf(reason) < 0) {
      out.push(reason);
    }
  }
  return out;
}

function parseReason(value: string | undefined, fallback: ReviewReason): ReviewReason {
  if (value === ReviewReason.RecentWrong) {
    return ReviewReason.RecentWrong;
  }
  if (value === ReviewReason.WeakWord) {
    return ReviewReason.WeakWord;
  }
  if (value === ReviewReason.DueReview) {
    return ReviewReason.DueReview;
  }
  return fallback;
}

function clampNumber(value: number, min: number, max: number): number {
  if (value < min || Number.isNaN(value)) {
    return min;
  }
  if (value > max) {
    return max;
  }
  return value;
}

function cloneDailyLearningState(src: DailyLearningState): DailyLearningState {
  const out: DailyLearningState = new DailyLearningState();
  out.dayKey = src.dayKey;
  out.packBattleWon = src.packBattleWon;
  out.reviewAllDone = src.reviewAllDone;
  out.reviewSnapshot = cloneDailyReviewSnapshot(src.reviewSnapshot);
  return out;
}

function cloneDailyReviewSnapshot(src: DailyReviewSnapshot): DailyReviewSnapshot {
  const out: DailyReviewSnapshot = new DailyReviewSnapshot();
  out.dayKey = src.dayKey;
  out.generatedAtMs = src.generatedAtMs;
  out.sourceCutoffMs = src.sourceCutoffMs;
  out.wordIds = src.wordIds.slice();
  out.reviewedWordIds = src.reviewedWordIds.slice();
  for (let i = 0; i < src.items.length; i++) {
    const item: DailyReviewItem = new DailyReviewItem();
    item.wordId = src.items[i].wordId;
    item.reasons = src.items[i].reasons.slice();
    item.primaryReason = src.items[i].primaryReason;
    item.score = src.items[i].score;
    item.lastAnsweredMs = src.items[i].lastAnsweredMs;
    out.items.push(item);
  }
  return out;
}

let globalDailyLearningStateService: DailyLearningStateService | undefined = undefined;

export function getDailyLearningStateService(): DailyLearningStateService {
  if (globalDailyLearningStateService === undefined) {
    globalDailyLearningStateService = new DailyLearningStateService();
  }
  return globalDailyLearningStateService;
}

export function __resetDailyLearningStateServiceForTest(): void {
  globalDailyLearningStateService = undefined;
}
