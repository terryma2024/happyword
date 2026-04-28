import { WordEntry } from '../models/WordEntry';
import { Question, QuestionKind } from '../models/Question';
import { RandomFn, shuffle } from '../utils/shuffle';

const MIN_WORD_LETTERS: number = 3;
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
