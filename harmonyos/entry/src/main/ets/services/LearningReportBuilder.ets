import { WordEntry } from '../models/WordEntry';
import { Pack } from '../models/Pack';
import { PackLibrary } from './PackLibrary';
import { LearningRecorder } from './LearningRecorder';
import { MemoryScheduler, MemoryState } from './MemoryScheduler';
import { WordStat } from './WrongAnswerStore';
import { localStartOfDay } from './TodayPlanService';

/**
 * One pack row in the learning report. The page renders these
 * verbatim into the pack-breakdown table. Replaces V0.4.5's
 * CategoryReport (the category dimension has zero remaining UX
 * surface since V0.6.6 removed the category picker from
 * ConfigPage; HomePage chips, PackManagerPage, and BattlePage
 * today-mode all key on packs).
 */
export class PackReport {
  packId: string = '';
  name: string = '';
  totalSeen: number = 0;
  totalCorrect: number = 0;
  /** 0..100, rounded to integer. 0 when totalSeen === 0. */
  accuracyPct: number = 0;
  /** Mirrors PackSelectionService.getActiveIds().has(packId). */
  active: boolean = false;
}

/**
 * Aggregate snapshot of learning progress so far. Pure data, no
 * methods that mutate. The page reads each field directly into
 * ArkUI components.
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
  /**
   * One row per pack. Order: active packs first (in selection
   * order), then inactive-but-seen packs sorted by accuracyPct
   * ascending. See LearningReportBuilder.build for the rules.
   */
  packs: PackReport[] = [];
}

/**
 * Pure builder for the V0.6.7.8 learning report. No persistence,
 * no I/O — feed it the in-memory PackLibrary, the active-id list,
 * and the initialised recorder; receive a `LearningReport`.
 *
 * V0.4.5 keyed reports by category; the V0.6.7.8 rewrite keys by
 * pack to align with the V0.6.5 three-layer pack model. See
 * docs/superpowers/specs/2026-05-10-learning-report-by-pack-design.md
 * for the rules around per-pack independent counting and top-level
 * dedup-by-stat-iteration.
 */
export class LearningReportBuilder {
  private scheduler: MemoryScheduler;

  constructor(scheduler?: MemoryScheduler) {
    this.scheduler = scheduler !== undefined ? scheduler : new MemoryScheduler();
  }

  build(
    library: PackLibrary,
    activeIds: string[],
    recorder: LearningRecorder,
    nowMs: number,
  ): LearningReport {
    const stats: WordStat[] = recorder.statsForTest();
    const statByWordId: Map<string, WordStat> = new Map<string, WordStat>();
    for (let i: number = 0; i < stats.length; i++) {
      statByWordId.set(stats[i].wordId, stats[i]);
    }

    const startOfDay: number = localStartOfDay(nowMs);
    const allPacks: Pack[] = library.allPacks();
    const activeSet: Set<string> = new Set<string>();
    for (let i: number = 0; i < activeIds.length; i++) activeSet.add(activeIds[i]);

    // Collect every wordId that is reachable from the library union.
    // Stats whose wordId is not in this set are orphaned (the pack
    // that owned them was removed) and are ignored at the top level.
    const knownWordIds: Set<string> = new Set<string>();
    for (let i: number = 0; i < allPacks.length; i++) {
      const ws: WordEntry[] = allPacks[i].words;
      for (let j: number = 0; j < ws.length; j++) knownWordIds.add(ws[j].id);
    }

    const report: LearningReport = new LearningReport();
    report.totalWords = knownWordIds.size;

    // ----- Top-level totals + state buckets: iterate STATS once.
    // Each stat record is unique-per-wordId by construction
    // (LearningRecorder guarantees this), so summing here naturally
    // dedupes across packs that share a word. Stats whose wordId is
    // orphaned (no pack contains it anymore) are skipped.
    let totalSeen: number = 0;
    let totalCorrect: number = 0;
    let learningCount: number = 0;
    let familiarCount: number = 0;
    let masteredCount: number = 0;
    let reviewDue: number = 0;
    let reviewDoneToday: number = 0;
    let newFromStats: number = 0;
    for (let i: number = 0; i < stats.length; i++) {
      const stat: WordStat = stats[i];
      if (!knownWordIds.has(stat.wordId)) continue;
      totalSeen += stat.seenCount;
      totalCorrect += stat.correctCount;
      const state: MemoryState = this.scheduler.classify(stat, nowMs);
      if (state === MemoryState.New) {
        newFromStats += 1;
      } else if (state === MemoryState.Mastered) {
        masteredCount += 1;
      } else if (state === MemoryState.Familiar) {
        familiarCount += 1;
      } else if (state === MemoryState.Review) {
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

    // Words in the library union with no stat record are "new".
    let unseenInLibrary: number = 0;
    knownWordIds.forEach((id: string): void => {
      if (!statByWordId.has(id)) unseenInLibrary += 1;
    });

    report.totalSeen = totalSeen;
    report.totalCorrect = totalCorrect;
    report.accuracyPct = totalSeen > 0
      ? Math.round((totalCorrect * 100) / totalSeen)
      : 0;
    report.newCount = newFromStats + unseenInLibrary;
    report.learningCount = learningCount;
    report.familiarCount = familiarCount;
    report.masteredCount = masteredCount;
    report.reviewDueCount = reviewDue;
    report.reviewDoneTodayCount = reviewDoneToday;
    const denom: number = Math.max(reviewDue, reviewDoneToday);
    report.reviewCompletionPct = denom > 0
      ? Math.round((reviewDoneToday * 100) / denom)
      : 0;

    // ----- Per-pack rows: iterate each pack's words, look up stats.
    // A word in N active packs counts toward each row independently
    // (per-pack independent counting); the top-level above already
    // deduped via the stats-list iteration so this can't double-
    // count globally.
    const allRows: PackReport[] = [];
    for (let i: number = 0; i < allPacks.length; i++) {
      const pack: Pack = allPacks[i];
      const isActive: boolean = activeSet.has(pack.id);
      const row: PackReport = new PackReport();
      row.packId = pack.id;
      row.name = pack.name;
      row.active = isActive;
      for (let j: number = 0; j < pack.words.length; j++) {
        const stat: WordStat | undefined = statByWordId.get(pack.words[j].id);
        if (stat !== undefined) {
          row.totalSeen += stat.seenCount;
          row.totalCorrect += stat.correctCount;
        }
      }
      if (isActive || row.totalSeen > 0) {
        row.accuracyPct = row.totalSeen > 0
          ? Math.round((row.totalCorrect * 100) / row.totalSeen)
          : 0;
        allRows.push(row);
      }
    }

    // Sort: active first (in activeIds order), then inactive by
    // accuracy ascending. Use simple O(n) lookups since n is small
    // (active <= MAX_ACTIVE_PACKS = 10; inactive depends on family
    // pack count, typically < 10).
    const orderedActive: PackReport[] = [];
    for (let i: number = 0; i < activeIds.length; i++) {
      for (let j: number = 0; j < allRows.length; j++) {
        if (allRows[j].active && allRows[j].packId === activeIds[i]) {
          orderedActive.push(allRows[j]);
          break;
        }
      }
    }
    const inactiveRows: PackReport[] = [];
    for (let i: number = 0; i < allRows.length; i++) {
      if (!allRows[i].active) inactiveRows.push(allRows[i]);
    }
    // Selection sort by accuracyPct ascending — keeps stable ordering
    // across ArkTS environments (Array.sort stability is undefined
    // for our oldest supported runtime).
    for (let i: number = 0; i < inactiveRows.length; i++) {
      let minIdx: number = i;
      for (let j: number = i + 1; j < inactiveRows.length; j++) {
        if (inactiveRows[j].accuracyPct < inactiveRows[minIdx].accuracyPct) {
          minIdx = j;
        }
      }
      if (minIdx !== i) {
        const tmp: PackReport = inactiveRows[i];
        inactiveRows[i] = inactiveRows[minIdx];
        inactiveRows[minIdx] = tmp;
      }
    }
    for (let i: number = 0; i < orderedActive.length; i++) {
      report.packs.push(orderedActive[i]);
    }
    for (let i: number = 0; i < inactiveRows.length; i++) {
      report.packs.push(inactiveRows[i]);
    }
    return report;
  }
}
