import { describe, it, expect } from '@ohos/hypium';
import { mulberry32, RandomFn } from '../main/ets/utils/shuffle';
import { WordEntry } from '../main/ets/models/WordEntry';
import { WordRepository } from '../main/ets/services/WordRepository';
import { LearningRecorder } from '../main/ets/services/LearningRecorder';
import { TodayAdventureBuilder, localDayKey } from '../main/ets/services/TodayAdventureBuilder';
import {
  AdventureRegion,
  MonsterPlan,
  MonsterSlot,
  TodaySessionPlan,
  WordSlot,
  WordSource,
  MONSTER_PLAN_SLOT_COUNT,
  WORD_PLAN_MULTIPLIER,
} from '../main/ets/models/AdventureRegion';
import { MonsterKind } from '../main/ets/data/MonsterCatalog';

function makeWord(id: string, word: string, category: string): WordEntry {
  const w: WordEntry = new WordEntry();
  w.id = id;
  w.word = word;
  w.meaningZh = '_';
  w.category = category;
  w.difficulty = 1;
  return w;
}

function makeRegion(): AdventureRegion {
  const r: AdventureRegion = new AdventureRegion();
  r.id = 'fruit-forest';
  r.themeWordCategories = ['fruit'];
  const plan: MonsterPlan = new MonsterPlan();
  const slots: MonsterSlot[] = [];
  for (let i = 0; i < MONSTER_PLAN_SLOT_COUNT; i++) {
    const s: MonsterSlot = new MonsterSlot();
    s.kind = MonsterKind.Normal;
    s.catalogIndex = i + 1;
    slots.push(s);
  }
  plan.slots = slots;
  r.monsterPlan = plan;
  return r;
}

function makeRegionWithBoss(id: string, candidates: number[]): AdventureRegion {
  const r: AdventureRegion = new AdventureRegion();
  r.id = id;
  r.themeWordCategories = ['fruit'];
  const plan: MonsterPlan = new MonsterPlan();
  const slots: MonsterSlot[] = [];
  for (let i: number = 0; i < MONSTER_PLAN_SLOT_COUNT; i++) {
    const s: MonsterSlot = new MonsterSlot();
    // Last slot is Boss to mirror real region templates; earlier
    // slots stay Normal so the override leak check is trivial.
    s.kind = i === MONSTER_PLAN_SLOT_COUNT - 1 ? MonsterKind.Boss : MonsterKind.Normal;
    s.catalogIndex = i + 1;
    slots.push(s);
  }
  plan.slots = slots;
  r.monsterPlan = plan;
  r.bossCandidates = candidates;
  return r;
}

function makeRepo(): WordRepository {
  const repo: WordRepository = new WordRepository();
  const words: WordEntry[] = [];
  const names: string[] = [
    'apple', 'banana', 'orange', 'grape', 'pear', 'peach',
    'lemon', 'mango', 'melon', 'cherry', 'plum', 'kiwi',
    'lime', 'olive', 'date',
  ];
  for (let i = 0; i < names.length; i++) {
    words.push(makeWord(`fruit-${names[i]}`, names[i], 'fruit'));
  }
  repo.setEntries(words);
  return repo;
}

const NOW: number = 17_000_000_000_000;

export default function todayAdventureBuilderTest() {
  describe('localDayKey', () => {
    it('returnsStableYmdString', 0, () => {
      const k1: string = localDayKey(NOW);
      const k2: string = localDayKey(NOW + 60_000);
      expect(k1).assertEqual(k2);
      expect(k1.length).assertEqual('YYYY-MM-DD'.length);
    });
  });

  describe('TodayAdventureBuilder.build', () => {
    it('producesPlanWithBudgetedReviewLearningNew', 0, () => {
      const repo: WordRepository = makeRepo();
      const region: AdventureRegion = makeRegion();
      const rec: LearningRecorder = new LearningRecorder();
      // Seed a recorder with answers spanning multiple days so the
      // memory states settle into Review (wrong recently), Learning
      // (one correct), and untouched (which become "new").
      // We use private path via recordAnswer; timestamps come from
      // Date.now (recorder reads its own clock).
      rec.recordAnswer('fruit-apple', false);
      rec.recordAnswer('fruit-banana', true);
      rec.recordAnswer('fruit-orange', true);

      const rng: RandomFn = mulberry32(7);
      const builder: TodayAdventureBuilder = new TodayAdventureBuilder(rng);
      const plan: TodaySessionPlan = builder.build(region, repo, rec, NOW, true);
      expect(plan.regionId).assertEqual('fruit-forest');
      expect(plan.monsterSlots.length).assertEqual(MONSTER_PLAN_SLOT_COUNT);
      expect(plan.wordPlan.length).assertEqual(MONSTER_PLAN_SLOT_COUNT * WORD_PLAN_MULTIPLIER);
      expect(plan.bossWordIds.length).assertEqual(2);
      expect(plan.isFirstToday).assertTrue();
    });

    it('isDeterministicForFixedRng', 0, () => {
      const repo: WordRepository = makeRepo();
      const region: AdventureRegion = makeRegion();
      const rec: LearningRecorder = new LearningRecorder();
      rec.recordAnswer('fruit-apple', false);
      const a: TodaySessionPlan = new TodayAdventureBuilder(mulberry32(7)).build(region, repo, rec, NOW, true);
      const b: TodaySessionPlan = new TodayAdventureBuilder(mulberry32(7)).build(region, repo, rec, NOW, true);
      expect(a.wordPlan.length).assertEqual(b.wordPlan.length);
      for (let i = 0; i < a.wordPlan.length; i++) {
        expect(a.wordPlan[i].wordId).assertEqual(b.wordPlan[i].wordId);
        expect(a.wordPlan[i].source).assertEqual(b.wordPlan[i].source);
      }
    });

    it('keepsThemeCategoryOnlyWhenAvailable', 0, () => {
      const repo: WordRepository = makeRepo();
      // Add a non-fruit word the builder must not pick.
      const all: WordEntry[] = repo.all();
      all.push(makeWord('home-tv', 'tv', 'home'));
      repo.setEntries(all);
      const region: AdventureRegion = makeRegion();
      const rec: LearningRecorder = new LearningRecorder();
      const plan: TodaySessionPlan = new TodayAdventureBuilder(mulberry32(11))
        .build(region, repo, rec, NOW, false);
      for (let i = 0; i < plan.wordPlan.length; i++) {
        expect(plan.wordPlan[i].wordId.startsWith('fruit-')).assertTrue();
      }
    });

    it('marksReviewWordsAsReviewSourceInPlan', 0, () => {
      const repo: WordRepository = makeRepo();
      const region: AdventureRegion = makeRegion();
      const rec: LearningRecorder = new LearningRecorder();
      // Wrong → Review state, scheduled 30min out from Date.now().
      rec.recordAnswer('fruit-apple', false);
      rec.recordAnswer('fruit-banana', false);
      rec.recordAnswer('fruit-orange', false);
      // Builder uses NOW (which is far in the future), so the
      // scheduled nextReviewMs (Date.now()+30min) is already due.
      const plan: TodaySessionPlan = new TodayAdventureBuilder(mulberry32(2))
        .build(region, repo, rec, NOW, false);
      let reviewSourceCount: number = 0;
      for (let i = 0; i < plan.wordPlan.length; i++) {
        if (plan.wordPlan[i].source === WordSource.Review) {
          reviewSourceCount += 1;
        }
      }
      expect(reviewSourceCount > 0).assertTrue();
    });

    it('returnsAtLeastTargetWordsEvenWhenPoolIsSmall', 0, () => {
      const repo: WordRepository = new WordRepository();
      // Tiny repo: 4 fruits — fewer than the 10-slot target.
      repo.setEntries([
        makeWord('fruit-apple', 'apple', 'fruit'),
        makeWord('fruit-pear', 'pear', 'fruit'),
        makeWord('fruit-mango', 'mango', 'fruit'),
        makeWord('fruit-kiwi', 'kiwi', 'fruit'),
      ]);
      const region: AdventureRegion = makeRegion();
      const rec: LearningRecorder = new LearningRecorder();
      const plan: TodaySessionPlan = new TodayAdventureBuilder(mulberry32(3))
        .build(region, repo, rec, NOW, false);
      // The builder should not exceed the pool but must include
      // every available word at least once.
      const ids: Set<string> = new Set<string>();
      for (let i = 0; i < plan.wordPlan.length; i++) {
        ids.add(plan.wordPlan[i].wordId);
      }
      expect(ids.size).assertEqual(4);
    });
  });

  describe('TodayAdventureBuilder.bossRotation (V0.3.8)', () => {
    const ONE_DAY: number = 24 * 60 * 60 * 1000;

    it('sameRegionSameDayPicksSameBoss', 0, () => {
      const region: AdventureRegion = makeRegionWithBoss('test-region', [14, 15, 16]);
      const repo: WordRepository = makeRepo();
      const rec: LearningRecorder = new LearningRecorder();
      const b: TodayAdventureBuilder = new TodayAdventureBuilder(mulberry32(7));
      const p1: TodaySessionPlan = b.build(region, repo, rec, NOW, false);
      const p2: TodaySessionPlan = b.build(region, repo, rec, NOW + 60_000, false);
      const last: number = p1.monsterSlots.length - 1;
      expect(p1.monsterSlots[last].catalogIndex).assertEqual(p2.monsterSlots[last].catalogIndex);
    });

    it('regionWithoutBossCandidatesPreservesTemplateSlot', 0, () => {
      const region: AdventureRegion = makeRegionWithBoss('no-boss-region', []);
      const repo: WordRepository = makeRepo();
      const rec: LearningRecorder = new LearningRecorder();
      const b: TodayAdventureBuilder = new TodayAdventureBuilder(mulberry32(7));
      const p: TodaySessionPlan = b.build(region, repo, rec, NOW, false);
      const last: number = p.monsterSlots.length - 1;
      expect(p.monsterSlots[last].catalogIndex).assertEqual(MONSTER_PLAN_SLOT_COUNT);
      expect(p.monsterSlots[last].kind).assertEqual(MonsterKind.Boss);
    });

    it('overrideOnlyTouchesLastSlot', 0, () => {
      const region: AdventureRegion = makeRegionWithBoss('forest-test', [14, 15, 16]);
      const repo: WordRepository = makeRepo();
      const rec: LearningRecorder = new LearningRecorder();
      const b: TodayAdventureBuilder = new TodayAdventureBuilder(mulberry32(7));
      const p: TodaySessionPlan = b.build(region, repo, rec, NOW, false);
      for (let i: number = 0; i < p.monsterSlots.length - 1; i++) {
        expect(p.monsterSlots[i].catalogIndex).assertEqual(region.monsterPlan.slots[i].catalogIndex);
        expect(p.monsterSlots[i].kind).assertEqual(region.monsterPlan.slots[i].kind);
      }
    });

    it('chosenBossIndexIsAlwaysFromCandidates', 0, () => {
      const region: AdventureRegion = makeRegionWithBoss('forest-test', [14, 15, 16]);
      const repo: WordRepository = makeRepo();
      const rec: LearningRecorder = new LearningRecorder();
      const b: TodayAdventureBuilder = new TodayAdventureBuilder(mulberry32(7));
      const allHit: Set<number> = new Set<number>();
      let now: number = NOW;
      for (let d: number = 0; d < 14; d++) {
        const p: TodaySessionPlan = b.build(region, repo, rec, now, false);
        const last: number = p.monsterSlots.length - 1;
        const idx: number = p.monsterSlots[last].catalogIndex;
        expect(idx === 14 || idx === 15 || idx === 16).assertTrue();
        allHit.add(idx);
        now += ONE_DAY;
      }
      // 14 days against 3 candidates with djb2 hash — extremely unlikely
      // to land on a single candidate. Assert >= 2 distinct hits.
      expect(allHit.size >= 2).assertTrue();
    });

    it('differentRegionsCanPickDifferentBossesOnSameDay', 0, () => {
      const forest: AdventureRegion = makeRegionWithBoss('fruit-forest', [14, 15, 16]);
      const castle: AdventureRegion = makeRegionWithBoss('school-castle', [17, 18]);
      const repo: WordRepository = makeRepo();
      const rec: LearningRecorder = new LearningRecorder();
      const b: TodayAdventureBuilder = new TodayAdventureBuilder(mulberry32(7));
      const pForest: TodaySessionPlan = b.build(forest, repo, rec, NOW, false);
      const pCastle: TodaySessionPlan = b.build(castle, repo, rec, NOW, false);
      const last: number = pForest.monsterSlots.length - 1;
      // Disjoint candidate ranges guarantee non-equal indices when
      // both override paths fire.
      expect(pForest.monsterSlots[last].catalogIndex).assertLarger(13);
      expect(pForest.monsterSlots[last].catalogIndex).assertLess(17);
      expect(pCastle.monsterSlots[last].catalogIndex).assertLarger(16);
      expect(pCastle.monsterSlots[last].catalogIndex).assertLess(19);
    });
  });
}
