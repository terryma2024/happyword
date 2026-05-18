import { Question } from '../models/Question';
import { WordEntry } from '../models/WordEntry';
import { WordRepository } from './WordRepository';
import { QuestionGenerator } from './QuestionGenerator';
import { FillLetterGenerator } from './FillLetterGenerator';
import { SpellGenerator } from './SpellGenerator';
import { IQuestionSource } from './IQuestionSource';
import {
  resolveQuestionTypeForWord,
  resolveQuestionTypeWithinPool,
  wordSupportsQuestionType,
} from './BattleQuestionTypePolicy';
import {
  BattleQuestionPick,
  BattleQuestionScheduler,
  WordKindSupportFn,
} from './BattleQuestionScheduler';
import {
  TodaySessionPlan,
  WordSlot,
} from '../models/AdventureRegion';

/**
 * Provider that returns the current 1-based BattleEngine monster
 * slot. Injected by BattlePage after the engine is constructed,
 * because the engine itself is the only authority on its current
 * monsterIndex during a battle.
 */
export type MonsterIndexProvider = () => number;

/**
 * PlanQuestionSource — IQuestionSource that walks `plan.wordPlan`
 * while V0.8.4 {@link BattleQuestionScheduler} picks question kinds
 * from Config-enabled types (intro pass → challenge, or mode-specific).
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
  private readonly spellGen: SpellGenerator;
  private readonly scheduler: BattleQuestionScheduler | undefined;
  private monsterIndexProvider: MonsterIndexProvider;
  private cursor: number = 0;

  constructor(
    plan: TodaySessionPlan,
    repo: WordRepository,
    choiceGen: QuestionGenerator,
    fillGen: FillLetterGenerator,
    spellGen: SpellGenerator,
    scheduler?: BattleQuestionScheduler,
  ) {
    this.plan = plan;
    this.repo = repo;
    this.choiceGen = choiceGen;
    this.fillGen = fillGen;
    this.spellGen = spellGen;
    this.scheduler = scheduler;
    this.monsterIndexProvider = (): number => 1;
  }

  setMonsterIndexProvider(provider: MonsterIndexProvider): void {
    this.monsterIndexProvider = provider;
  }

  nextQuestion(lastWordId?: string): Question {
    const canServe: WordKindSupportFn = (wordId: string, kind: string): boolean => {
      const w: WordEntry | undefined = this.repo.findById(wordId);
      return w !== undefined && wordSupportsQuestionType(w, kind);
    };

    let primaryType: string;
    let preferredWordId: string = '';
    if (this.scheduler !== undefined) {
      const pick: BattleQuestionPick = this.scheduler.pickNext(lastWordId, canServe);
      primaryType = pick.kind;
      preferredWordId = pick.preferredWordId;
    } else {
      primaryType = 'choice';
    }

    const phasePool: string[] = this.scheduler !== undefined
      ? this.scheduler.activePhasePool()
      : [];

    let word: WordEntry;
    if (preferredWordId.length > 0) {
      const preferred: WordEntry | undefined = this.repo.findById(preferredWordId);
      word = preferred !== undefined ? preferred : this.pickWordForQuestionType(primaryType, lastWordId);
    } else {
      word = this.pickWordForQuestionType(primaryType, lastWordId);
    }

    const resolvedType: string = this.scheduler !== undefined
      ? resolveQuestionTypeWithinPool(word, primaryType, phasePool)
      : resolveQuestionTypeForWord(word, primaryType);

    const exact: Question | undefined = this.generateExactQuestion(resolvedType, word, lastWordId);
    if (exact !== undefined) {
      if (this.scheduler !== undefined) {
        this.scheduler.markServed(word.id, exact.kind, canServe);
      }
      return exact;
    }
    const fallback: Question = this.choiceGen.nextQuestionForWord(word, lastWordId);
    if (this.scheduler !== undefined) {
      this.scheduler.markServed(word.id, fallback.kind, canServe);
    }
    return fallback;
  }

  private generateExactQuestion(
    targetType: string,
    word: WordEntry,
    lastWordId?: string,
  ): Question | undefined {
    if (targetType === 'fill-letter') {
      return this.fillGen.generate(word);
    }
    if (targetType === 'fill-letter-medium') {
      return this.fillGen.generateMedium(word);
    }
    if (targetType === 'spell') {
      return this.spellGen.generate(word);
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
    for (let i = 0; i < this.plan.wordPlan.length; i++) {
      const w: WordEntry | undefined = this.repo.findById(this.plan.wordPlan[i].wordId);
      if (w !== undefined) {
        return w;
      }
    }
    return this.repo.all()[0];
  }

  private pickWordForQuestionType(targetType: string, lastWordId?: string): WordEntry {
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
      if (w !== undefined && wordSupportsQuestionType(w, targetType)) {
        return w;
      }
    }
    return this.pickWord(lastWordId);
  }

  private peekSlot(): WordSlot | undefined {
    if (this.plan.wordPlan.length === 0) {
      return undefined;
    }
    return this.plan.wordPlan[this.cursor % this.plan.wordPlan.length];
  }
}
