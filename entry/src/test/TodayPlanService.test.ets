import { describe, it, expect } from '@ohos/hypium';
import { WordEntry } from '../main/ets/models/WordEntry';
import { WordRepository } from '../main/ets/services/WordRepository';
import { LearningRecorder } from '../main/ets/services/LearningRecorder';
import { LearningSnapshot, WordStat, WrongAnswerStore, StringPreferencesLike } from '../main/ets/services/WrongAnswerStore';
import {
  AdventureRegion,
  MonsterPlan,
  MonsterSlot,
  WordSource,
  MONSTER_PLAN_SLOT_COUNT,
  WORD_PLAN_MULTIPLIER,
} from '../main/ets/models/AdventureRegion';
import { MonsterKind } from '../main/ets/data/MonsterCatalog';
import { MemoryState } from '../main/ets/services/MemoryScheduler';
import {
  TodayPlanService,
  TodayPlanView,
  TodayPlanRow,
  todayPlanSeed,
  localStartOfDay,
  describeMemoryState,
  describeWordSource,
} from '../main/ets/services/TodayPlanService';

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

function makeWord(id: string, word: string, meaningZh: string): WordEntry {
  const w: WordEntry = new WordEntry();
  w.id = id;
  w.word = word;
  w.meaningZh = meaningZh;
  w.category = 'fruit';
  w.difficulty = 1;
  return w;
}

function makeRegion(): AdventureRegion {
  const r: AdventureRegion = new AdventureRegion();
  r.id = 'fruit-forest';
  r.displayName = '水果森林';
  r.themeWordCategories = ['fruit'];
  const plan: MonsterPlan = new MonsterPlan();
  const slots: MonsterSlot[] = [];
  for (let i = 0; i < MONSTER_PLAN_SLOT_COUNT; i++) {
    const s: MonsterSlot = new MonsterSlot();
    s.kind = i === MONSTER_PLAN_SLOT_COUNT - 1 ? MonsterKind.Boss : MonsterKind.Normal;
    s.catalogIndex = i + 1;
    slots.push(s);
  }
  plan.slots = slots;
  r.monsterPlan = plan;
  return r;
}

function makeRepo(): WordRepository {
  const repo: WordRepository = new WordRepository();
  const names: string[] = [
    'apple', 'banana', 'orange', 'grape', 'pear', 'peach',
    'lemon', 'mango', 'melon', 'cherry', 'plum', 'kiwi',
  ];
  const meanings: string[] = [
    '苹果', '香蕉', '橙子', '葡萄', '梨', '桃子',
    '柠檬', '芒果', '甜瓜', '樱桃', '李子', '猕猴桃',
  ];
  const words: WordEntry[] = [];
  for (let i = 0; i < names.length; i++) {
    words.push(makeWord(`fruit-${names[i]}`, names[i], meanings[i]));
  }
  repo.setEntries(words);
  return repo;
}

function makeRecorderWith(stats: WordStat[]): LearningRecorder {
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

const NOW: number = 17_000_000_000_000;

export default function todayPlanServiceTest() {
  describe('todayPlanSeed', () => {
    it('isStableForSameRegionAndDay', 0, () => {
      const a: number = todayPlanSeed('fruit-forest', '2026-04-30');
      const b: number = todayPlanSeed('fruit-forest', '2026-04-30');
      expect(a).assertEqual(b);
    });

    it('differsAcrossDays', 0, () => {
      const a: number = todayPlanSeed('fruit-forest', '2026-04-30');
      const b: number = todayPlanSeed('fruit-forest', '2026-05-01');
      expect(a === b).assertFalse();
    });

    it('differsAcrossRegions', 0, () => {
      const a: number = todayPlanSeed('fruit-forest', '2026-04-30');
      const b: number = todayPlanSeed('school-castle', '2026-04-30');
      expect(a === b).assertFalse();
    });
  });

  describe('localStartOfDay', () => {
    it('isMonotonicAcrossSameDay', 0, () => {
      const noon: number = NOW;
      const evening: number = NOW + 6 * 60 * 60 * 1000;
      expect(localStartOfDay(noon)).assertEqual(localStartOfDay(evening));
    });

    it('movesForwardAcrossDayBoundary', 0, () => {
      const day1: number = NOW;
      const day2: number = NOW + 26 * 60 * 60 * 1000;
      expect(localStartOfDay(day2) > localStartOfDay(day1)).assertTrue();
    });
  });

  describe('describeMemoryState / describeWordSource', () => {
    it('mapsAllStatesToDistinctChineseLabels', 0, () => {
      const labels: Set<string> = new Set<string>();
      labels.add(describeMemoryState(MemoryState.New));
      labels.add(describeMemoryState(MemoryState.Learning));
      labels.add(describeMemoryState(MemoryState.Familiar));
      labels.add(describeMemoryState(MemoryState.Mastered));
      labels.add(describeMemoryState(MemoryState.Review));
      expect(labels.size).assertEqual(5);
    });

    it('mapsAllSourcesToDistinctChineseLabels', 0, () => {
      const labels: Set<string> = new Set<string>();
      labels.add(describeWordSource(WordSource.Review));
      labels.add(describeWordSource(WordSource.Learning));
      labels.add(describeWordSource(WordSource.New));
      expect(labels.size).assertEqual(3);
    });
  });

  describe('TodayPlanService.build', () => {
    it('returnsRowCountMatchingPlanLength', 0, () => {
      const repo: WordRepository = makeRepo();
      const region: AdventureRegion = makeRegion();
      const rec: LearningRecorder = makeRecorderWith([]);
      const view: TodayPlanView =
        new TodayPlanService().build(region, repo, rec, NOW);
      expect(view.regionId).assertEqual('fruit-forest');
      expect(view.regionDisplayName).assertEqual('水果森林');
      expect(view.total()).assertEqual(MONSTER_PLAN_SLOT_COUNT * WORD_PLAN_MULTIPLIER);
    });

    it('isDeterministicAcrossCalls', 0, () => {
      // V0.4.4 contract: re-rendering the page mid-day must show the
      // same words in the same buckets. Drives a fresh service
      // instance so we know it's not a stateful cache.
      const repo: WordRepository = makeRepo();
      const region: AdventureRegion = makeRegion();
      const rec: LearningRecorder = makeRecorderWith([]);
      const a: TodayPlanView = new TodayPlanService().build(region, repo, rec, NOW);
      const b: TodayPlanView = new TodayPlanService().build(region, repo, rec, NOW);
      const aIds: string[] = collectIds(a);
      const bIds: string[] = collectIds(b);
      expect(aIds.length).assertEqual(bIds.length);
      for (let i = 0; i < aIds.length; i++) {
        expect(aIds[i]).assertEqual(bIds[i]);
      }
    });

    it('groupsByWordSourceBucket', 0, () => {
      const repo: WordRepository = makeRepo();
      const region: AdventureRegion = makeRegion();
      const rec: LearningRecorder = makeRecorderWith([]);
      const view: TodayPlanView =
        new TodayPlanService().build(region, repo, rec, NOW);
      for (let i = 0; i < view.review.length; i++) {
        expect(view.review[i].source).assertEqual(WordSource.Review);
      }
      for (let i = 0; i < view.learning.length; i++) {
        expect(view.learning[i].source).assertEqual(WordSource.Learning);
      }
      for (let i = 0; i < view.freshNew.length; i++) {
        expect(view.freshNew[i].source).assertEqual(WordSource.New);
      }
    });

    it('marksDoneTodayWhenAnsweredCorrectlyToday', 0, () => {
      const repo: WordRepository = makeRepo();
      const region: AdventureRegion = makeRegion();
      // Stat: just answered apple correctly "today". The recorder
      // owns the timestamp — we can't pass NOW into recordAnswer, so
      // we hand-craft a stat aligned with the page's "today" window.
      const stat: WordStat = new WordStat();
      stat.wordId = 'fruit-apple';
      stat.seenCount = 1;
      stat.correctCount = 1;
      stat.consecutiveCorrect = 1;
      stat.lastAnsweredMs = NOW; // strictly inside today's window
      stat.memoryState = 'learning';
      stat.nextReviewMs = NOW + 60 * 60 * 1000;
      stat.lastCorrectMs = NOW;
      stat.mastery = 0.1;
      const rec: LearningRecorder = makeRecorderWith([stat]);
      const view: TodayPlanView =
        new TodayPlanService().build(region, repo, rec, NOW);
      const row: TodayPlanRow | undefined = findRow(view, 'fruit-apple');
      expect(row !== undefined).assertTrue();
      if (row !== undefined) {
        expect(row.doneToday).assertTrue();
      }
    });

    it('doesNotMarkDoneWhenLastAnswerWasYesterday', 0, () => {
      const repo: WordRepository = makeRepo();
      const region: AdventureRegion = makeRegion();
      const stat: WordStat = new WordStat();
      stat.wordId = 'fruit-apple';
      stat.seenCount = 1;
      stat.correctCount = 1;
      stat.consecutiveCorrect = 1;
      // Stamp 26h before NOW so it falls in the previous local day.
      stat.lastAnsweredMs = NOW - 26 * 60 * 60 * 1000;
      stat.lastCorrectMs = stat.lastAnsweredMs;
      stat.nextReviewMs = NOW + 60 * 60 * 1000;
      stat.memoryState = 'learning';
      stat.mastery = 0.1;
      const rec: LearningRecorder = makeRecorderWith([stat]);
      const view: TodayPlanView =
        new TodayPlanService().build(region, repo, rec, NOW);
      const row: TodayPlanRow | undefined = findRow(view, 'fruit-apple');
      expect(row !== undefined).assertTrue();
      if (row !== undefined) {
        expect(row.doneToday).assertFalse();
      }
    });

    it('doesNotMarkDoneWhenLastAnswerWasWrong', 0, () => {
      const repo: WordRepository = makeRepo();
      const region: AdventureRegion = makeRegion();
      const stat: WordStat = new WordStat();
      stat.wordId = 'fruit-apple';
      stat.seenCount = 1;
      stat.correctCount = 0;
      stat.wrongCount = 1;
      stat.consecutiveCorrect = 0; // last answer was wrong
      stat.consecutiveWrong = 1;
      stat.lastAnsweredMs = NOW;
      stat.nextReviewMs = NOW + 30 * 60 * 1000;
      stat.memoryState = 'review';
      stat.mastery = 0;
      const rec: LearningRecorder = makeRecorderWith([stat]);
      const view: TodayPlanView =
        new TodayPlanService().build(region, repo, rec, NOW);
      const row: TodayPlanRow | undefined = findRow(view, 'fruit-apple');
      expect(row !== undefined).assertTrue();
      if (row !== undefined) {
        expect(row.doneToday).assertFalse();
      }
    });

    it('doneCountTalliesAcrossBuckets', 0, () => {
      const repo: WordRepository = makeRepo();
      const region: AdventureRegion = makeRegion();
      const stats: WordStat[] = [];
      // Mark 'apple' and 'banana' as done today; both should
      // surface in the plan for our 12-word repo.
      const ids: string[] = ['fruit-apple', 'fruit-banana'];
      for (let i = 0; i < ids.length; i++) {
        const s: WordStat = new WordStat();
        s.wordId = ids[i];
        s.seenCount = 1;
        s.correctCount = 1;
        s.consecutiveCorrect = 1;
        s.lastAnsweredMs = NOW;
        s.lastCorrectMs = NOW;
        s.nextReviewMs = NOW + 60 * 60 * 1000;
        s.memoryState = 'learning';
        s.mastery = 0.1;
        stats.push(s);
      }
      const rec: LearningRecorder = makeRecorderWith(stats);
      const view: TodayPlanView =
        new TodayPlanService().build(region, repo, rec, NOW);
      // The plan deterministically pulls all 12 words (target=10
      // but pool of 12 means all candidates are covered when the
      // recorder has only 2 stats — both stat'd ids should be
      // included; doneCount should match how many stat'd ids ended
      // up in the wordPlan).
      let expectedDone: number = 0;
      const allRows: TodayPlanRow[] = collectRows(view);
      for (let i = 0; i < allRows.length; i++) {
        if (ids.indexOf(allRows[i].wordId) >= 0) {
          expectedDone += 1;
        }
      }
      expect(view.doneCount()).assertEqual(expectedDone);
    });

    it('memoryStateClassifiesNewForUnseenWords', 0, () => {
      const repo: WordRepository = makeRepo();
      const region: AdventureRegion = makeRegion();
      const rec: LearningRecorder = makeRecorderWith([]);
      const view: TodayPlanView =
        new TodayPlanService().build(region, repo, rec, NOW);
      const allRows: TodayPlanRow[] = collectRows(view);
      expect(allRows.length > 0).assertTrue();
      for (let i = 0; i < allRows.length; i++) {
        expect(allRows[i].memoryState).assertEqual(MemoryState.New);
      }
    });
  });
}

function collectIds(view: TodayPlanView): string[] {
  const out: string[] = [];
  for (let i = 0; i < view.review.length; i++) {
    out.push(view.review[i].wordId);
  }
  for (let i = 0; i < view.learning.length; i++) {
    out.push(view.learning[i].wordId);
  }
  for (let i = 0; i < view.freshNew.length; i++) {
    out.push(view.freshNew[i].wordId);
  }
  return out;
}

function collectRows(view: TodayPlanView): TodayPlanRow[] {
  const out: TodayPlanRow[] = [];
  for (let i = 0; i < view.review.length; i++) {
    out.push(view.review[i]);
  }
  for (let i = 0; i < view.learning.length; i++) {
    out.push(view.learning[i]);
  }
  for (let i = 0; i < view.freshNew.length; i++) {
    out.push(view.freshNew[i]);
  }
  return out;
}

function findRow(view: TodayPlanView, wordId: string): TodayPlanRow | undefined {
  const all: TodayPlanRow[] = collectRows(view);
  for (let i = 0; i < all.length; i++) {
    if (all[i].wordId === wordId) {
      return all[i];
    }
  }
  return undefined;
}
