import { Question } from '../models/Question';
import { WordEntry } from '../models/WordEntry';
import { WordRepository } from './WordRepository';
import { QuestionGenerator } from './QuestionGenerator';
import { FillLetterGenerator } from './FillLetterGenerator';
import { IQuestionSource } from './IQuestionSource';
import {
  TodaySessionPlan,
  WordSlot,
} from '../models/AdventureRegion';
import { MonsterKind } from '../data/MonsterCatalog';

/**
 * Provider that returns the current 1-based BattleEngine monster
 * slot. Injected by BattlePage after the engine is constructed,
 * because the engine itself is the only authority on its current
 * monsterIndex during a battle.
 */
export type MonsterIndexProvider = () => number;

/**
 * PlanQuestionSource — IQuestionSource that walks `plan.wordPlan`
 * deterministically while letting the current monster's
 * MonsterKind decide whether to render Choice or FillLetter
 * questions. Spelling and Boss monsters always emit FillLetter
 * (degrades to Choice when FillLetterGenerator returns undefined,
 * e.g. for two-letter words). Normal/Review/Elite emit Choice.
 *
 * Cycling: when wordPlan runs out the source wraps back to index
 * 0 so a long battle never stalls. The skip-last-word constraint
 * inherited from QuestionGenerator is respected best-effort.
 */
export class PlanQuestionSource implements IQuestionSource {
  private readonly plan: TodaySessionPlan;
  private readonly repo: WordRepository;
  private readonly choiceGen: QuestionGenerator;
  private readonly fillGen: FillLetterGenerator;
  private monsterIndexProvider: MonsterIndexProvider;
  private cursor: number = 0;

  constructor(
    plan: TodaySessionPlan,
    repo: WordRepository,
    choiceGen: QuestionGenerator,
    fillGen: FillLetterGenerator
  ) {
    this.plan = plan;
    this.repo = repo;
    this.choiceGen = choiceGen;
    this.fillGen = fillGen;
    this.monsterIndexProvider = (): number => 1;
  }

  setMonsterIndexProvider(provider: MonsterIndexProvider): void {
    this.monsterIndexProvider = provider;
  }

  nextQuestion(lastWordId?: string): Question {
    const word: WordEntry = this.pickWord(lastWordId);
    const kind: MonsterKind = this.currentMonsterKind();
    if (kind === MonsterKind.Elite || kind === MonsterKind.Boss) {
      const medium: Question | undefined = this.fillGen.generateMedium(word);
      if (medium !== undefined) {
        return medium;
      }
      const beginner: Question | undefined = this.fillGen.generate(word);
      if (beginner !== undefined) {
        return beginner;
      }
      return this.choiceGen.nextQuestionForWord(word, lastWordId);
    }
    if (kind === MonsterKind.Spelling) {
      const fill: Question | undefined = this.fillGen.generate(word);
      if (fill !== undefined) {
        return fill;
      }
      return this.choiceGen.nextQuestionForWord(word, lastWordId);
    }
    return this.choiceGen.nextQuestionForWord(word, lastWordId);
  }

  /** Test seam — peek at the next slot without advancing. */
  peekNextWordIdForTest(): string {
    const slot: WordSlot | undefined = this.peekSlot();
    return slot !== undefined ? slot.wordId : '';
  }

  private pickWord(lastWordId?: string): WordEntry {
    if (this.plan.wordPlan.length === 0) {
      return this.repo.all()[0];
    }
    let attempts: number = 0;
    while (attempts < this.plan.wordPlan.length) {
      const slot: WordSlot = this.plan.wordPlan[this.cursor % this.plan.wordPlan.length];
      this.cursor = (this.cursor + 1) % this.plan.wordPlan.length;
      attempts += 1;
      if (lastWordId !== undefined && slot.wordId === lastWordId && this.plan.wordPlan.length > 1) {
        continue;
      }
      const w: WordEntry | undefined = this.repo.findById(slot.wordId);
      if (w !== undefined) {
        return w;
      }
    }
    // Fallback: first known word in the plan, then first word in the
    // repo. We never want to throw mid-battle.
    for (let i = 0; i < this.plan.wordPlan.length; i++) {
      const w: WordEntry | undefined = this.repo.findById(this.plan.wordPlan[i].wordId);
      if (w !== undefined) {
        return w;
      }
    }
    return this.repo.all()[0];
  }

  private peekSlot(): WordSlot | undefined {
    if (this.plan.wordPlan.length === 0) {
      return undefined;
    }
    return this.plan.wordPlan[this.cursor % this.plan.wordPlan.length];
  }

  private currentMonsterKind(): MonsterKind {
    const idx1: number = this.monsterIndexProvider();
    const slots: number = this.plan.monsterSlots.length;
    if (slots === 0) {
      return MonsterKind.Normal;
    }
    const i: number = idx1 <= 0 ? 0 : (idx1 - 1) % slots;
    return this.plan.monsterSlots[i].kind;
  }
}
