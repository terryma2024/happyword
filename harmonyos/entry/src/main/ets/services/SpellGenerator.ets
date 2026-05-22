import { WordEntry } from '../models/WordEntry';
import { Question, QuestionKind } from '../models/Question';
import { RandomFn, shuffle } from '../utils/shuffle';

/**
 * V0.4.1 Spell question generator.
 *
 * Takes a WordEntry and produces a Spell question whose first letter
 * is pre-revealed and whose pool is the remaining letters in a
 * deterministic shuffle of the injected RNG. Returns undefined when
 * the word's alphabetic length falls outside [SPELL_MIN_LEN, SPELL_MAX_LEN]
 * so the caller can fall back to FillLetterMedium / FillLetter / Choice.
 *
 * Why 4-9:
 * - Lower bound 4: 3-letter words overlap too much with single-blank
 *   FillLetter and lose the "spell the whole word" feel.
 * - Upper bound 9: keeps the slot row + pool row inside the horizontal
 *   battle UI on 480p devices without folding/scaling.
 *
 * Pure & RNG-injected, mirroring FillLetterGenerator.
 */
const SPELL_MIN_LEN: number = 4;
const SPELL_MAX_LEN: number = 9;

class PhraseToken {
  glyph: string = '';
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
      token.isLetter = true;
      token.isArticle = articlePositions.has(pos);
      out.push(token);
    } else if (c === ' ') {
      const token: PhraseToken = new PhraseToken();
      token.glyph = ' ';
      token.isLetter = false;
      token.isArticle = false;
      out.push(token);
    }
  }
  return out;
}

export class SpellGenerator {
  private readonly rng: RandomFn;

  constructor(rng?: RandomFn) {
    this.rng = rng ?? Math.random;
  }

  generate(word: WordEntry): Question | undefined {
    const tokens: PhraseToken[] = phraseTokens(word.word);
    const fillableIndices: number[] = [];
    const letters: string[] = [];
    for (let i: number = 0; i < tokens.length; i++) {
      letters.push(tokens[i].glyph);
      if (tokens[i].isLetter && !tokens[i].isArticle) {
        fillableIndices.push(i);
      }
    }
    if (fillableIndices.length < SPELL_MIN_LEN || fillableIndices.length > SPELL_MAX_LEN) {
      return undefined;
    }

    const mask: boolean[] = [];
    for (let i = 0; i < letters.length; i++) {
      mask.push(!tokens[i].isLetter || tokens[i].isArticle || i === fillableIndices[0]);
    }

    const remaining: string[] = [];
    for (let i: number = 1; i < fillableIndices.length; i++) {
      remaining.push(letters[fillableIndices[i]]);
    }
    const pool: string[] = shuffle<string>(remaining, this.rng);

    const q: Question = new Question();
    q.kind = QuestionKind.Spell;
    q.promptZh = word.meaningZh;
    q.answer = word.word;
    q.options = [];
    q.wordId = word.id;
    q.spellLetters = letters;
    q.spellRevealedMask = mask;
    q.spellPool = pool;
    return q;
  }
}
