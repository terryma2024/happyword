import { WordEntry } from '../models/WordEntry';
import { Question, QuestionKind } from '../models/Question';
import { RandomFn, shuffle } from '../utils/shuffle';

const MIN_WORD_LETTERS: number = 3;
const MIN_WORD_LETTERS_MEDIUM: number = 4;
const ALPHABET: string = 'abcdefghijklmnopqrstuvwxyz';
const TOTAL_OPTIONS: number = 3;

/**
 * Generate a beginner fill-letter question (one missing letter,
 * three candidates) from a single WordEntry. Returns undefined
 * for words with fewer than three alphabetic characters so the
 * caller can degrade to a Choice question.
 *
 * Determinism: every random pick reads from `rng` so the same
 * seed produces the same Question.
 */
export class FillLetterGenerator {
  private readonly rng: RandomFn;

  constructor(rng?: RandomFn) {
    this.rng = rng ?? Math.random;
  }

  generate(word: WordEntry, _lastWordId?: string): Question | undefined {
    const lower: string = word.word.toLowerCase();
    const letters: string[] = [];
    for (let i = 0; i < lower.length; i++) {
      const c: string = lower.charAt(i);
      if (c >= 'a' && c <= 'z') {
        letters.push(c);
      }
    }
    if (letters.length < MIN_WORD_LETTERS) {
      return undefined;
    }

    // Pick a missing index from [1, letters.length - 1] so the
    // first letter is never hidden — easier for early readers.
    const missingIndex: number = this.randomInt(1, letters.length - 1);
    const letterAnswer: string = letters[missingIndex];

    // Distractors: random letters not in the word at all (and not
    // equal to letterAnswer). Falls back to "letters not equal to
    // letterAnswer" if the word covers most of the alphabet.
    const wordLetters: Set<string> = new Set<string>();
    for (let i = 0; i < letters.length; i++) {
      wordLetters.add(letters[i]);
    }
    const candidatePool: string[] = [];
    for (let i = 0; i < ALPHABET.length; i++) {
      const c: string = ALPHABET.charAt(i);
      if (wordLetters.has(c)) {
        continue;
      }
      candidatePool.push(c);
    }
    if (candidatePool.length < TOTAL_OPTIONS - 1) {
      candidatePool.length = 0;
      for (let i = 0; i < ALPHABET.length; i++) {
        const c: string = ALPHABET.charAt(i);
        if (c !== letterAnswer) {
          candidatePool.push(c);
        }
      }
    }
    const shuffledPool: string[] = shuffle<string>(candidatePool, this.rng);
    const distractors: string[] = shuffledPool.slice(0, TOTAL_OPTIONS - 1);

    const optionsPlain: string[] = [letterAnswer, distractors[0], distractors[1]];
    const letterOptions: string[] = shuffle<string>(optionsPlain, this.rng);

    const templateParts: string[] = [];
    for (let i = 0; i < letters.length; i++) {
      templateParts.push(i === missingIndex ? '_' : letters[i]);
    }

    const q: Question = new Question();
    q.kind = QuestionKind.FillLetter;
    q.promptZh = word.meaningZh;
    q.answer = word.word;
    q.options = [];
    q.wordId = word.id;
    q.letterTemplate = templateParts.join(' ');
    q.missingIndex = missingIndex;
    q.letterOptions = letterOptions;
    q.letterAnswer = letterAnswer;
    return q;
  }

  /**
   * Generate a medium fill-letter question (two missing letters, two steps).
   * Returns undefined for words shorter than 4 alphabetic characters so the
   * caller can degrade to beginner fill-letter or choice.
   */
  generateMedium(word: WordEntry, _lastWordId?: string): Question | undefined {
    const lower: string = word.word.toLowerCase();
    const letters: string[] = [];
    for (let i = 0; i < lower.length; i++) {
      const c: string = lower.charAt(i);
      if (c >= 'a' && c <= 'z') {
        letters.push(c);
      }
    }
    if (letters.length < MIN_WORD_LETTERS_MEDIUM) {
      return undefined;
    }

    // Pick two distinct missing indices from [1, letters.length - 1].
    // Invariants:
    // - Never hide the first letter.
    // - Always fill blanks left-to-right: step 0 is the smaller index.
    let idxA: number = this.randomInt(1, letters.length - 1);
    let idxB: number = this.randomInt(1, letters.length - 1);
    if (idxB === idxA) {
      // Deterministic "re-pick": shift by one within range.
      idxB = idxB + 1;
      if (idxB > letters.length - 1) {
        idxB = 1;
      }
    }
    if (idxA > idxB) {
      const tmp: number = idxA;
      idxA = idxB;
      idxB = tmp;
    }
    const missingIndices: number[] = [idxA, idxB];
    const answers: string[] = [letters[idxA], letters[idxB]];

    // Base template: both blanks shown as '_' so the UI can render two slots,
    // but the engine will only resolve one step at a time.
    const templateParts: string[] = [];
    for (let i = 0; i < letters.length; i++) {
      templateParts.push((i === idxA || i === idxB) ? '_' : letters[i]);
    }

    // Shared candidate pool: letters not in the word at all.
    const wordLetters: Set<string> = new Set<string>();
    for (let i = 0; i < letters.length; i++) {
      wordLetters.add(letters[i]);
    }
    const poolNoWordLetters: string[] = [];
    for (let i = 0; i < ALPHABET.length; i++) {
      const c: string = ALPHABET.charAt(i);
      if (wordLetters.has(c)) {
        continue;
      }
      poolNoWordLetters.push(c);
    }

    const optionsSteps: string[][] = [];
    for (let step: number = 0; step < 2; step++) {
      const ans: string = answers[step];
      const otherAns: string = answers[step === 0 ? 1 : 0];

      // Prefer distractors that are not in the word and not equal to either answer.
      const candidatePool: string[] = [];
      for (let i = 0; i < poolNoWordLetters.length; i++) {
        const c: string = poolNoWordLetters[i];
        if (c === ans || c === otherAns) {
          continue;
        }
        candidatePool.push(c);
      }
      // Fallback: any letters except answers (even if in the word) when the
      // word covers most of the alphabet.
      if (candidatePool.length < TOTAL_OPTIONS - 1) {
        candidatePool.length = 0;
        for (let i = 0; i < ALPHABET.length; i++) {
          const c: string = ALPHABET.charAt(i);
          if (c === ans || c === otherAns) {
            continue;
          }
          candidatePool.push(c);
        }
      }

      const shuffledPool: string[] = shuffle<string>(candidatePool, this.rng);
      const distractors: string[] = shuffledPool.slice(0, TOTAL_OPTIONS - 1);
      const optionsPlain: string[] = [ans, distractors[0], distractors[1]];
      optionsSteps.push(shuffle<string>(optionsPlain, this.rng));
    }

    const q: Question = new Question();
    q.kind = QuestionKind.FillLetterMedium;
    q.promptZh = word.meaningZh;
    q.answer = word.word;
    q.options = [];
    q.wordId = word.id;
    q.letterTemplateBase = templateParts.join(' ');
    q.missingIndices = missingIndices;
    q.letterOptionsSteps = optionsSteps;
    q.letterAnswers = answers;
    q.currentStep = 0;
    return q;
  }

  private randomInt(minInclusive: number, maxInclusive: number): number {
    if (maxInclusive < minInclusive) {
      return minInclusive;
    }
    const span: number = maxInclusive - minInclusive + 1;
    const r: number = this.rng();
    const idx: number = Math.floor(r * span);
    if (idx < 0) {
      return minInclusive;
    }
    if (idx >= span) {
      return maxInclusive;
    }
    return minInclusive + idx;
  }
}
