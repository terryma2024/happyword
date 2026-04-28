import { describe, it, expect } from '@ohos/hypium';
import { mulberry32 } from '../main/ets/utils/shuffle';
import { WordEntry } from '../main/ets/models/WordEntry';
import { Question, QuestionKind } from '../main/ets/models/Question';
import { WordRepository } from '../main/ets/services/WordRepository';
import { QuestionGenerator } from '../main/ets/services/QuestionGenerator';
import { FillLetterGenerator } from '../main/ets/services/FillLetterGenerator';
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

export default function planQuestionSourceTest() {
  describe('PlanQuestionSource', () => {
    it('emitsChoiceForNormalMonsterByDefault', 0, () => {
      const repo: WordRepository = makeRepo();
      const plan: TodaySessionPlan = planWith(
        [MonsterKind.Normal, MonsterKind.Normal],
        ['fruit-apple', 'fruit-banana']
      );
      const src: PlanQuestionSource = new PlanQuestionSource(
        plan,
        repo,
        new QuestionGenerator(repo, mulberry32(1)),
        new FillLetterGenerator(mulberry32(2))
      );
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
      const src: PlanQuestionSource = new PlanQuestionSource(
        plan,
        repo,
        new QuestionGenerator(repo, mulberry32(1)),
        new FillLetterGenerator(mulberry32(2))
      );
      src.setMonsterIndexProvider((): number => 1);
      const q: Question = src.nextQuestion();
      expect(q.kind).assertEqual(QuestionKind.FillLetter);
      expect(q.letterOptions.length).assertEqual(3);
      expect(q.missingIndex >= 1).assertTrue();
    });

    it('emitsFillLetterForBossMonster', 0, () => {
      const repo: WordRepository = makeRepo();
      const plan: TodaySessionPlan = planWith(
        [MonsterKind.Boss],
        ['fruit-orange']
      );
      const src: PlanQuestionSource = new PlanQuestionSource(
        plan,
        repo,
        new QuestionGenerator(repo, mulberry32(1)),
        new FillLetterGenerator(mulberry32(2))
      );
      src.setMonsterIndexProvider((): number => 1);
      const q: Question = src.nextQuestion();
      expect(q.kind).assertEqual(QuestionKind.FillLetter);
    });

    it('cyclesWordPlanWhenExhausted', 0, () => {
      const repo: WordRepository = makeRepo();
      const plan: TodaySessionPlan = planWith(
        [MonsterKind.Normal],
        ['fruit-apple', 'fruit-banana']
      );
      const src: PlanQuestionSource = new PlanQuestionSource(
        plan,
        repo,
        new QuestionGenerator(repo, mulberry32(1)),
        new FillLetterGenerator(mulberry32(2))
      );
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
      const src: PlanQuestionSource = new PlanQuestionSource(
        plan,
        repo,
        new QuestionGenerator(repo, mulberry32(1)),
        new FillLetterGenerator(mulberry32(2))
      );
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
      const src: PlanQuestionSource = new PlanQuestionSource(
        plan,
        repo,
        new QuestionGenerator(repo, mulberry32(1)),
        new FillLetterGenerator(mulberry32(2))
      );
      src.setMonsterIndexProvider((): number => 1);
      const next: Question = src.nextQuestion('fruit-apple');
      expect(next.wordId === 'fruit-apple').assertFalse();
    });
  });
}
