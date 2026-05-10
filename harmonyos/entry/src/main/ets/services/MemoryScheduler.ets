import { WordStat } from './WrongAnswerStore';

export enum MemoryState {
  New = 'new',
  Learning = 'learning',
  Review = 'review',
  Familiar = 'familiar',
  Mastered = 'mastered',
}

export const INTERVAL_30_MIN_MS: number = 30 * 60 * 1000;
export const INTERVAL_1_DAY_MS: number = 24 * 3600 * 1000;
export const INTERVAL_3_DAY_MS: number = 3 * INTERVAL_1_DAY_MS;
export const INTERVAL_14_DAY_MS: number = 14 * INTERVAL_1_DAY_MS;

const PROMOTE_TO_FAMILIAR_AT: number = 2;
const PROMOTE_TO_MASTERED_AT: number = 5;
/**
 * V0.4.3: legacy fallback thresholds in case a snapshot was migrated
 * from before the streak counters existed (consecutiveCorrect = 0
 * even though correctCount may be larger). For migrated entries we
 * still respect the cumulative correctCount so a long-learned word
 * doesn't snap back to "learning" forever after the upgrade. The
 * thresholds are deliberately stricter than the streak ones since
 * cumulative count is a weaker signal of mastery.
 */
const LEGACY_FAMILIAR_CORRECT_AT: number = 4;
const LEGACY_MASTERED_CORRECT_AT: number = 10;

/**
 * Pure state-machine that decides the next memoryState +
 * nextReviewMs after a single answer. LearningRecorder feeds this
 * with the WordStat after it has bumped seen/correct/wrong, so
 * the scheduler can read the latest correctCount when picking
 * promotion thresholds.
 */
export class MemoryScheduler {
  applyAnswer(stat: WordStat, correct: boolean, nowMs: number): void {
    const current: MemoryState = this.coerceState(stat.memoryState);
    if (correct) {
      stat.lastCorrectMs = nowMs;
      this.applyCorrect(stat, current, nowMs);
    } else {
      this.applyWrong(stat, nowMs);
    }
  }

  classify(stat: WordStat, nowMs: number): MemoryState {
    if (stat.nextReviewMs > 0 && stat.nextReviewMs <= nowMs) {
      return MemoryState.Review;
    }
    return this.coerceState(stat.memoryState);
  }

  private applyCorrect(stat: WordStat, current: MemoryState, nowMs: number): void {
    if (current === MemoryState.New) {
      stat.memoryState = MemoryState.Learning;
      stat.nextReviewMs = nowMs + INTERVAL_1_DAY_MS;
      return;
    }
    if (current === MemoryState.Learning) {
      if (this.qualifiesForFamiliar(stat)) {
        stat.memoryState = MemoryState.Familiar;
        stat.nextReviewMs = nowMs + INTERVAL_3_DAY_MS;
      } else {
        stat.nextReviewMs = nowMs + INTERVAL_1_DAY_MS;
      }
      return;
    }
    if (current === MemoryState.Review) {
      stat.memoryState = MemoryState.Learning;
      stat.nextReviewMs = nowMs + INTERVAL_1_DAY_MS;
      return;
    }
    if (current === MemoryState.Familiar) {
      if (this.qualifiesForMastered(stat)) {
        stat.memoryState = MemoryState.Mastered;
        stat.nextReviewMs = nowMs + INTERVAL_14_DAY_MS;
      } else {
        stat.nextReviewMs = nowMs + INTERVAL_3_DAY_MS;
      }
      return;
    }
    // Mastered: stay put on continued correct answers, refresh schedule.
    stat.nextReviewMs = nowMs + INTERVAL_14_DAY_MS;
  }

  /**
   * V0.4.3: promote to Familiar when the player has built a recent
   * streak (preferred signal) OR has accumulated enough cumulative
   * correct answers (legacy fallback for snapshots migrated from
   * before consecutiveCorrect existed).
   */
  private qualifiesForFamiliar(stat: WordStat): boolean {
    if (stat.consecutiveCorrect >= PROMOTE_TO_FAMILIAR_AT) {
      return true;
    }
    return stat.correctCount >= LEGACY_FAMILIAR_CORRECT_AT;
  }

  private qualifiesForMastered(stat: WordStat): boolean {
    if (stat.consecutiveCorrect >= PROMOTE_TO_MASTERED_AT) {
      return true;
    }
    return stat.correctCount >= LEGACY_MASTERED_CORRECT_AT;
  }

  private applyWrong(stat: WordStat, nowMs: number): void {
    stat.memoryState = MemoryState.Review;
    stat.nextReviewMs = nowMs + INTERVAL_30_MIN_MS;
  }

  private coerceState(label: string): MemoryState {
    if (label === MemoryState.Learning) return MemoryState.Learning;
    if (label === MemoryState.Review) return MemoryState.Review;
    if (label === MemoryState.Familiar) return MemoryState.Familiar;
    if (label === MemoryState.Mastered) return MemoryState.Mastered;
    return MemoryState.New;
  }
}
