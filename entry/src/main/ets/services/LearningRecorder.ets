import { BusinessError } from '@ohos.base';
import { common } from '@kit.AbilityKit';
import {
  LearningSnapshot,
  WordStat,
  WrongAnswerStore,
  clampMastery,
  MASTERY_DELTA_CORRECT,
  MASTERY_DELTA_WRONG,
} from './WrongAnswerStore';
import { MemoryScheduler, MemoryState } from './MemoryScheduler';
import { CloudSyncLike } from './CloudSyncTypes';

const DEBOUNCE_MS: number = 100;

/**
 * LearningRecorder is the in-memory front of the V0.2 learning log.
 * BattlePage calls `recordAnswer` after every submission, ResultPage
 * reads `newlyLearnedCount` / `totalLearnedCount` for its footer, and
 * HomePage reads `recentWrongIds` to gate the review-mode button.
 *
 * Persistence strategy:
 * - Mutations land on the in-memory snapshot immediately so reads are
 *   synchronous and consistent.
 * - Each mutation schedules a 100 ms debounced flush through
 *   `WrongAnswerStore.save`. Rapid-fire answers therefore collapse into
 *   a single disk write per burst.
 * - `flushNow()` is exposed for deterministic unit tests and for
 *   aboutToDisappear paths that want a synchronous guarantee.
 *
 * Robustness:
 * - Until `init()` resolves successfully, `recordAnswer` mutates the
 *   in-memory snapshot but does not attempt to save. This keeps game
 *   logic decoupled from the slower preferences bootstrap.
 */
export class LearningRecorder {
  private store: WrongAnswerStore;
  private snapshot: LearningSnapshot = new LearningSnapshot();
  private ready: boolean = false;
  private saveTimer: number = -1;
  private sessionStartLearnedIds: Set<string> = new Set<string>();
  // Words that became "learned" inside the current session. A word is
  // learned the first time it is answered correctly; this lives in
  // memory only so HomePage can't accidentally spike the badge.
  private sessionNewlyLearnedIds: Set<string> = new Set<string>();
  /**
   * Monotonic tick used for tiebreaking recentWrongIds ordering when
   * multiple answers land in the same millisecond (common under the
   * sub-ms cadence of the ohosTest hypium runner). We read this
   * alongside `Date.now()` inside recordAnswer and fall back to it
   * when the primary timestamps collide.
   */
  private recordSequence: number = 0;
  private statSequence: Map<string, number> = new Map<string, number>();
  private scheduler: MemoryScheduler;
  private cloudSync?: CloudSyncLike;

  constructor(store?: WrongAnswerStore, scheduler?: MemoryScheduler) {
    this.store = store !== undefined ? store : new WrongAnswerStore();
    this.scheduler = scheduler !== undefined ? scheduler : new MemoryScheduler();
  }

  /**
   * Boot the recorder: open preferences, hydrate the in-memory
   * snapshot, capture which wordIds were already "learned" before
   * this session. Safe to call more than once; subsequent calls are
   * no-ops.
   */
  async init(ctx: common.UIAbilityContext): Promise<void> {
    if (this.ready) {
      return;
    }
    try {
      await this.store.open(ctx);
      const loaded: LearningSnapshot = await this.store.load();
      this.snapshot = loaded;
    } catch (err) {
      console.error(`LearningRecorder.init failed: ${JSON.stringify(err as BusinessError)}`);
      this.snapshot = new LearningSnapshot();
    }
    this.sessionStartLearnedIds = this.computeLearnedIdSet();
    this.ready = true;
  }

  /** V0.6.4: register the cloud-sync companion. Pass `undefined` to
   *  detach (used by tests + by binding-removed flow). */
  attachCloudSync(svc?: CloudSyncLike): void {
    this.cloudSync = svc;
  }

  /** V0.6.4: read-only accessor used by pages that want to peek at the
   *  attached sync service (e.g. ConfigPage's manual-sync button). */
  getCloudSync(): CloudSyncLike | undefined {
    return this.cloudSync;
  }

  /** Used by unit tests to install a pre-configured store. */
  attachStore(store: WrongAnswerStore, snapshot: LearningSnapshot): void {
    this.store = store;
    this.snapshot = snapshot;
    this.sessionStartLearnedIds = this.computeLearnedIdSet();
    this.ready = true;
  }

  /**
   * Reset per-session counters. Call when a new battle starts so the
   * ResultPage footer only counts words learned in THAT battle.
   */
  beginSession(): void {
    this.sessionStartLearnedIds = this.computeLearnedIdSet();
    this.sessionNewlyLearnedIds.clear();
  }

  /**
   * Record a single answer. Updates counters, schedules a debounced
   * flush, and marks the word as newly-learned if this is the first
   * correct answer we've seen for it.
   */
  recordAnswer(wordId: string, correct: boolean): void {
    if (wordId.length === 0) {
      return;
    }
    const stat: WordStat = this.findOrCreateStat(wordId);
    const wasLearned: boolean = this.sessionStartLearnedIds.has(wordId);
    stat.seenCount += 1;
    if (correct) {
      stat.correctCount += 1;
      // V0.4.3 streaks + mastery: bump consecutiveCorrect, reset
      // wrong streak, raise mastery by the asymmetric delta.
      stat.consecutiveCorrect += 1;
      stat.consecutiveWrong = 0;
      stat.mastery = clampMastery(stat.mastery + MASTERY_DELTA_CORRECT);
      if (!wasLearned) {
        this.sessionNewlyLearnedIds.add(wordId);
      }
    } else {
      stat.wrongCount += 1;
      stat.consecutiveWrong += 1;
      stat.consecutiveCorrect = 0;
      stat.mastery = clampMastery(stat.mastery - MASTERY_DELTA_WRONG);
    }
    stat.lastAnsweredMs = Date.now();
    this.recordSequence += 1;
    this.statSequence.set(wordId, this.recordSequence);
    this.scheduler.applyAnswer(stat, correct, stat.lastAnsweredMs);
    this.snapshot.version = 3;
    this.scheduleSave();
  }

  /**
   * Return wordIds whose current MemoryState (with due-check) matches
   * `state`, most-recent-first by lastAnsweredMs. New (unseen) words
   * cannot be enumerated here because the recorder only knows about
   * wordIds it has observed; callers needing every "new" wordId must
   * combine this with their own word universe.
   */
  wordIdsByMemoryState(state: MemoryState, limit: number, nowMs: number): string[] {
    if (limit <= 0) {
      return [];
    }
    const out: string[] = [];
    const stats: WordStat[] = this.snapshot.stats.slice();
    stats.sort((a: WordStat, b: WordStat): number => b.lastAnsweredMs - a.lastAnsweredMs);
    for (let i = 0; i < stats.length && out.length < limit; i++) {
      if (this.scheduler.classify(stats[i], nowMs) === state) {
        out.push(stats[i].wordId);
      }
    }
    return out;
  }

  /** Test seam — assert the snapshot version after recordAnswer ran. */
  snapshotVersionForTest(): number {
    return this.snapshot.version;
  }

  /**
   * Read the in-memory stats list. Test seam used by both the unit
   * tests and TodayAdventureBuilder so the latter does not need a
   * private accessor on WrongAnswerStore.
   */
  statsForTest(): WordStat[] {
    return this.snapshot.stats.slice();
  }

  /** V0.6.4: cloud-sync read accessor. Mirrors `statsForTest` but
   *  exposed under a non-test name so production code (CloudSyncService)
   *  can call it without an obvious smell. */
  allStats(): WordStat[] {
    return this.snapshot.stats.slice();
  }

  /** V0.6.4: apply a single LWW pull from the cloud sync service.
   *  Replaces the matching wordId entry when `lastAnsweredMs` strictly
   *  exceeds the local one, otherwise the call is a no-op. The mutation
   *  is debounced through the same timer as `recordAnswer` so the
   *  on-disk snapshot eventually reflects the cloud pull. */
  applyCloudPull(stat: WordStat): boolean {
    const idx: number = this.snapshot.stats.findIndex(
      (s: WordStat): boolean => s.wordId === stat.wordId,
    );
    if (idx < 0) {
      this.snapshot.stats.push(stat);
      this.scheduleSave();
      return true;
    }
    const local: WordStat = this.snapshot.stats[idx];
    if (stat.lastAnsweredMs <= local.lastAnsweredMs) {
      return false;
    }
    this.snapshot.stats[idx] = stat;
    this.scheduleSave();
    return true;
  }

  /**
   * Return the most-recent `limit` wordIds whose latest outcome was
   * wrong. De-duplicated and ordered most-recent-first so the review
   * pool surfaces the word the learner just missed.
   */
  recentWrongIds(limit: number): string[] {
    if (limit <= 0) {
      return [];
    }
    const candidates: WordStat[] = this.snapshot.stats
      .filter((s: WordStat): boolean => s.wrongCount > 0)
      .slice();
    candidates.sort((a: WordStat, b: WordStat): number => {
      if (b.lastAnsweredMs !== a.lastAnsweredMs) {
        return b.lastAnsweredMs - a.lastAnsweredMs;
      }
      // Two recordAnswer calls inside the same ms: prefer the
      // later-sequenced one. Unknown words fall back to 0 so
      // snapshot-loaded-from-disk entries still sort by timestamp.
      const seqA: number = this.statSequence.has(a.wordId)
        ? (this.statSequence.get(a.wordId) as number) : 0;
      const seqB: number = this.statSequence.has(b.wordId)
        ? (this.statSequence.get(b.wordId) as number) : 0;
      return seqB - seqA;
    });
    const out: string[] = [];
    for (let i = 0; i < candidates.length && out.length < limit; i++) {
      const id: string = candidates[i].wordId;
      if (out.indexOf(id) < 0) {
        out.push(id);
      }
    }
    return out;
  }

  /** Count of words that crossed 0→1 correctness in the current session. */
  get newlyLearnedCount(): number {
    return this.sessionNewlyLearnedIds.size;
  }

  /** Total count of distinct words ever answered correctly at least once. */
  get totalLearnedCount(): number {
    return this.computeLearnedIdSet().size;
  }

  /** Drop all stats. Useful for tests and for a future "reset" button. */
  async clear(): Promise<void> {
    this.snapshot = new LearningSnapshot();
    this.sessionStartLearnedIds.clear();
    this.sessionNewlyLearnedIds.clear();
    await this.flushNow();
  }

  /**
   * Force the debounced save to happen immediately. Resolves once the
   * store has acknowledged the flush. Never throws.
   */
  async flushNow(): Promise<void> {
    if (this.saveTimer >= 0) {
      clearTimeout(this.saveTimer);
      this.saveTimer = -1;
    }
    if (!this.ready) {
      return;
    }
    try {
      await this.store.save(this.snapshot);
    } catch (err) {
      console.error(`LearningRecorder.flushNow failed: ${JSON.stringify(err as BusinessError)}`);
    }
    // V0.6.4 fire-and-forget cloud sync. Failures are swallowed by the
    // sync service itself, so we deliberately don't await the promise:
    // a parent web reload should not block the flush.
    if (this.cloudSync !== undefined) {
      this.cloudSync.syncOnce().catch((err: BusinessError): void => {
        console.error(`LearningRecorder.flushNow cloud sync: ${JSON.stringify(err)}`);
      });
    }
  }

  private findOrCreateStat(wordId: string): WordStat {
    for (let i = 0; i < this.snapshot.stats.length; i++) {
      if (this.snapshot.stats[i].wordId === wordId) {
        return this.snapshot.stats[i];
      }
    }
    const fresh: WordStat = new WordStat();
    fresh.wordId = wordId;
    this.snapshot.stats.push(fresh);
    return fresh;
  }

  private computeLearnedIdSet(): Set<string> {
    const learned: Set<string> = new Set<string>();
    for (let i = 0; i < this.snapshot.stats.length; i++) {
      const s: WordStat = this.snapshot.stats[i];
      if (s.correctCount > 0) {
        learned.add(s.wordId);
      }
    }
    return learned;
  }

  private scheduleSave(): void {
    if (!this.ready) {
      return;
    }
    if (this.saveTimer >= 0) {
      clearTimeout(this.saveTimer);
    }
    this.saveTimer = setTimeout((): void => {
      this.saveTimer = -1;
      this.store.save(this.snapshot).catch((err: BusinessError): void => {
        console.error(`LearningRecorder scheduled save failed: ${JSON.stringify(err)}`);
      });
    }, DEBOUNCE_MS);
  }
}

/**
 * Singleton-style getter used by pages that don't have access to the
 * UIAbility's scoped instance. Keeps a single in-memory snapshot
 * across HomePage / BattlePage / ResultPage without requiring them
 * all to share an AppStorage key.
 */
let globalRecorder: LearningRecorder | undefined = undefined;

export function getLearningRecorder(): LearningRecorder {
  if (globalRecorder === undefined) {
    globalRecorder = new LearningRecorder();
  }
  return globalRecorder;
}

/** Test-only reset hook. Clears the singleton so each test starts fresh. */
export function __resetLearningRecorderForTest(): void {
  globalRecorder = undefined;
}
