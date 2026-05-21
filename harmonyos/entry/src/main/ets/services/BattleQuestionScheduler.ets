import { QuestionKind } from '../models/Question';
import {
  sanitizeEnabledQuestionTypes,
} from './BattleQuestionTypePolicy';
import { RandomFn, shuffle } from '../utils/shuffle';

export enum BattleScheduleMode {
  SingleType = 'single_type',
  IntroOnly = 'intro_only',
  ChallengeOnly = 'challenge_only',
  TwoPhase = 'two_phase',
}

const INTRO_KINDS: string[] = [QuestionKind.Choice, QuestionKind.FillLetter];
const CHALLENGE_KINDS: string[] = [QuestionKind.FillLetterMedium, QuestionKind.Spell];

export type WordKindSupportFn = (wordId: string, kind: string) => boolean;

export class BattleQuestionPick {
  kind: string = '';
  /** When non-empty, PlanQuestionSource should prefer this plan word. */
  preferredWordId: string = '';
}

export function intersectKinds(pool: string[], enabled: string[]): string[] {
  const out: string[] = [];
  for (let i: number = 0; i < pool.length; i++) {
    const k: string = pool[i];
    if (enabled.indexOf(k) >= 0) {
      out.push(k);
    }
  }
  return out;
}

export function deriveScheduleMode(
  enabledTypes: string[],
  introPool: string[],
  challengePool: string[],
): BattleScheduleMode {
  const safe: string[] = sanitizeEnabledQuestionTypes(enabledTypes);
  if (safe.length === 1) {
    return BattleScheduleMode.SingleType;
  }
  if (introPool.length === 0) {
    return BattleScheduleMode.ChallengeOnly;
  }
  if (challengePool.length === 0) {
    return BattleScheduleMode.IntroOnly;
  }
  return BattleScheduleMode.TwoPhase;
}

export class BattleQuestionScheduler {
  private readonly mode: BattleScheduleMode;
  private readonly effectiveIntroPool: string[];
  private readonly effectiveChallengePool: string[];
  private readonly singleType: string;
  private readonly rng: RandomFn;
  private readonly planWordIds: string[];
  private readonly shuffledWordIds: string[];
  private wordCursor: number = 0;
  private readonly servedChoice: string[] = [];
  private readonly servedFillLetter: string[] = [];
  private introPassComplete: boolean = false;
  private lastIntroKind: string = '';

  constructor(planWordIds: string[], enabledTypes: string[], rng?: RandomFn) {
    this.rng = rng ?? Math.random;
    const safe: string[] = sanitizeEnabledQuestionTypes(enabledTypes);
    this.effectiveIntroPool = intersectKinds(INTRO_KINDS, safe);
    this.effectiveChallengePool = intersectKinds(CHALLENGE_KINDS, safe);
    this.mode = deriveScheduleMode(safe, this.effectiveIntroPool, this.effectiveChallengePool);
    this.singleType = safe.length === 1 ? safe[0] : '';
    const ids: string[] = [];
    for (let i: number = 0; i < planWordIds.length; i++) {
      if (planWordIds[i].length > 0 && ids.indexOf(planWordIds[i]) < 0) {
        ids.push(planWordIds[i]);
      }
    }
    this.planWordIds = ids;
    this.shuffledWordIds = shuffle(ids, this.rng);
  }

  scheduleMode(): BattleScheduleMode {
    return this.mode;
  }

  effectiveIntroKinds(): string[] {
    return this.effectiveIntroPool.slice();
  }

  effectiveChallengeKinds(): string[] {
    return this.effectiveChallengePool.slice();
  }

  isIntroPassActive(): boolean {
    if (this.mode === BattleScheduleMode.ChallengeOnly
      || this.mode === BattleScheduleMode.SingleType) {
      return false;
    }
    if (this.mode === BattleScheduleMode.TwoPhase) {
      return !this.introPassComplete;
    }
    // intro_only: active until intro pass completes, then sustain (not "pass")
    return !this.introPassComplete;
  }

  /** Pool used for degradation on the current phase. */
  activePhasePool(): string[] {
    if (this.mode === BattleScheduleMode.SingleType) {
      return [this.singleType];
    }
    if (this.mode === BattleScheduleMode.ChallengeOnly) {
      return this.effectiveChallengePool.slice();
    }
    if (this.isIntroPassActive() || this.mode === BattleScheduleMode.IntroOnly) {
      return this.effectiveIntroPool.slice();
    }
    return this.effectiveChallengePool.slice();
  }

  markServed(wordId: string, kind: string, canServe: WordKindSupportFn): void {
    if (kind === QuestionKind.Choice && this.servedChoice.indexOf(wordId) < 0) {
      this.servedChoice.push(wordId);
    }
    if (kind === QuestionKind.FillLetter && this.servedFillLetter.indexOf(wordId) < 0) {
      this.servedFillLetter.push(wordId);
    }
    if ((this.mode === BattleScheduleMode.TwoPhase
      || this.mode === BattleScheduleMode.IntroOnly) && !this.introPassComplete) {
      if (this.checkIntroPassComplete(canServe)) {
        this.introPassComplete = true;
      }
    }
  }

  pickNext(
    lastWordId: string | undefined,
    canServe: WordKindSupportFn,
  ): BattleQuestionPick {
    const out: BattleQuestionPick = new BattleQuestionPick();
    if (this.mode === BattleScheduleMode.SingleType) {
      out.kind = this.singleType;
      return out;
    }
    if (this.mode === BattleScheduleMode.ChallengeOnly
      || (this.mode === BattleScheduleMode.TwoPhase && this.introPassComplete)) {
      out.kind = this.rollChallengeKind();
      return out;
    }
    if (this.mode === BattleScheduleMode.IntroOnly && this.introPassComplete) {
      return this.pickIntroSustain(lastWordId, canServe);
    }
    return this.pickIntroPass(lastWordId, canServe);
  }

  private rollChallengeKind(): string {
    if (this.effectiveChallengePool.length === 1) {
      return this.effectiveChallengePool[0];
    }
    if (this.effectiveChallengePool.length >= 2) {
      return this.rng() < 0.5
        ? QuestionKind.FillLetterMedium
        : QuestionKind.Spell;
    }
    return QuestionKind.Choice;
  }

  private pickIntroPass(
    lastWordId: string | undefined,
    canServe: WordKindSupportFn,
  ): BattleQuestionPick {
    const pick: BattleQuestionPick = this.scanIntroWords(lastWordId, canServe, true);
    if (pick.kind.length > 0) {
      this.lastIntroKind = pick.kind;
    } else {
      this.introPassComplete = true;
      pick.kind = this.rollChallengeKind();
    }
    return pick;
  }

  private pickIntroSustain(
    lastWordId: string | undefined,
    canServe: WordKindSupportFn,
  ): BattleQuestionPick {
    const pick: BattleQuestionPick = this.scanIntroWords(lastWordId, canServe, false);
    if (pick.kind.length > 0) {
      this.lastIntroKind = pick.kind;
      return pick;
    }
    pick.kind = this.effectiveIntroPool.length > 0
      ? this.effectiveIntroPool[0]
      : QuestionKind.Choice;
    return pick;
  }

  /**
   * @param requireUnserved when true (intro pass), only (word, kind) pairs
   *   not yet served; when false (sustain), allow reuse of words but prefer
   *   kinds still unserved for that word.
   */
  private scanIntroWords(
    lastWordId: string | undefined,
    canServe: WordKindSupportFn,
    requireUnserved: boolean,
  ): BattleQuestionPick {
    const out: BattleQuestionPick = new BattleQuestionPick();
    const order: string[] = this.shuffledWordIds.length > 0
      ? this.shuffledWordIds
      : this.planWordIds;
    const attempts: number = order.length === 0 ? 1 : order.length;
    for (let a: number = 0; a < attempts; a++) {
      const wordId: string = order.length === 0
        ? ''
        : order[(this.wordCursor + a) % order.length];
      if (wordId.length === 0) {
        continue;
      }
      if (lastWordId !== undefined && wordId === lastWordId && order.length > 1) {
        continue;
      }
      const kinds: string[] = this.availableIntroKindsForWord(
        wordId, canServe, requireUnserved);
      if (kinds.length === 0) {
        continue;
      }
      out.preferredWordId = wordId;
      out.kind = this.pickAlternatingIntroKind(kinds);
      this.wordCursor = order.length === 0
        ? 0
        : (this.wordCursor + a + 1) % order.length;
      return out;
    }
    return out;
  }

  private availableIntroKindsForWord(
    wordId: string,
    canServe: WordKindSupportFn,
    requireUnserved: boolean,
  ): string[] {
    const kinds: string[] = [];
    for (let i: number = 0; i < this.effectiveIntroPool.length; i++) {
      const k: string = this.effectiveIntroPool[i];
      if (!canServe(wordId, k)) {
        continue;
      }
      if (requireUnserved && this.isServed(wordId, k)) {
        continue;
      }
      if (!requireUnserved && this.isServed(wordId, k)) {
        continue;
      }
      kinds.push(k);
    }
    if (!requireUnserved) {
      // Sustain: if every intro kind was already served for this word,
      // still allow any intro kind the word supports (reuse).
      if (kinds.length === 0) {
        for (let i: number = 0; i < this.effectiveIntroPool.length; i++) {
          const k: string = this.effectiveIntroPool[i];
          if (canServe(wordId, k)) {
            kinds.push(k);
          }
        }
      }
    }
    return kinds;
  }

  private pickAlternatingIntroKind(kinds: string[]): string {
    if (kinds.length === 1) {
      return kinds[0];
    }
    if (this.lastIntroKind === QuestionKind.Choice
      && kinds.indexOf(QuestionKind.FillLetter) >= 0) {
      return QuestionKind.FillLetter;
    }
    if (this.lastIntroKind === QuestionKind.FillLetter
      && kinds.indexOf(QuestionKind.Choice) >= 0) {
      return QuestionKind.Choice;
    }
    return kinds[0];
  }

  private isServed(wordId: string, kind: string): boolean {
    if (kind === QuestionKind.Choice) {
      return this.servedChoice.indexOf(wordId) >= 0;
    }
    if (kind === QuestionKind.FillLetter) {
      return this.servedFillLetter.indexOf(wordId) >= 0;
    }
    return false;
  }

  private checkIntroPassComplete(canServe: WordKindSupportFn): boolean {
    if (this.planWordIds.length === 0) {
      return true;
    }
    for (let w: number = 0; w < this.planWordIds.length; w++) {
      const wordId: string = this.planWordIds[w];
      for (let k: number = 0; k < this.effectiveIntroPool.length; k++) {
        const kind: string = this.effectiveIntroPool[k];
        if (canServe(wordId, kind) && !this.isServed(wordId, kind)) {
          return false;
        }
      }
    }
    return true;
  }
}
