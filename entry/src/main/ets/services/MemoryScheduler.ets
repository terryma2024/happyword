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
      if (stat.correctCount >= PROMOTE_TO_FAMILIAR_AT) {
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
      if (stat.correctCount >= PROMOTE_TO_MASTERED_AT) {
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
