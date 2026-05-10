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
    // V0.6.7.8 stub — the next commit replaces this with the real
    // aggregation logic. Leaving it as an empty report keeps the
    // module buildable so the unit-test refactor can land first.
    const report: LearningReport = new LearningReport();
    return report;
  }
}
