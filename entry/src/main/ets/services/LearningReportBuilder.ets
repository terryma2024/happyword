import { WordEntry } from '../models/WordEntry';
import { WordRepository } from './WordRepository';
import { LearningRecorder } from './LearningRecorder';
import { MemoryScheduler, MemoryState } from './MemoryScheduler';
import { WordStat } from './WrongAnswerStore';
import { localStartOfDay } from './TodayPlanService';

/**
 * One category row in the learning report. The page renders these
 * verbatim — both as "weak categories" highlights and as a full
 * breakdown table when the kid scrolls.
 */
export class CategoryReport {
  category: string = '';
  displayName: string = '';
  totalSeen: number = 0;
  totalCorrect: number = 0;
  /** 0..100, rounded to integer. 0 when totalSeen === 0. */
  accuracyPct: number = 0;
}

/**
 * Aggregate snapshot of learning progress so far. Pure data, no
 * methods that mutate. The page reads each field directly into ArkUI
 * components.
 */
export class LearningReport {
  totalWords: number = 0;
  totalSeen: number = 0;
  totalCorrect: number = 0;
  /** 0..100, rounded to integer. 0 when totalSeen === 0. */
  accuracyPct: number = 0;
  newCount: number = 0;
  learningCount: number = 0;
  familiarCount: number = 0;
  masteredCount: number = 0;
  reviewDueCount: number = 0;
  reviewDoneTodayCount: number = 0;
  /** 0..100. `done / max(due, done)` so it never exceeds 100. */
  reviewCompletionPct: number = 0;
  categories: CategoryReport[] = [];
  /**
   * Up to 3 weakest categories (lowest accuracy first). Excludes
   * categories with zero seen words. Empty when no data.
   */
  weakCategories: CategoryReport[] = [];
}

/**
 * Display label for a category id. Localised here rather than
 * embedded in `WordEntry` so the report layer can iterate without
 * needing a translation map injected from outside.
 */
export function describeCategory(category: string): string {
  if (category === 'fruit') return '水果';
  if (category === 'place') return '地点';
  if (category === 'home') return '家庭';
  return category;
}

/**
 * Pure builder for the V0.4.5 learning report. No persistence,
 * no I/O — feed it the loaded repo + initialised recorder and
 * receive a `LearningReport`.
 */
export class LearningReportBuilder {
  private scheduler: MemoryScheduler;

  constructor(scheduler?: MemoryScheduler) {
    this.scheduler = scheduler !== undefined ? scheduler : new MemoryScheduler();
  }

  build(repo: WordRepository, recorder: LearningRecorder, nowMs: number): LearningReport {
    const all: WordEntry[] = repo.all();
    const stats: WordStat[] = recorder.statsForTest();
    const statByWordId: Map<string, WordStat> = new Map<string, WordStat>();
    for (let i = 0; i < stats.length; i++) {
      statByWordId.set(stats[i].wordId, stats[i]);
    }

    const startOfDay: number = localStartOfDay(nowMs);
    const report: LearningReport = new LearningReport();
    report.totalWords = all.length;

    // Per-category aggregator. Map preserves insertion order so the
    // category list comes out in the same order as the bundled
    // dictionary, which matches user expectation.
    const catMap: Map<string, CategoryReport> = new Map<string, CategoryReport>();
    for (let i = 0; i < all.length; i++) {
      const w: WordEntry = all[i];
      if (!catMap.has(w.category)) {
        const cat: CategoryReport = new CategoryReport();
        cat.category = w.category;
        cat.displayName = describeCategory(w.category);
        catMap.set(w.category, cat);
      }
    }

    let totalSeen: number = 0;
    let totalCorrect: number = 0;
    let newCount: number = 0;
    let learningCount: number = 0;
    let familiarCount: number = 0;
    let masteredCount: number = 0;
    let reviewDue: number = 0;
    let reviewDoneToday: number = 0;

    for (let i = 0; i < all.length; i++) {
      const w: WordEntry = all[i];
      const stat: WordStat | undefined = statByWordId.get(w.id);
      const cat: CategoryReport = catMap.get(w.category) as CategoryReport;
      if (stat === undefined) {
        newCount += 1;
        continue;
      }
      totalSeen += stat.seenCount;
      totalCorrect += stat.correctCount;
      cat.totalSeen += stat.seenCount;
      cat.totalCorrect += stat.correctCount;
      const state: MemoryState = this.scheduler.classify(stat, nowMs);
      if (state === MemoryState.New) {
        newCount += 1;
      } else if (state === MemoryState.Mastered) {
        masteredCount += 1;
      } else if (state === MemoryState.Familiar) {
        familiarCount += 1;
      } else if (state === MemoryState.Review) {
        // Review state means due — count toward review pool.
        reviewDue += 1;
        learningCount += 1;
      } else {
        learningCount += 1;
      }
      const isReviewable: boolean =
        stat.seenCount > 0 && stat.lastAnsweredMs < startOfDay;
      if (isReviewable && stat.lastAnsweredMs >= 0 && state !== MemoryState.New) {
        // Already counted reviewDue above for due state; widen the
        // review-eligible pool to include any seen-before-today
        // word so the "review completion" bar reflects the kid's
        // total reach rather than only urgent items.
        if (state !== MemoryState.Review) {
          reviewDue += 1;
        }
      }
      const doneToday: boolean =
        stat.lastAnsweredMs >= startOfDay && stat.consecutiveCorrect > 0;
      if (doneToday) {
        reviewDoneToday += 1;
      }
    }

    report.totalSeen = totalSeen;
    report.totalCorrect = totalCorrect;
    report.accuracyPct = totalSeen > 0
      ? Math.round((totalCorrect * 100) / totalSeen)
      : 0;
    report.newCount = newCount;
    report.learningCount = learningCount;
    report.familiarCount = familiarCount;
    report.masteredCount = masteredCount;
    report.reviewDueCount = reviewDue;
    report.reviewDoneTodayCount = reviewDoneToday;
    const denom: number = Math.max(reviewDue, reviewDoneToday);
    report.reviewCompletionPct = denom > 0
      ? Math.round((reviewDoneToday * 100) / denom)
      : 0;

    // Finalise per-category accuracy rounding then build weakCats.
    const cats: CategoryReport[] = [];
    catMap.forEach((cat: CategoryReport): void => {
      cat.accuracyPct = cat.totalSeen > 0
        ? Math.round((cat.totalCorrect * 100) / cat.totalSeen)
        : 0;
      cats.push(cat);
    });
    report.categories = cats;
    report.weakCategories = pickWeakCategories(cats, 3);
    return report;
  }
}

/**
 * Sort `cats` by accuracy ascending and return up to `n` entries,
 * skipping those with no data. Stable order across calls (iteration
 * order from the parent Map preserves dictionary order, then
 * sort ties keep that order).
 */
function pickWeakCategories(cats: CategoryReport[], n: number): CategoryReport[] {
  const eligible: CategoryReport[] = [];
  for (let i = 0; i < cats.length; i++) {
    if (cats[i].totalSeen > 0) {
      eligible.push(cats[i]);
    }
  }
  // Selection sort to keep stable behaviour deterministic across
  // ArkTS environments. Plain Array.prototype.sort is stable in
  // modern engines but we don't want to rely on that.
  const sorted: CategoryReport[] = eligible.slice();
  for (let i = 0; i < sorted.length; i++) {
    let minIdx: number = i;
    for (let j = i + 1; j < sorted.length; j++) {
      if (sorted[j].accuracyPct < sorted[minIdx].accuracyPct) {
        minIdx = j;
      }
    }
    if (minIdx !== i) {
      const tmp: CategoryReport = sorted[i];
      sorted[i] = sorted[minIdx];
      sorted[minIdx] = tmp;
    }
  }
  return sorted.slice(0, n);
}
