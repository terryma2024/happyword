import { describe, it, expect } from '@ohos/hypium';
import { WordStat } from '../main/ets/services/WrongAnswerStore';
import {
  MemoryScheduler,
  MemoryState,
  INTERVAL_30_MIN_MS,
  INTERVAL_1_DAY_MS,
  INTERVAL_3_DAY_MS,
  INTERVAL_14_DAY_MS,
} from '../main/ets/services/MemoryScheduler';

function freshStat(state: MemoryState): WordStat {
  const s: WordStat = new WordStat();
  s.wordId = 'w';
  s.memoryState = state;
  return s;
}

const NOW: number = 10_000_000_000;

export default function memorySchedulerTest() {
  describe('MemoryScheduler.applyAnswer', () => {
    it('newCorrectMovesToLearningWithOneDayInterval', 0, () => {
      const s: WordStat = freshStat(MemoryState.New);
      new MemoryScheduler().applyAnswer(s, true, NOW);
      expect(s.memoryState).assertEqual(MemoryState.Learning);
      expect(s.nextReviewMs).assertEqual(NOW + INTERVAL_1_DAY_MS);
      expect(s.lastCorrectMs).assertEqual(NOW);
    });

    it('newWrongMovesToReviewWith30Min', 0, () => {
      const s: WordStat = freshStat(MemoryState.New);
      new MemoryScheduler().applyAnswer(s, false, NOW);
      expect(s.memoryState).assertEqual(MemoryState.Review);
      expect(s.nextReviewMs).assertEqual(NOW + INTERVAL_30_MIN_MS);
    });

    it('learningSecondConsecutiveCorrectPromotesToFamiliarWith3Day', 0, () => {
      const s: WordStat = freshStat(MemoryState.Learning);
      s.consecutiveCorrect = 2;
      s.correctCount = 2;
      new MemoryScheduler().applyAnswer(s, true, NOW);
      expect(s.memoryState).assertEqual(MemoryState.Familiar);
      expect(s.nextReviewMs).assertEqual(NOW + INTERVAL_3_DAY_MS);
    });

    it('learningFirstConsecutiveCorrectStaysLearning', 0, () => {
      const s: WordStat = freshStat(MemoryState.Learning);
      s.consecutiveCorrect = 1;
      s.correctCount = 1;
      new MemoryScheduler().applyAnswer(s, true, NOW);
      expect(s.memoryState).assertEqual(MemoryState.Learning);
      expect(s.nextReviewMs).assertEqual(NOW + INTERVAL_1_DAY_MS);
    });

    it('learningHighCorrectCountWithoutStreakStaysLearningUntilLegacyThreshold', 0, () => {
      // V0.4.3 regression guard: a kid who answers right-then-wrong
      // repeatedly should NOT be promoted just because correctCount
      // crossed the old threshold of 2. We require either a real
      // streak or a much larger cumulative count for legacy data.
      const s: WordStat = freshStat(MemoryState.Learning);
      s.consecutiveCorrect = 1;
      s.correctCount = 3;
      new MemoryScheduler().applyAnswer(s, true, NOW);
      expect(s.memoryState).assertEqual(MemoryState.Learning);
      expect(s.nextReviewMs).assertEqual(NOW + INTERVAL_1_DAY_MS);
    });

    it('learningLegacyMigrationStillPromotesAtLegacyThreshold', 0, () => {
      // Snapshot migrated from before streaks existed: consecutive
      // counters are 0 even though the player clearly knows the word
      // (correctCount = 4). The legacy fallback path should still
      // promote so we don't regress upgraded users.
      const s: WordStat = freshStat(MemoryState.Learning);
      s.consecutiveCorrect = 0;
      s.correctCount = 4;
      new MemoryScheduler().applyAnswer(s, true, NOW);
      expect(s.memoryState).assertEqual(MemoryState.Familiar);
      expect(s.nextReviewMs).assertEqual(NOW + INTERVAL_3_DAY_MS);
    });

    it('reviewCorrectMovesBackToLearning', 0, () => {
      const s: WordStat = freshStat(MemoryState.Review);
      new MemoryScheduler().applyAnswer(s, true, NOW);
      expect(s.memoryState).assertEqual(MemoryState.Learning);
      expect(s.nextReviewMs).assertEqual(NOW + INTERVAL_1_DAY_MS);
    });

    it('reviewWrongStaysReview', 0, () => {
      const s: WordStat = freshStat(MemoryState.Review);
      new MemoryScheduler().applyAnswer(s, false, NOW);
      expect(s.memoryState).assertEqual(MemoryState.Review);
      expect(s.nextReviewMs).assertEqual(NOW + INTERVAL_30_MIN_MS);
    });

    it('familiarFifthConsecutiveCorrectPromotesToMastered', 0, () => {
      const s: WordStat = freshStat(MemoryState.Familiar);
      s.consecutiveCorrect = 5;
      s.correctCount = 5;
      new MemoryScheduler().applyAnswer(s, true, NOW);
      expect(s.memoryState).assertEqual(MemoryState.Mastered);
      expect(s.nextReviewMs).assertEqual(NOW + INTERVAL_14_DAY_MS);
    });

    it('familiarLegacyMigrationPromotesAtLegacyThreshold', 0, () => {
      const s: WordStat = freshStat(MemoryState.Familiar);
      s.consecutiveCorrect = 0;
      s.correctCount = 10;
      new MemoryScheduler().applyAnswer(s, true, NOW);
      expect(s.memoryState).assertEqual(MemoryState.Mastered);
      expect(s.nextReviewMs).assertEqual(NOW + INTERVAL_14_DAY_MS);
    });

    it('familiarWrongDropsToReview', 0, () => {
      const s: WordStat = freshStat(MemoryState.Familiar);
      new MemoryScheduler().applyAnswer(s, false, NOW);
      expect(s.memoryState).assertEqual(MemoryState.Review);
      expect(s.nextReviewMs).assertEqual(NOW + INTERVAL_30_MIN_MS);
    });

    it('masteredCorrectStaysMastered', 0, () => {
      const s: WordStat = freshStat(MemoryState.Mastered);
      new MemoryScheduler().applyAnswer(s, true, NOW);
      expect(s.memoryState).assertEqual(MemoryState.Mastered);
      expect(s.nextReviewMs).assertEqual(NOW + INTERVAL_14_DAY_MS);
    });
  });

  describe('MemoryScheduler.classify', () => {
    it('returnsReviewWhenDueRegardlessOfStoredState', 0, () => {
      const s: WordStat = freshStat(MemoryState.Familiar);
      s.nextReviewMs = NOW - 1;
      expect(new MemoryScheduler().classify(s, NOW)).assertEqual(MemoryState.Review);
    });
    it('returnsStoredStateWhenNotDue', 0, () => {
      const s: WordStat = freshStat(MemoryState.Familiar);
      s.nextReviewMs = NOW + 1;
      expect(new MemoryScheduler().classify(s, NOW)).assertEqual(MemoryState.Familiar);
    });
    it('returnsNewWhenStoredStateIsEmpty', 0, () => {
      const s: WordStat = new WordStat();
      expect(new MemoryScheduler().classify(s, NOW)).assertEqual(MemoryState.New);
    });
  });
}
