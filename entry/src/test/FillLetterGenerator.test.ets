import { describe, it, expect } from '@ohos/hypium';
import { WordEntry } from '../main/ets/models/WordEntry';
import { Question, QuestionKind } from '../main/ets/models/Question';
import { FillLetterGenerator } from '../main/ets/services/FillLetterGenerator';
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

export default function fillLetterGeneratorTest() {
  describe('FillLetterGenerator', () => {
    it('producesWellFormedFillLetterQuestion', 0, () => {
      const gen: FillLetterGenerator = new FillLetterGenerator(mulberry32(1));
      const q: Question | undefined = gen.generate(makeWord('fruit-apple', 'apple'));
      expect(q !== undefined).assertTrue();
      const qq: Question = q as Question;
      expect(qq.kind).assertEqual(QuestionKind.FillLetter);
      expect(qq.answer).assertEqual('apple');
      expect(qq.letterOptions.length).assertEqual(3);
      expect(qq.letterOptions.indexOf(qq.letterAnswer) >= 0).assertTrue();
      expect(qq.isValid()).assertTrue();
    });

    it('isDeterministicGivenSameSeed', 0, () => {
      const a: Question = new FillLetterGenerator(mulberry32(42))
        .generate(makeWord('fruit-banana', 'banana')) as Question;
      const b: Question = new FillLetterGenerator(mulberry32(42))
        .generate(makeWord('fruit-banana', 'banana')) as Question;
      expect(a.letterTemplate).assertEqual(b.letterTemplate);
      expect(a.missingIndex).assertEqual(b.missingIndex);
      expect(a.letterAnswer).assertEqual(b.letterAnswer);
      expect(a.letterOptions[0]).assertEqual(b.letterOptions[0]);
      expect(a.letterOptions[1]).assertEqual(b.letterOptions[1]);
      expect(a.letterOptions[2]).assertEqual(b.letterOptions[2]);
    });

    it('avoidsHidingTheFirstLetter', 0, () => {
      const gen: FillLetterGenerator = new FillLetterGenerator(mulberry32(2));
      for (let i = 0; i < 20; i++) {
        const q: Question = gen.generate(makeWord(`w-${i}`, 'orange')) as Question;
        expect(q.missingIndex >= 1).assertTrue();
      }
    });

    it('returnsUndefinedForWordsShorterThanThreeLetters', 0, () => {
      const gen: FillLetterGenerator = new FillLetterGenerator(mulberry32(3));
      expect(gen.generate(makeWord('home-tv', 'TV')) === undefined).assertTrue();
    });

    it('distractorLettersDoNotAppearElsewhereInTheWord', 0, () => {
      const gen: FillLetterGenerator = new FillLetterGenerator(mulberry32(4));
      const q: Question = gen.generate(makeWord('fruit-apple', 'apple')) as Question;
      const lettersInWord: Set<string> = new Set<string>();
      const word: string = 'apple';
      for (let i = 0; i < word.length; i++) {
        lettersInWord.add(word.charAt(i));
      }
      for (let i = 0; i < q.letterOptions.length; i++) {
        const c: string = q.letterOptions[i];
        if (c === q.letterAnswer) {
          continue;
        }
        expect(lettersInWord.has(c)).assertFalse();
      }
    });

    it('letterTemplateUsesUnderscoreAtMissingIndex', 0, () => {
      const gen: FillLetterGenerator = new FillLetterGenerator(mulberry32(5));
      const q: Question = gen.generate(makeWord('fruit-pear', 'pear')) as Question;
      const tokens: string[] = q.letterTemplate.split(' ');
      expect(tokens.length).assertEqual('pear'.length);
      expect(tokens[q.missingIndex]).assertEqual('_');
    });
  });
}
