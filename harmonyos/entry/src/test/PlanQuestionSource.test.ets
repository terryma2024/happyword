import { describe, it, expect } from '@ohos/hypium';
import { mulberry32 } from '../main/ets/utils/shuffle';
import { WordEntry } from '../main/ets/models/WordEntry';
import { Question, QuestionKind } from '../main/ets/models/Question';
import { WordRepository } from '../main/ets/services/WordRepository';
import { QuestionGenerator } from '../main/ets/services/QuestionGenerator';
import { FillLetterGenerator } from '../main/ets/services/FillLetterGenerator';
import { SpellGenerator } from '../main/ets/services/SpellGenerator';
import { PlanQuestionSource } from '../main/ets/services/PlanQuestionSource';
import {
  MonsterPlan,
  MonsterSlot,
  TodaySessionPlan,
  WordSlot,
  WordSource,
} from '../main/ets/models/AdventureRegion';
import { MonsterKind } from '../main/ets/data/MonsterCatalog';

function makeWord(id: string, word: string): WordEntry {
  const w: WordEntry = new WordEntry();
  w.id = id;
  w.word = word;
  w.meaningZh = '_';
  w.category = 'fruit';
  w.difficulty = 1;
  return w;
}

function makeRepo(): WordRepository {
  const repo: WordRepository = new WordRepository();
  repo.setEntries([
    makeWord('fruit-apple', 'apple'),
    makeWord('fruit-banana', 'banana'),
    makeWord('fruit-orange', 'orange'),
    makeWord('fruit-grape', 'grape'),
    makeWord('fruit-pear', 'pear'),
    makeWord('fruit-mango', 'mango'),
    makeWord('place-zoo', 'zoo'),
    makeWord('home-tv', 'TV'),
    makeWord('w-extraordinary', 'extraordinary'),
    makeWord('w-fish', 'fish'),
  ]);
  return repo;
}

function planWith(monsterKinds: MonsterKind[], wordIds: string[]): TodaySessionPlan {
  const plan: TodaySessionPlan = new TodaySessionPlan();
  plan.regionId = 'fruit-forest';
  for (let i = 0; i < monsterKinds.length; i++) {
    const s: MonsterSlot = new MonsterSlot();
    s.kind = monsterKinds[i];
    s.catalogIndex = i + 1;
    plan.monsterSlots.push(s);
  }
  for (let i = 0; i < wordIds.length; i++) {
    const ws: WordSlot = new WordSlot();
    ws.wordId = wordIds[i];
    ws.source = WordSource.Learning;
    plan.wordPlan.push(ws);
  }
  return plan;
}

function buildSrc(
  plan: TodaySessionPlan,
  repo: WordRepository,
  seedQ: number,
  seedFill: number,
  seedSpell: number,
): PlanQuestionSource {
  return new PlanQuestionSource(
    plan,
    repo,
    new QuestionGenerator(repo, mulberry32(seedQ)),
    new FillLetterGenerator(mulberry32(seedFill)),
    new SpellGenerator(mulberry32(seedSpell)),
  );
}

export default function planQuestionSourceTest() {
  describe('PlanQuestionSource', () => {
    it('emitsChoiceForNormalMonsterByDefault', 0, () => {
      const repo: WordRepository = makeRepo();
      const plan: TodaySessionPlan = planWith(
        [MonsterKind.Normal, MonsterKind.Normal],
        ['fruit-apple', 'fruit-banana']
      );
      const src: PlanQuestionSource = buildSrc(plan, repo, 1, 2, 3);
      src.setMonsterIndexProvider((): number => 1);
      const q: Question = src.nextQuestion();
      expect(q.kind).assertEqual(QuestionKind.Choice);
      expect(q.options.length).assertEqual(3);
    });

    it('emitsFillLetterForSpellingMonster', 0, () => {
      const repo: WordRepository = makeRepo();
      const plan: TodaySessionPlan = planWith(
        [MonsterKind.Spelling],
        ['fruit-banana', 'fruit-orange']
      );
      const src: PlanQuestionSource = buildSrc(plan, repo, 1, 2, 3);
      src.setMonsterIndexProvider((): number => 1);
      const q: Question = src.nextQuestion();
      expect(q.kind).assertEqual(QuestionKind.FillLetter);
      expect(q.letterOptions.length).assertEqual(3);
      expect(q.missingIndex >= 1).assertTrue();
    });

    it('emitsSpellForBossMonsterWithFiveLetterWord', 0, () => {
      const repo: WordRepository = makeRepo();
      const plan: TodaySessionPlan = planWith(
        [MonsterKind.Boss],
        ['fruit-apple']
      );
      const src: PlanQuestionSource = buildSrc(plan, repo, 1, 2, 3);
      src.setMonsterIndexProvider((): number => 1);
      const q: Question = src.nextQuestion();
      expect(q.kind).assertEqual(QuestionKind.Spell);
      expect(q.spellLetters.length).assertEqual(5);
      expect(q.spellRevealedMask[0]).assertTrue();
      expect(q.spellPool.length).assertEqual(4);
    });

    it('emitsSpellForBossMonsterWithSixLetterWord', 0, () => {
      const repo: WordRepository = makeRepo();
      // 'orange' has 6 alphabetic letters — within Spell's 4-9 gate.
      const plan: TodaySessionPlan = planWith(
        [MonsterKind.Boss],
        ['fruit-orange']
      );
      const src: PlanQuestionSource = buildSrc(plan, repo, 1, 2, 3);
      src.setMonsterIndexProvider((): number => 1);
      const q: Question = src.nextQuestion();
      expect(q.kind).assertEqual(QuestionKind.Spell);
    });

    it('bossWithFourLetterWordEmitsSpellAtBoundary', 0, () => {
      const repo: WordRepository = makeRepo();
      const plan: TodaySessionPlan = planWith(
        [MonsterKind.Boss],
        ['w-fish']
      );
      const src: PlanQuestionSource = buildSrc(plan, repo, 4, 5, 6);
      src.setMonsterIndexProvider((): number => 1);
      const q: Question = src.nextQuestion();
      expect(q.kind).assertEqual(QuestionKind.Spell);
      expect(q.spellLetters.length).assertEqual(4);
    });

    it('bossWithThreeLetterWordFallsBackToFillLetter', 0, () => {
      const repo: WordRepository = makeRepo();
      // 'zoo' has 3 letters: spell undefined; medium undefined; fill-letter works.
      const plan: TodaySessionPlan = planWith(
        [MonsterKind.Boss],
        ['place-zoo']
      );
      const src: PlanQuestionSource = buildSrc(plan, repo, 7, 8, 9);
      src.setMonsterIndexProvider((): number => 1);
      const q: Question = src.nextQuestion();
      expect(q.kind).assertEqual(QuestionKind.FillLetter);
    });

    it('bossWithTwoLetterWordFallsBackToChoice', 0, () => {
      const repo: WordRepository = makeRepo();
      // 'TV' has 2 alphabetic letters: spell, medium, and fill-letter all undefined.
      const plan: TodaySessionPlan = planWith(
        [MonsterKind.Boss],
        ['home-tv']
      );
      const src: PlanQuestionSource = buildSrc(plan, repo, 10, 11, 12);
      src.setMonsterIndexProvider((): number => 1);
      const q: Question = src.nextQuestion();
      expect(q.kind).assertEqual(QuestionKind.Choice);
      expect(q.options.length).assertEqual(3);
    });

    it('bossWithLongWordFallsBackToFillLetterMedium', 0, () => {
      const repo: WordRepository = makeRepo();
      // 'extraordinary' has 13 letters: spell undefined (>9), medium works.
      const plan: TodaySessionPlan = planWith(
        [MonsterKind.Boss],
        ['w-extraordinary']
      );
      const src: PlanQuestionSource = buildSrc(plan, repo, 13, 14, 15);
      src.setMonsterIndexProvider((): number => 1);
      const q: Question = src.nextQuestion();
      expect(q.kind).assertEqual(QuestionKind.FillLetterMedium);
    });

    it('emitsFillLetterMediumForEliteMonster', 0, () => {
      const repo: WordRepository = makeRepo();
      const plan: TodaySessionPlan = planWith(
        [MonsterKind.Elite],
        ['fruit-banana']
      );
      const src: PlanQuestionSource = buildSrc(plan, repo, 3, 4, 5);
      src.setMonsterIndexProvider((): number => 1);
      const q: Question = src.nextQuestion();
      expect(q.kind).assertEqual(QuestionKind.FillLetterMedium);
      expect(q.missingIndices.length).assertEqual(2);
    });

    it('eliteNeverEmitsSpellEvenWithLongEnoughWord', 0, () => {
      const repo: WordRepository = makeRepo();
      // V0.4.1 regression guard: Boss split off from Elite, but Elite must
      // continue to emit FillLetterMedium for 4-9 letter words, never Spell.
      const plan: TodaySessionPlan = planWith(
        [MonsterKind.Elite],
        ['fruit-orange']
      );
      const src: PlanQuestionSource = buildSrc(plan, repo, 16, 17, 18);
      src.setMonsterIndexProvider((): number => 1);
      const q: Question = src.nextQuestion();
      expect(q.kind).assertEqual(QuestionKind.FillLetterMedium);
    });

    it('spellingSlotStillEmitsBeginnerFillLetter', 0, () => {
      const repo: WordRepository = makeRepo();
      const plan: TodaySessionPlan = planWith(
        [MonsterKind.Spelling],
        ['fruit-apple']
      );
      const src: PlanQuestionSource = buildSrc(plan, repo, 5, 6, 7);
      src.setMonsterIndexProvider((): number => 1);
      const q: Question = src.nextQuestion();
      expect(q.kind).assertEqual(QuestionKind.FillLetter);
      expect(q.letterOptions.length).assertEqual(3);
    });

    it('eliteWithShortWordFallsBackToBeginnerThenChoice', 0, () => {
      const repo: WordRepository = makeRepo();
      // wordId place-zoo has 3 letters: medium should return undefined; beginner should work.
      const planZoo: TodaySessionPlan = planWith(
        [MonsterKind.Elite],
        ['place-zoo']
      );
      const srcZoo: PlanQuestionSource = buildSrc(planZoo, repo, 7, 8, 9);
      srcZoo.setMonsterIndexProvider((): number => 1);
      const qZoo: Question = srcZoo.nextQuestion();
      expect(qZoo.kind).assertEqual(QuestionKind.FillLetter);

      // wordId home-tv has <3 alphabetic letters: both medium and beginner return undefined; must degrade to choice.
      const planTv: TodaySessionPlan = planWith(
        [MonsterKind.Elite],
        ['home-tv']
      );
      const srcTv: PlanQuestionSource = buildSrc(planTv, repo, 9, 10, 11);
      srcTv.setMonsterIndexProvider((): number => 1);
      const qTv: Question = srcTv.nextQuestion();
      expect(qTv.kind).assertEqual(QuestionKind.Choice);
      expect(qTv.options.length).assertEqual(3);
    });

    it('cyclesWordPlanWhenExhausted', 0, () => {
      const repo: WordRepository = makeRepo();
      const plan: TodaySessionPlan = planWith(
        [MonsterKind.Normal],
        ['fruit-apple', 'fruit-banana']
      );
      const src: PlanQuestionSource = buildSrc(plan, repo, 1, 2, 3);
      src.setMonsterIndexProvider((): number => 1);
      const ids: string[] = [];
      for (let i = 0; i < 5; i++) {
        ids.push(src.nextQuestion().wordId);
      }
      expect(ids.length).assertEqual(5);
      // After 2 unique words the cursor must wrap.
      const unique: Set<string> = new Set<string>();
      for (let i = 0; i < ids.length; i++) {
        unique.add(ids[i]);
      }
      expect(unique.size).assertEqual(2);
    });

    it('switchesQuestionKindAcrossSlots', 0, () => {
      const repo: WordRepository = makeRepo();
      const plan: TodaySessionPlan = planWith(
        [MonsterKind.Normal, MonsterKind.Spelling],
        ['fruit-apple', 'fruit-banana', 'fruit-orange', 'fruit-grape']
      );
      const src: PlanQuestionSource = buildSrc(plan, repo, 1, 2, 3);
      let monster: number = 1;
      src.setMonsterIndexProvider((): number => monster);
      const q1: Question = src.nextQuestion();
      monster = 2;
      const q2: Question = src.nextQuestion();
      expect(q1.kind).assertEqual(QuestionKind.Choice);
      expect(q2.kind).assertEqual(QuestionKind.FillLetter);
    });

    it('skipsLastWordWhenPossible', 0, () => {
      const repo: WordRepository = makeRepo();
      const plan: TodaySessionPlan = planWith(
        [MonsterKind.Normal],
        ['fruit-apple', 'fruit-banana']
      );
      const src: PlanQuestionSource = buildSrc(plan, repo, 1, 2, 3);
      src.setMonsterIndexProvider((): number => 1);
      const next: Question = src.nextQuestion('fruit-apple');
      expect(next.wordId === 'fruit-apple').assertFalse();
    });
  });
}
