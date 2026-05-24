import { describe, it, expect } from '@ohos/hypium';
import { ExampleSentence, WordEntry } from '../main/ets/models/WordEntry';
import { Question, QuestionKind } from '../main/ets/models/Question';
import { WordRepository } from '../main/ets/services/WordRepository';
import {
  findSentenceClozeTargetSpan,
  SentenceClozeGenerator,
  wordSupportsSentenceCloze,
} from '../main/ets/services/SentenceClozeGenerator';
import { mulberry32 } from '../main/ets/utils/shuffle';

function makeWord(id: string, word: string, exampleEn: string = '', exampleZh: string = ''): WordEntry {
  const w: WordEntry = new WordEntry();
  w.id = id;
  w.word = word;
  w.meaningZh = word;
  w.category = 'test';
  w.difficulty = 1;
  if (exampleEn.length > 0 || exampleZh.length > 0) {
    const ex: ExampleSentence = new ExampleSentence();
    ex.en = exampleEn;
    ex.zh = exampleZh;
    w.example = ex;
  }
  return w;
}

function makeRepo(entries: WordEntry[]): WordRepository {
  const repo: WordRepository = new WordRepository();
  repo.setEntries(entries);
  return repo;
}

export default function sentenceClozeGeneratorTest() {
  describe('SentenceClozeGenerator', () => {
    it('matchesWholeWordAndBuildsClozePrompt', 0, () => {
      const apple: WordEntry = makeWord('fruit-apple', 'apple', 'I eat an apple.', '我吃一个苹果。');
      const repo: WordRepository = makeRepo([
        apple,
        makeWord('fruit-banana', 'banana'),
        makeWord('fruit-orange', 'orange'),
      ]);
      const q: Question | undefined = new SentenceClozeGenerator(mulberry32(1)).generate(apple, repo);
      expect(q !== undefined).assertTrue();
      const qq: Question = q as Question;
      expect(qq.kind).assertEqual(QuestionKind.SentenceCloze);
      expect(qq.sentenceTemplate).assertEqual('I eat an ____.');
      expect(qq.sentenceZh).assertEqual('我吃一个苹果。');
      expect(qq.options.indexOf('apple') >= 0).assertTrue();
      expect(qq.options.length).assertEqual(3);
      expect(qq.isValid()).assertTrue();
    });

    it('rejectsPartialSubstringMatches', 0, () => {
      const span = findSentenceClozeTargetSpan('A caterpillar is small.', 'cat');
      expect(span === undefined).assertTrue();
      expect(wordSupportsSentenceCloze(makeWord('animal-cat', 'cat', 'A caterpillar is small.', '毛毛虫很小。')))
        .assertFalse();
    });

    it('matchesPhrasesAsContiguousTargets', 0, () => {
      const wand: WordEntry = makeWord('magic-wand', 'magic wand', 'I hold a magic wand.', '我拿着一根魔法棒。');
      const repo: WordRepository = makeRepo([
        wand,
        makeWord('fruit-apple', 'apple'),
        makeWord('fruit-banana', 'banana'),
      ]);
      const q: Question | undefined = new SentenceClozeGenerator(mulberry32(2)).generate(wand, repo);
      expect(q !== undefined).assertTrue();
      expect((q as Question).sentenceTemplate).assertEqual('I hold a ____.');
      expect(wordSupportsSentenceCloze(makeWord('bad-wand', 'magic wand', 'This magic is bright.', '这个魔法很亮。')))
        .assertFalse();
    });

    it('replacesOnlyTheFirstValidMatch', 0, () => {
      const apple: WordEntry = makeWord('fruit-apple', 'apple', 'Apple pie has apple slices.', '苹果派里有苹果片。');
      const repo: WordRepository = makeRepo([
        apple,
        makeWord('fruit-banana', 'banana'),
        makeWord('fruit-orange', 'orange'),
      ]);
      const q: Question | undefined = new SentenceClozeGenerator(mulberry32(3)).generate(apple, repo);
      expect(q !== undefined).assertTrue();
      expect((q as Question).sentenceTemplate).assertEqual('____ pie has apple slices.');
    });

    it('usesCaseInsensitiveUniqueDistractorsThenRepoFallback', 0, () => {
      const apple: WordEntry = makeWord('fruit-apple', 'apple', 'I eat an apple.', '我吃一个苹果。');
      apple.distractors = ['Apple', 'banana'];
      const repo: WordRepository = makeRepo([
        apple,
        makeWord('fruit-orange', 'orange'),
        makeWord('fruit-grape', 'grape'),
      ]);
      const q: Question | undefined = new SentenceClozeGenerator(mulberry32(4)).generate(apple, repo);
      expect(q !== undefined).assertTrue();
      const qq: Question = q as Question;
      expect(qq.options.length).assertEqual(3);
      expect(qq.options.indexOf('apple') >= 0).assertTrue();
      expect(qq.options.indexOf('banana') >= 0).assertTrue();
      expect(qq.options.indexOf('orange') >= 0 || qq.options.indexOf('grape') >= 0).assertTrue();
    });
  });
}
