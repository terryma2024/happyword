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

export class SpellGenerator {
  private readonly rng: RandomFn;

  constructor(rng?: RandomFn) {
    this.rng = rng ?? Math.random;
  }

  generate(word: WordEntry): Question | undefined {
    const lower: string = word.word.toLowerCase();
    const letters: string[] = [];
    for (let i = 0; i < lower.length; i++) {
      const c: string = lower.charAt(i);
      if (c >= 'a' && c <= 'z') {
        letters.push(c);
      }
    }
    if (letters.length < SPELL_MIN_LEN || letters.length > SPELL_MAX_LEN) {
      return undefined;
    }

    const mask: boolean[] = [];
    for (let i = 0; i < letters.length; i++) {
      mask.push(i === 0);
    }

    const remaining: string[] = letters.slice(1);
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
