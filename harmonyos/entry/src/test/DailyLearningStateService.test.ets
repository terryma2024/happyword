import { describe, it, expect } from '@ohos/hypium';
import { WordEntry } from '../main/ets/models/WordEntry';
import { WordStat } from '../main/ets/services/WrongAnswerStore';
import { MemoryState } from '../main/ets/services/MemoryScheduler';
import {
  DailyLearningState,
  DailyLearningStateService,
  DailyReviewSnapshot,
  HomeDailyStatus,
  ReviewReason,
  ReviewQueueBuilder,
  compactDayKey,
  decideHomeDailyStatus,
  reviewMonsterCount,
} from '../main/ets/services/DailyLearningStateService';

const START: number = Date.parse('2026-05-26T00:00:00');
const NOON: number = START + 12 * 60 * 60 * 1000;
const DAY: number = 24 * 60 * 60 * 1000;

function word(id: string): WordEntry {
  const w: WordEntry = new WordEntry();
  w.id = id;
  w.word = id;
  w.meaningZh = id;
  w.category = 'fruit';
  return w;
}

function stat(
  id: string,
  lastAnsweredMs: number,
  memoryState: MemoryState,
  nextReviewMs: number,
  correct: number,
  wrong: number,
  seen: number,
  mastery: number,
  lastOutcome: string,
): WordStat {
  const s: WordStat = new WordStat();
  s.wordId = id;
  s.lastAnsweredMs = lastAnsweredMs;
  s.memoryState = memoryState;
  s.nextReviewMs = nextReviewMs;
  s.correctCount = correct;
  s.wrongCount = wrong;
  s.seenCount = seen;
  s.mastery = mastery;
  if (lastOutcome === 'wrong') {
    s.consecutiveWrong = 1;
    s.consecutiveCorrect = 0;
  } else if (lastOutcome === 'correct') {
    s.consecutiveCorrect = 1;
    s.consecutiveWrong = 0;
  }
  s.lastOutcome = lastOutcome;
  return s;
}

export default function dailyLearningStateServiceTest() {
  describe('compactDayKey', () => {
    it('formatsLocalDayAsYYYYMMDD', 0, () => {
      expect(compactDayKey(NOON)).assertEqual('20260526');
    });
  });

  describe('ReviewQueueBuilder', () => {
    it('buildsStableReviewSnapshotFromPreDayStatsOnly', 0, () => {
      const words: WordEntry[] = [
        word('due'),
        word('recent-wrong'),
        word('weak'),
        word('same-day-wrong'),
        word('fresh'),
      ];
      const stats: WordStat[] = [
        stat('due', START - 5 * DAY, MemoryState.Familiar, START - DAY, 5, 0, 5, 0.8, 'correct'),
        stat('recent-wrong', START - 2 * DAY, MemoryState.Review, START + DAY, 1, 1, 2, 0.4, 'wrong'),
        stat('weak', START - 3 * DAY, MemoryState.Learning, START + DAY, 2, 3, 5, 0.3, 'correct'),
        stat('same-day-wrong', START + 60_000, MemoryState.Review, START + 30 * 60_000, 0, 1, 1, 0, 'wrong'),
      ];

      const snapshot: DailyReviewSnapshot = new ReviewQueueBuilder()
        .buildSnapshot(words, stats, NOON, ['due']);

      expect(snapshot.dayKey).assertEqual('20260526');
      expect(snapshot.wordIds.length).assertEqual(3);
      expect(snapshot.wordIds[0]).assertEqual('due');
      expect(snapshot.wordIds.indexOf('same-day-wrong') < 0).assertTrue();
      expect(snapshot.items[0].primaryReason).assertEqual(ReviewReason.DueReview);
      expect(snapshot.items[1].primaryReason).assertEqual(ReviewReason.RecentWrong);
      expect(snapshot.items[2].primaryReason).assertEqual(ReviewReason.WeakWord);
    });

    it('capsReviewSnapshotAtFiftyWords', 0, () => {
      const words: WordEntry[] = [];
      const stats: WordStat[] = [];
      for (let i = 0; i < 80; i++) {
        const id: string = `w-${i < 10 ? '0' : ''}${i}`;
        words.push(word(id));
        stats.push(stat(id, START - DAY, MemoryState.Review, START - 1, 0, 1, 1, 0, 'wrong'));
      }

      const snapshot: DailyReviewSnapshot = new ReviewQueueBuilder()
        .buildSnapshot(words, stats, NOON, []);

      expect(snapshot.wordIds.length).assertEqual(50);
    });
  });

  describe('Home daily status', () => {
    it('usesSpecifiedABLabelMatrix', 0, () => {
      const state: DailyLearningState = new DailyLearningState();
      state.dayKey = '20260526';
      state.reviewSnapshot.wordIds = ['a', 'b'];

      let status: HomeDailyStatus = decideHomeDailyStatus(state);
      expect(status.label).assertEqual('请选择一个场景加战斗');
      expect(status.remainingReviewCount).assertEqual(2);
      expect(status.todayAdventureCompleted).assertFalse();
      expect(status.dailyCheckInCompleted).assertFalse();

      state.reviewSnapshot.reviewedWordIds = ['a', 'b'];
      status = decideHomeDailyStatus(state);
      expect(status.label).assertEqual('请选择一个场景加战斗');
      expect(status.dailyCheckInCompleted).assertTrue();

      state.packBattleWon = true;
      state.reviewSnapshot.reviewedWordIds = ['a'];
      status = decideHomeDailyStatus(state);
      expect(status.label).assertEqual('请点击复习加战斗(1)');
      expect(status.todayAdventureCompleted).assertFalse();

      state.reviewSnapshot.reviewedWordIds = ['a', 'b'];
      status = decideHomeDailyStatus(state);
      expect(status.label).assertEqual('已完成');
      expect(status.todayAdventureCompleted).assertTrue();
    });
  });

  describe('DailyLearningStateService helpers', () => {
    it('marksReviewedWordsAndPackWins', 0, () => {
      const state: DailyLearningState = new DailyLearningState();
      state.dayKey = '20260526';
      state.reviewSnapshot.wordIds = ['a', 'b'];
      const service: DailyLearningStateService = new DailyLearningStateService();

      service.markPackBattleWonInMemory(state);
      service.markReviewedWordsInMemory(state, ['a', 'a', 'missing']);

      expect(state.packBattleWon).assertTrue();
      expect(state.reviewSnapshot.reviewedWordIds.length).assertEqual(1);
      expect(state.reviewSnapshot.reviewedWordIds[0]).assertEqual('a');
      expect(state.reviewAllDone).assertFalse();

      service.markReviewedWordsInMemory(state, ['b']);
      expect(state.reviewAllDone).assertTrue();
    });

    it('computesReviewMonsterCountFromWordCountHpAndConfiguredCap', 0, () => {
      expect(reviewMonsterCount(20, 5, 10, 5)).assertEqual(3);
      expect(reviewMonsterCount(1, 5, 10, 5)).assertEqual(1);
      expect(reviewMonsterCount(50, 1, 10, 5)).assertEqual(10);
      expect(reviewMonsterCount(20, 0, 10, 5)).assertEqual(3);
    });
  });
}
