import { WordEntry } from '../models/WordEntry';
import { Question, QuestionKind } from '../models/Question';
import { RandomFn, shuffle } from '../utils/shuffle';

const MIN_WORD_LETTERS: number = 3;
const MIN_WORD_LETTERS_MEDIUM: number = 4;
const ALPHABET: string = 'abcdefghijklmnopqrstuvwxyz';
const TOTAL_OPTIONS: number = 3;
const WORD_SPACE_TEMPLATE_TOKEN: string = ' ';

class PhraseToken {
  glyph: string = '';
  originalIndex: number = -1;
  isLetter: boolean = false;
  isArticle: boolean = false;
}

function isAsciiLetter(c: string): boolean {
  return c >= 'a' && c <= 'z';
}

function isArticleWord(word: string): boolean {
  return word === 'a' || word === 'an' || word === 'the';
}

function phraseTokens(raw: string): PhraseToken[] {
  const lower: string = raw.toLowerCase();
  const articlePositions: Set<number> = new Set<number>();
  let i: number = 0;
  while (i < lower.length) {
    const c: string = lower.charAt(i);
    if (!isAsciiLetter(c)) {
      i++;
      continue;
    }
    const start: number = i;
    let word: string = '';
    while (i < lower.length && isAsciiLetter(lower.charAt(i))) {
      word += lower.charAt(i);
      i++;
    }
    if (isArticleWord(word)) {
      for (let p: number = start; p < i; p++) {
        articlePositions.add(p);
      }
    }
  }

  const out: PhraseToken[] = [];
  for (let pos: number = 0; pos < lower.length; pos++) {
    const c: string = lower.charAt(pos);
    if (isAsciiLetter(c)) {
      const token: PhraseToken = new PhraseToken();
      token.glyph = c;
      token.originalIndex = pos;
      token.isLetter = true;
      token.isArticle = articlePositions.has(pos);
      out.push(token);
    } else if (c === ' ') {
      const token: PhraseToken = new PhraseToken();
      token.glyph = WORD_SPACE_TEMPLATE_TOKEN;
      token.originalIndex = pos;
      token.isLetter = false;
      token.isArticle = false;
      out.push(token);
    }
  }
  return out;
}

function fillableTokens(tokens: PhraseToken[]): PhraseToken[] {
  const out: PhraseToken[] = [];
  for (let i: number = 0; i < tokens.length; i++) {
    const token: PhraseToken = tokens[i];
    if (token.isLetter && !token.isArticle) {
      out.push(token);
    }
  }
  return out;
}

function allLetters(tokens: PhraseToken[]): string[] {
  const out: string[] = [];
  for (let i: number = 0; i < tokens.length; i++) {
    if (tokens[i].isLetter) {
      out.push(tokens[i].glyph);
    }
  }
  return out;
}

function templateFromTokens(tokens: PhraseToken[], missingPositions: Set<number>): string {
  const parts: string[] = [];
  for (let i: number = 0; i < tokens.length; i++) {
    const token: PhraseToken = tokens[i];
    if (token.isLetter && missingPositions.has(token.originalIndex)) {
      parts.push('_');
    } else {
      parts.push(token.glyph);
    }
  }
  return parts.join(' ');
}

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
    const tokens: PhraseToken[] = phraseTokens(word.word);
    const letters: string[] = allLetters(tokens);
    const fillable: PhraseToken[] = fillableTokens(tokens);
    if (fillable.length < MIN_WORD_LETTERS) {
      return undefined;
    }

    // Pick from content letters only: articles (a/an/the) and spaces are
    // displayed, never asked for. Keep the first content letter visible.
    const missingToken: PhraseToken = fillable[this.randomInt(1, fillable.length - 1)];
    const missingIndex: number = missingToken.originalIndex;
    const letterAnswer: string = missingToken.glyph;

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

    const missingPositions: Set<number> = new Set<number>();
    missingPositions.add(missingIndex);

    const q: Question = new Question();
    q.kind = QuestionKind.FillLetter;
    q.promptZh = word.meaningZh;
    q.answer = word.word;
    q.options = [];
    q.wordId = word.id;
    q.letterTemplate = templateFromTokens(tokens, missingPositions);
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
    const tokens: PhraseToken[] = phraseTokens(word.word);
    const letters: string[] = allLetters(tokens);
    const fillable: PhraseToken[] = fillableTokens(tokens);
    if (fillable.length < MIN_WORD_LETTERS_MEDIUM) {
      return undefined;
    }

    // Pick two distinct missing content letters.
    // Invariants:
    // - Never hide spaces or article letters.
    // - Never hide the first content letter.
    // - Always fill blanks left-to-right: step 0 is the smaller index.
    let fillIdxA: number = this.randomInt(1, fillable.length - 1);
    let fillIdxB: number = this.randomInt(1, fillable.length - 1);
    if (fillIdxB === fillIdxA) {
      // Deterministic "re-pick": shift by one within range.
      fillIdxB = fillIdxB + 1;
      if (fillIdxB > fillable.length - 1) {
        fillIdxB = 1;
      }
    }
    let idxA: number = fillable[fillIdxA].originalIndex;
    let idxB: number = fillable[fillIdxB].originalIndex;
    if (idxA > idxB) {
      const tmp: number = idxA;
      idxA = idxB;
      idxB = tmp;
    }
    const missingIndices: number[] = [idxA, idxB];
    const answers: string[] = [
      word.word.toLowerCase().charAt(idxA),
      word.word.toLowerCase().charAt(idxB),
    ];

    // Base template: both blanks shown as '_' so the UI can render two slots,
    // but the engine will only resolve one step at a time.
    const missingPositions: Set<number> = new Set<number>();
    missingPositions.add(idxA);
    missingPositions.add(idxB);

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
    q.letterTemplateBase = templateFromTokens(tokens, missingPositions);
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
