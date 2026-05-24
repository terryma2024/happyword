import { describe, it, expect } from '@ohos/hypium';
import { mulberry32 } from '../main/ets/utils/shuffle';
import { ExampleSentence, WordEntry } from '../main/ets/models/WordEntry';
import { Question, QuestionKind } from '../main/ets/models/Question';
import { WordRepository } from '../main/ets/services/WordRepository';
import { QuestionGenerator } from '../main/ets/services/QuestionGenerator';
import { FillLetterGenerator } from '../main/ets/services/FillLetterGenerator';
import { SpellGenerator } from '../main/ets/services/SpellGenerator';
import { PlanQuestionSource } from '../main/ets/services/PlanQuestionSource';
import { BattleQuestionScheduler } from '../main/ets/services/BattleQuestionScheduler';
import { DEFAULT_ENABLED_QUESTION_TYPES } from '../main/ets/services/BattleQuestionTypePolicy';
import {
  MonsterPlan,
  MonsterSlot,
  TodaySessionPlan,
  WordSlot,
  WordSource,
} from '../main/ets/models/AdventureRegion';
import { MonsterKind, monsterIndexForKind } from '../main/ets/data/MonsterCatalog';

function makeWord(id: string, word: string): WordEntry {
  const w: WordEntry = new WordEntry();
  w.id = id;
  w.word = word;
  w.meaningZh = '_';
  w.category = 'fruit';
  w.difficulty = 1;
  return w;
}

function makeWordWithExample(id: string, word: string, exampleEn: string, exampleZh: string): WordEntry {
  const w: WordEntry = makeWord(id, word);
  const ex: ExampleSentence = new ExampleSentence();
  ex.en = exampleEn;
  ex.zh = exampleZh;
  w.example = ex;
  return w;
}

function makeRepo(): WordRepository {
  const repo: WordRepository = new WordRepository();
  repo.setEntries([
    makeWordWithExample('fruit-apple', 'apple', 'I eat an apple.', '我吃苹果。'),
    makeWordWithExample('fruit-banana', 'banana', 'The banana is yellow.', '香蕉是黄色的。'),
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
    s.catalogIndex = monsterIndexForKind(monsterKinds[i]);
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

function planWordIds(plan: TodaySessionPlan): string[] {
  const ids: string[] = [];
  for (let i = 0; i < plan.wordPlan.length; i++) {
    ids.push(plan.wordPlan[i].wordId);
  }
  return ids;
}

function buildSrc(
  plan: TodaySessionPlan,
  repo: WordRepository,
  seedQ: number,
  seedFill: number,
  seedSpell: number,
  enabledTypes: string[],
): PlanQuestionSource {
  const scheduler: BattleQuestionScheduler = new BattleQuestionScheduler(
    planWordIds(plan),
    enabledTypes,
    mulberry32(seedQ),
  );
  return new PlanQuestionSource(
    plan,
    repo,
    new QuestionGenerator(repo, mulberry32(seedQ)),
    new FillLetterGenerator(mulberry32(seedFill)),
    new SpellGenerator(mulberry32(seedSpell)),
    scheduler,
  );
}

export default function planQuestionSourceTest() {
  describe('PlanQuestionSource', () => {
    it('emitsChoiceWhenOnlyChoiceEnabled', 0, () => {
      const repo: WordRepository = makeRepo();
      const plan: TodaySessionPlan = planWith(
        [MonsterKind.Normal, MonsterKind.Normal],
        ['fruit-apple', 'fruit-banana']
      );
      const src: PlanQuestionSource = buildSrc(
        plan, repo, 1, 2, 3, [QuestionKind.Choice]);
      const q: Question = src.nextQuestion();
      expect(q.kind).assertEqual(QuestionKind.Choice);
      expect(q.options.length).assertEqual(3);
    });

    it('emitsFillLetterWhenOnlyFillLetterEnabled', 0, () => {
      const repo: WordRepository = makeRepo();
      const plan: TodaySessionPlan = planWith(
        [MonsterKind.Spelling],
        ['fruit-banana', 'fruit-orange']
      );
      const src: PlanQuestionSource = buildSrc(
        plan, repo, 1, 2, 3, [QuestionKind.FillLetter]);
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
      const src: PlanQuestionSource = buildSrc(plan, repo, 1, 2, 3, [QuestionKind.Spell]);
      const q: Question = src.nextQuestion();
      expect(q.kind).assertEqual(QuestionKind.Spell);
      expect(q.spellLetters.length).assertEqual(5);
      expect(q.spellRevealedMask[0]).assertTrue();
      expect(q.spellPool.length).assertEqual(4);
    });

    it('emitsSpellForBossMonsterWithSixLetterWord', 0, () => {
      const repo: WordRepository = makeRepo();
      const plan: TodaySessionPlan = planWith(
        [MonsterKind.Boss],
        ['fruit-orange']
      );
      const src: PlanQuestionSource = buildSrc(plan, repo, 1, 2, 3, [QuestionKind.Spell]);
      const q: Question = src.nextQuestion();
      expect(q.kind).assertEqual(QuestionKind.Spell);
    });

    it('bossWithFourLetterWordEmitsSpellAtBoundary', 0, () => {
      const repo: WordRepository = makeRepo();
      const plan: TodaySessionPlan = planWith(
        [MonsterKind.Boss],
        ['w-fish']
      );
      const src: PlanQuestionSource = buildSrc(plan, repo, 4, 5, 6, [QuestionKind.Spell]);
      const q: Question = src.nextQuestion();
      expect(q.kind).assertEqual(QuestionKind.Spell);
      expect(q.spellLetters.length).assertEqual(4);
    });

    it('bossWithNoSpellEligibleWordFallsBackToChoice', 0, () => {
      const repo: WordRepository = makeRepo();
      const plan: TodaySessionPlan = planWith(
        [MonsterKind.Boss],
        ['place-zoo']
      );
      const src: PlanQuestionSource = buildSrc(
        plan, repo, 7, 8, 9, [QuestionKind.Spell, QuestionKind.Choice]);
      const q: Question = src.nextQuestion();
      expect(q.kind).assertEqual(QuestionKind.Choice);
    });

    it('bossSkipsIneligibleWordsInsteadOfFallingBackToFillLetter', 0, () => {
      const repo: WordRepository = makeRepo();
      const plan: TodaySessionPlan = planWith(
        [MonsterKind.Boss],
        ['place-zoo', 'fruit-apple']
      );
      const src: PlanQuestionSource = buildSrc(plan, repo, 7, 8, 9, [QuestionKind.Spell]);
      const q: Question = src.nextQuestion();
      expect(q.wordId).assertEqual('fruit-apple');
      expect(q.kind).assertEqual(QuestionKind.Spell);
    });

    it('bossWithTwoLetterWordFallsBackToChoice', 0, () => {
      const repo: WordRepository = makeRepo();
      const plan: TodaySessionPlan = planWith(
        [MonsterKind.Boss],
        ['home-tv']
      );
      const src: PlanQuestionSource = buildSrc(
        plan, repo, 10, 11, 12, [QuestionKind.Spell, QuestionKind.Choice]);
      const q: Question = src.nextQuestion();
      expect(q.kind).assertEqual(QuestionKind.Choice);
      expect(q.options.length).assertEqual(3);
    });

    it('bossWithOnlyTooLongWordFallsBackToChoice', 0, () => {
      const repo: WordRepository = makeRepo();
      const plan: TodaySessionPlan = planWith(
        [MonsterKind.Boss],
        ['w-extraordinary']
      );
      const src: PlanQuestionSource = buildSrc(
        plan, repo, 13, 14, 15, [QuestionKind.Spell, QuestionKind.Choice]);
      const q: Question = src.nextQuestion();
      expect(q.kind).assertEqual(QuestionKind.Choice);
    });

    it('emitsFillLetterMediumWhenOnlyMediumEnabled', 0, () => {
      const repo: WordRepository = makeRepo();
      const plan: TodaySessionPlan = planWith(
        [MonsterKind.Elite],
        ['fruit-banana']
      );
      const src: PlanQuestionSource = buildSrc(
        plan, repo, 3, 4, 5, [QuestionKind.FillLetterMedium]);
      const q: Question = src.nextQuestion();
      expect(q.kind).assertEqual(QuestionKind.FillLetterMedium);
      expect(q.missingIndices.length).assertEqual(2);
    });

    it('emitsSentenceClozeWhenOnlySentenceClozeEnabled', 0, () => {
      const repo: WordRepository = makeRepo();
      const plan: TodaySessionPlan = planWith(
        [MonsterKind.Boss],
        ['fruit-apple']
      );
      const src: PlanQuestionSource = buildSrc(
        plan, repo, 3, 4, 5, [QuestionKind.SentenceCloze]);
      const q: Question = src.nextQuestion();
      expect(q.kind).assertEqual(QuestionKind.SentenceCloze);
      expect(q.sentenceTemplate).assertEqual('I eat an ____.');
      expect(q.sentenceZh).assertEqual('我吃苹果。');
    });

    it('sentenceClozeOnlyFallsBackToChoiceWhenNoWordHasExample', 0, () => {
      const repo: WordRepository = makeRepo();
      const plan: TodaySessionPlan = planWith(
        [MonsterKind.Boss],
        ['fruit-orange']
      );
      const src: PlanQuestionSource = buildSrc(
        plan, repo, 3, 4, 5, [QuestionKind.SentenceCloze]);
      const q: Question = src.nextQuestion();
      expect(q.kind).assertEqual(QuestionKind.Choice);
    });

    it('challengeOnlyNeverEmitsSpellFromEliteSlot', 0, () => {
      const repo: WordRepository = makeRepo();
      const plan: TodaySessionPlan = planWith(
        [MonsterKind.Elite],
        ['fruit-orange']
      );
      const src: PlanQuestionSource = buildSrc(
        plan, repo, 16, 17, 18, [QuestionKind.FillLetterMedium]);
      const q: Question = src.nextQuestion();
      expect(q.kind).assertEqual(QuestionKind.FillLetterMedium);
    });

    it('eliteWithNoMediumEligibleWordFallsBackToChoice', 0, () => {
      const repo: WordRepository = makeRepo();
      const planZoo: TodaySessionPlan = planWith(
        [MonsterKind.Elite],
        ['place-zoo']
      );
      const srcZoo: PlanQuestionSource = buildSrc(
        planZoo, repo, 7, 8, 9, [QuestionKind.FillLetterMedium, QuestionKind.Choice]);
      const qZoo: Question = srcZoo.nextQuestion();
      expect(qZoo.kind).assertEqual(QuestionKind.Choice);

      const planTv: TodaySessionPlan = planWith(
        [MonsterKind.Elite],
        ['home-tv']
      );
      const srcTv: PlanQuestionSource = buildSrc(
        planTv, repo, 9, 10, 11, [QuestionKind.FillLetterMedium, QuestionKind.Choice]);
      const qTv: Question = srcTv.nextQuestion();
      expect(qTv.kind).assertEqual(QuestionKind.Choice);
      expect(qTv.options.length).assertEqual(3);
    });

    it('eliteSkipsIneligibleWordsInsteadOfFallingBackToBeginner', 0, () => {
      const repo: WordRepository = makeRepo();
      const plan: TodaySessionPlan = planWith(
        [MonsterKind.Elite],
        ['place-zoo', 'fruit-mango']
      );
      const src: PlanQuestionSource = buildSrc(
        plan, repo, 7, 8, 9, [QuestionKind.FillLetterMedium]);
      const q: Question = src.nextQuestion();
      expect(q.wordId).assertEqual('fruit-mango');
      expect(q.kind).assertEqual(QuestionKind.FillLetterMedium);
    });

    it('cyclesWordPlanWhenExhausted', 0, () => {
      const repo: WordRepository = makeRepo();
      const plan: TodaySessionPlan = planWith(
        [MonsterKind.Normal],
        ['fruit-apple', 'fruit-banana']
      );
      const src: PlanQuestionSource = buildSrc(plan, repo, 1, 2, 3, [QuestionKind.Choice]);
      const ids: string[] = [];
      for (let i = 0; i < 5; i++) {
        ids.push(src.nextQuestion().wordId);
      }
      expect(ids.length).assertEqual(5);
      const unique: Set<string> = new Set<string>();
      for (let i = 0; i < ids.length; i++) {
        unique.add(ids[i]);
      }
      expect(unique.size).assertEqual(2);
    });

    it('twoPhaseReachesChallengeKindsAfterIntro', 0, () => {
      const repo: WordRepository = makeRepo();
      const plan: TodaySessionPlan = planWith(
        [MonsterKind.Normal, MonsterKind.Spelling],
        ['fruit-apple', 'fruit-banana', 'fruit-orange', 'fruit-grape']
      );
      const src: PlanQuestionSource = buildSrc(
        plan, repo, 1, 2, 3, DEFAULT_ENABLED_QUESTION_TYPES.slice());
      const kinds: string[] = [];
      for (let i = 0; i < 12; i++) {
        kinds.push(src.nextQuestion().kind);
      }
      expect(kinds.indexOf(QuestionKind.Choice) >= 0).assertTrue();
      expect(kinds.indexOf(QuestionKind.FillLetter) >= 0).assertTrue();
      let sawChallenge = false;
      for (let i = 0; i < kinds.length; i++) {
        if (kinds[i] === QuestionKind.FillLetterMedium
          || kinds[i] === QuestionKind.Spell
          || kinds[i] === QuestionKind.SentenceCloze) {
          sawChallenge = true;
        }
      }
      expect(sawChallenge).assertTrue();
    });

    it('skipsLastWordWhenPossible', 0, () => {
      const repo: WordRepository = makeRepo();
      const plan: TodaySessionPlan = planWith(
        [MonsterKind.Normal],
        ['fruit-apple', 'fruit-banana']
      );
      const src: PlanQuestionSource = buildSrc(plan, repo, 1, 2, 3, [QuestionKind.Choice]);
      const next: Question = src.nextQuestion('fruit-apple');
      expect(next.wordId === 'fruit-apple').assertFalse();
    });
  });
}
