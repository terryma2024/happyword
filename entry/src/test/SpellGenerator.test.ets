import { describe, it, expect } from '@ohos/hypium';
import { WordEntry } from '../main/ets/models/WordEntry';
import { Question, QuestionKind } from '../main/ets/models/Question';
import { SpellGenerator } from '../main/ets/services/SpellGenerator';
import { mulberry32 } from '../main/ets/utils/shuffle';

function makeWord(id: string, word: string): WordEntry {
  const e: WordEntry = new WordEntry();
  e.id = id;
  e.word = word;
  e.meaningZh = word;
  e.category = 'fruit';
  e.difficulty = 1;
  return e;
}

function multisetEqual(a: string[], b: string[]): boolean {
  if (a.length !== b.length) {
    return false;
  }
  const counts: Map<string, number> = new Map<string, number>();
  for (let i = 0; i < a.length; i++) {
    const prev: number = counts.has(a[i]) ? (counts.get(a[i]) as number) : 0;
    counts.set(a[i], prev + 1);
  }
  for (let i = 0; i < b.length; i++) {
    const c: string = b[i];
    if (!counts.has(c)) {
      return false;
    }
    const remaining: number = (counts.get(c) as number) - 1;
    if (remaining < 0) {
      return false;
    }
    counts.set(c, remaining);
  }
  const values: IterableIterator<number> = counts.values();
  let next: IteratorResult<number> = values.next();
  while (!next.done) {
    if (next.value !== 0) {
      return false;
    }
    next = values.next();
  }
  return true;
}

export default function spellGeneratorTest() {
  describe('SpellGenerator', () => {
    it('producesWellFormedSpellQuestion', 0, () => {
      const gen: SpellGenerator = new SpellGenerator(mulberry32(1));
      const q: Question | undefined = gen.generate(makeWord('fruit-apple', 'apple'));
      expect(q !== undefined).assertTrue();
      const qq: Question = q as Question;
      expect(qq.kind).assertEqual(QuestionKind.Spell);
      expect(qq.answer).assertEqual('apple');
      expect(qq.spellLetters.length).assertEqual(5);
      expect(qq.spellRevealedMask[0]).assertTrue();
      expect(qq.spellRevealedMask[1]).assertFalse();
      expect(qq.spellPool.length).assertEqual(4);
      expect(multisetEqual(qq.spellPool, ['p', 'p', 'l', 'e'])).assertTrue();
      expect(qq.isValid()).assertTrue();
    });

    it('returnsUndefinedForWordsShorterThanFour', 0, () => {
      const gen: SpellGenerator = new SpellGenerator(mulberry32(2));
      expect(gen.generate(makeWord('fruit-cat', 'cat')) === undefined).assertTrue();
      expect(gen.generate(makeWord('home-go', 'go')) === undefined).assertTrue();
    });

    it('returnsUndefinedForWordsLongerThanNine', 0, () => {
      const gen: SpellGenerator = new SpellGenerator(mulberry32(3));
      expect(gen.generate(makeWord('fruit-strawberry', 'strawberry')) === undefined).assertTrue();
    });

    it('acceptsBoundaryFourAndNineLetterWords', 0, () => {
      const gen: SpellGenerator = new SpellGenerator(mulberry32(4));
      expect(gen.generate(makeWord('w-fish', 'fish')) !== undefined).assertTrue();
      expect(gen.generate(makeWord('w-elephants', 'elephants')) !== undefined).assertTrue();
    });

    it('isDeterministicGivenSameSeed', 0, () => {
      const a: Question = new SpellGenerator(mulberry32(42))
        .generate(makeWord('fruit-banana', 'banana')) as Question;
      const b: Question = new SpellGenerator(mulberry32(42))
        .generate(makeWord('fruit-banana', 'banana')) as Question;
      expect(a.spellPool.length).assertEqual(b.spellPool.length);
      for (let i = 0; i < a.spellPool.length; i++) {
        expect(a.spellPool[i]).assertEqual(b.spellPool[i]);
      }
    });

    it('handlesRepeatedLetters', 0, () => {
      const gen: SpellGenerator = new SpellGenerator(mulberry32(5));
      const q: Question = gen.generate(makeWord('w-letter', 'letter')) as Question;
      expect(q.spellLetters.length).assertEqual(6);
      expect(q.spellPool.length).assertEqual(5);
      // Pool must contain 1 e, 2 t, 1 e, 1 r => actually letters[1..] = e, t, t, e, r
      // Multiset: {e:2, t:2, r:1}
      expect(multisetEqual(q.spellPool, ['e', 't', 't', 'e', 'r'])).assertTrue();
      expect(q.isValid()).assertTrue();
    });

    it('lowercasesUppercaseInput', 0, () => {
      const gen: SpellGenerator = new SpellGenerator(mulberry32(6));
      const q: Question = gen.generate(makeWord('w-Apple', 'Apple')) as Question;
      // Letters extracted as lowercase a-z only.
      expect(q.spellLetters[0]).assertEqual('a');
      expect(q.spellLetters[1]).assertEqual('p');
      expect(q.isValid()).assertTrue();
    });

    it('skipsNonAlphabeticChars', 0, () => {
      const gen: SpellGenerator = new SpellGenerator(mulberry32(7));
      // Hyphen counts as 0 alphabetic; 'ice-cream' has 8 a-z chars => still valid.
      const q: Question = gen.generate(makeWord('w-icecream', 'ice-cream')) as Question;
      expect(q.spellLetters.length).assertEqual(8);
      expect(q.isValid()).assertTrue();
    });
  });
}
