import { describe, it, expect } from '@ohos/hypium';
import { WordEntry } from '../main/ets/models/WordEntry';
import { WordRepository } from '../main/ets/services/WordRepository';
import { LearningRecorder } from '../main/ets/services/LearningRecorder';
import {
  LearningSnapshot,
  StringPreferencesLike,
  WordStat,
  WrongAnswerStore,
} from '../main/ets/services/WrongAnswerStore';
import {
  LearningReportBuilder,
  LearningReport,
  CategoryReport,
  describeCategory,
} from '../main/ets/services/LearningReportBuilder';

class FakePreferences implements StringPreferencesLike {
  private readonly map: Map<string, string> = new Map<string, string>();
  getString(key: string): Promise<string> {
    return Promise.resolve(this.map.has(key) ? (this.map.get(key) as string) : '');
  }
  putString(key: string, value: string): Promise<void> {
    this.map.set(key, value);
    return Promise.resolve();
  }
  flush(): Promise<void> {
    return Promise.resolve();
  }
}

function makeWord(id: string, category: string): WordEntry {
  const w: WordEntry = new WordEntry();
  w.id = id;
  w.word = id;
  w.meaningZh = '_';
  w.category = category;
  w.difficulty = 1;
  return w;
}

function makeRepo(): WordRepository {
  const repo: WordRepository = new WordRepository();
  const words: WordEntry[] = [
    // 5 fruits
    makeWord('fruit-apple', 'fruit'),
    makeWord('fruit-banana', 'fruit'),
    makeWord('fruit-orange', 'fruit'),
    makeWord('fruit-grape', 'fruit'),
    makeWord('fruit-pear', 'fruit'),
    // 4 places
    makeWord('place-school', 'place'),
    makeWord('place-park', 'place'),
    makeWord('place-zoo', 'place'),
    makeWord('place-bank', 'place'),
    // 3 home
    makeWord('home-tv', 'home'),
    makeWord('home-bed', 'home'),
    makeWord('home-book', 'home'),
  ];
  repo.setEntries(words);
  return repo;
}

function makeRecorder(stats: WordStat[]): LearningRecorder {
  const snap: LearningSnapshot = new LearningSnapshot();
  for (let i = 0; i < stats.length; i++) {
    snap.stats.push(stats[i]);
  }
  const store: WrongAnswerStore = new WrongAnswerStore();
  store.injectPreferences(new FakePreferences());
  const rec: LearningRecorder = new LearningRecorder(store);
  rec.attachStore(store, snap);
  return rec;
}

function makeStat(
  wordId: string,
  seenCount: number,
  correctCount: number,
  consecutiveCorrect: number,
  lastAnsweredMs: number,
  memoryState: string
): WordStat {
  const s: WordStat = new WordStat();
  s.wordId = wordId;
  s.seenCount = seenCount;
  s.correctCount = correctCount;
  s.wrongCount = seenCount - correctCount;
  s.consecutiveCorrect = consecutiveCorrect;
  s.consecutiveWrong = consecutiveCorrect > 0 ? 0 : (seenCount - correctCount);
  s.lastAnsweredMs = lastAnsweredMs;
  s.lastCorrectMs = correctCount > 0 ? lastAnsweredMs : -1;
  s.nextReviewMs = lastAnsweredMs + 60 * 60 * 1000;
  s.memoryState = memoryState;
  s.mastery = correctCount / Math.max(1, seenCount);
  return s;
}

const NOW: number = 17_000_000_000_000;
const YESTERDAY: number = NOW - 26 * 60 * 60 * 1000;

export default function learningReportBuilderTest() {
  describe('describeCategory', () => {
    it('mapsKnownCategoriesToChineseLabels', 0, () => {
      expect(describeCategory('fruit')).assertEqual('水果');
      expect(describeCategory('place')).assertEqual('地点');
      expect(describeCategory('home')).assertEqual('家庭');
    });

    it('mapsV046CategoriesToChineseLabels', 0, () => {
      expect(describeCategory('animal')).assertEqual('动物');
      expect(describeCategory('ocean')).assertEqual('海洋');
    });

    it('fallsBackToRawCategoryForUnknown', 0, () => {
      expect(describeCategory('mystery')).assertEqual('mystery');
    });
  });

  describe('LearningReportBuilder.build', () => {
    it('returnsZeroStateForEmptyRecorder', 0, () => {
      const repo: WordRepository = makeRepo();
      const rec: LearningRecorder = makeRecorder([]);
      const report: LearningReport =
        new LearningReportBuilder().build(repo, rec, NOW);
      expect(report.totalWords).assertEqual(12);
      expect(report.totalSeen).assertEqual(0);
      expect(report.totalCorrect).assertEqual(0);
      expect(report.accuracyPct).assertEqual(0);
      expect(report.newCount).assertEqual(12);
      expect(report.learningCount).assertEqual(0);
      expect(report.familiarCount).assertEqual(0);
      expect(report.masteredCount).assertEqual(0);
      expect(report.reviewDueCount).assertEqual(0);
      expect(report.reviewDoneTodayCount).assertEqual(0);
      expect(report.reviewCompletionPct).assertEqual(0);
      expect(report.weakCategories.length).assertEqual(0);
      expect(report.categories.length).assertEqual(3);
    });

    it('aggregatesAccuracyAcrossWordsAndCategories', 0, () => {
      const repo: WordRepository = makeRepo();
      const stats: WordStat[] = [
        makeStat('fruit-apple', 4, 4, 4, NOW, 'familiar'),
        makeStat('fruit-banana', 4, 2, 0, NOW, 'review'),
        makeStat('place-school', 4, 1, 0, NOW, 'review'),
      ];
      const rec: LearningRecorder = makeRecorder(stats);
      const report: LearningReport =
        new LearningReportBuilder().build(repo, rec, NOW);
      expect(report.totalSeen).assertEqual(12);
      expect(report.totalCorrect).assertEqual(7);
      // 7 / 12 = 58.33 -> 58
      expect(report.accuracyPct).assertEqual(58);
      // fruit: 4+2 / 4+4 = 6 / 8 = 75
      const fruitCat: CategoryReport = findCat(report, 'fruit');
      expect(fruitCat.accuracyPct).assertEqual(75);
      // place: 1 / 4 = 25
      const placeCat: CategoryReport = findCat(report, 'place');
      expect(placeCat.accuracyPct).assertEqual(25);
      // home: 0 / 0 = 0
      const homeCat: CategoryReport = findCat(report, 'home');
      expect(homeCat.totalSeen).assertEqual(0);
      expect(homeCat.accuracyPct).assertEqual(0);
    });

    it('orderWeakCategoriesByLowestAccuracyFirst', 0, () => {
      const repo: WordRepository = makeRepo();
      const stats: WordStat[] = [
        makeStat('fruit-apple', 4, 3, 3, NOW, 'familiar'),    // 75%
        makeStat('place-school', 5, 1, 0, NOW, 'review'),     // 20%
        makeStat('home-tv', 2, 1, 0, NOW, 'review'),          // 50%
      ];
      const rec: LearningRecorder = makeRecorder(stats);
      const report: LearningReport =
        new LearningReportBuilder().build(repo, rec, NOW);
      expect(report.weakCategories.length).assertEqual(3);
      expect(report.weakCategories[0].category).assertEqual('place');
      expect(report.weakCategories[1].category).assertEqual('home');
      expect(report.weakCategories[2].category).assertEqual('fruit');
    });

    it('skipsCategoriesWithNoSeenWordsFromWeakList', 0, () => {
      const repo: WordRepository = makeRepo();
      const stats: WordStat[] = [
        makeStat('fruit-apple', 2, 2, 2, NOW, 'familiar'),
      ];
      const rec: LearningRecorder = makeRecorder(stats);
      const report: LearningReport =
        new LearningReportBuilder().build(repo, rec, NOW);
      // place + home have zero seen — only fruit qualifies for weak list
      expect(report.weakCategories.length).assertEqual(1);
      expect(report.weakCategories[0].category).assertEqual('fruit');
    });

    it('countsMasteredAndFamiliarViaScheduler', 0, () => {
      const repo: WordRepository = makeRepo();
      const stats: WordStat[] = [
        makeStat('fruit-apple', 6, 6, 6, NOW, 'mastered'),
        makeStat('fruit-banana', 3, 3, 3, NOW, 'familiar'),
        makeStat('fruit-orange', 1, 1, 1, NOW, 'learning'),
      ];
      const rec: LearningRecorder = makeRecorder(stats);
      const report: LearningReport =
        new LearningReportBuilder().build(repo, rec, NOW);
      expect(report.masteredCount).assertEqual(1);
      expect(report.familiarCount).assertEqual(1);
      expect(report.learningCount).assertEqual(1);
      // 12 - 3 = 9 untouched words still count as new
      expect(report.newCount).assertEqual(9);
    });

    it('reviewCompletionTracksTodaysCorrectAnswers', 0, () => {
      const repo: WordRepository = makeRepo();
      // 3 words seen yesterday; only 1 already answered correctly today.
      const yesterdayStats: WordStat[] = [
        makeStat('fruit-apple', 2, 2, 0, YESTERDAY, 'learning'),
        makeStat('fruit-banana', 2, 1, 0, YESTERDAY, 'review'),
        makeStat('place-school', 2, 1, 0, YESTERDAY, 'review'),
      ];
      // Today, the kid answers fruit-apple correctly again.
      const apple: WordStat = makeStat('fruit-apple', 3, 3, 1, NOW, 'learning');
      const stats: WordStat[] = [apple, yesterdayStats[1], yesterdayStats[2]];
      const rec: LearningRecorder = makeRecorder(stats);
      const report: LearningReport =
        new LearningReportBuilder().build(repo, rec, NOW);
      expect(report.reviewDoneTodayCount).assertEqual(1);
      expect(report.reviewDueCount > 0).assertTrue();
      // completion: 1 / max(due, 1)
      expect(report.reviewCompletionPct > 0).assertTrue();
      expect(report.reviewCompletionPct <= 100).assertTrue();
    });

    it('reviewCompletionStays0WhenNothingReviewedToday', 0, () => {
      const repo: WordRepository = makeRepo();
      const stats: WordStat[] = [
        makeStat('fruit-apple', 2, 1, 0, YESTERDAY, 'review'),
      ];
      const rec: LearningRecorder = makeRecorder(stats);
      const report: LearningReport =
        new LearningReportBuilder().build(repo, rec, NOW);
      expect(report.reviewDoneTodayCount).assertEqual(0);
      expect(report.reviewCompletionPct).assertEqual(0);
    });

    it('accuracyRoundsToNearestInteger', 0, () => {
      const repo: WordRepository = makeRepo();
      const stats: WordStat[] = [
        makeStat('fruit-apple', 3, 2, 2, NOW, 'learning'), // 2/3 = 66.67
      ];
      const rec: LearningRecorder = makeRecorder(stats);
      const report: LearningReport =
        new LearningReportBuilder().build(repo, rec, NOW);
      expect(report.accuracyPct).assertEqual(67);
    });

    it('totalsExcludeUnseenWordsFromAccuracy', 0, () => {
      const repo: WordRepository = makeRepo();
      const stats: WordStat[] = [
        makeStat('fruit-apple', 5, 5, 5, NOW, 'familiar'),
      ];
      const rec: LearningRecorder = makeRecorder(stats);
      const report: LearningReport =
        new LearningReportBuilder().build(repo, rec, NOW);
      expect(report.totalSeen).assertEqual(5);
      expect(report.totalCorrect).assertEqual(5);
      expect(report.accuracyPct).assertEqual(100);
      expect(report.newCount).assertEqual(11);
    });
  });
}

function findCat(report: LearningReport, category: string): CategoryReport {
  for (let i = 0; i < report.categories.length; i++) {
    if (report.categories[i].category === category) {
      return report.categories[i];
    }
  }
  return new CategoryReport();
}
