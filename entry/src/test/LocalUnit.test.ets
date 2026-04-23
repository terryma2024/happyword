import { describe, it, expect } from '@ohos/hypium';
import {
  computeRibbonFlyTarget,
  generateRibbons,
  Ribbon,
  RibbonFlyTarget,
  RIBBON_COLORS,
  RIBBON_FLY_RADIUS,
  RIBBON_UPWARD_BIAS
} from '../main/ets/components/GiftBox';
import { WordEntry, CATEGORY_FRUIT, CATEGORY_HOME, CATEGORY_PLACE } from '../main/ets/models/WordEntry';
import { Question } from '../main/ets/models/Question';
import { WordRepository } from '../main/ets/services/WordRepository';
import { shuffle, mulberry32, RandomFn } from '../main/ets/utils/shuffle';
import { QuestionGenerator, OPTIONS_PER_QUESTION } from '../main/ets/services/QuestionGenerator';

function makeWord(id: string, word: string, meaning: string, category: string): WordEntry {
  const e: WordEntry = new WordEntry();
  e.id = id;
  e.word = word;
  e.meaningZh = meaning;
  e.category = category;
  e.difficulty = 1;
  return e;
}

function buildFruitRepo(): WordRepository {
  const repo: WordRepository = new WordRepository();
  const entries: WordEntry[] = [
    makeWord('fruit-apple', 'apple', '苹果', CATEGORY_FRUIT),
    makeWord('fruit-banana', 'banana', '香蕉', CATEGORY_FRUIT),
    makeWord('fruit-orange', 'orange', '橙子', CATEGORY_FRUIT),
    makeWord('fruit-pear', 'pear', '梨', CATEGORY_FRUIT),
    makeWord('fruit-grape', 'grape', '葡萄', CATEGORY_FRUIT)
  ];
  repo.setEntries(entries);
  return repo;
}

export default function localUnitTest() {
  describe('generateRibbons', () => {
    it('returnsRequestedCount', 0, () => {
      const ribbons: Ribbon[] = generateRibbons(10);
      expect(ribbons.length).assertEqual(10);
    });

    it('assignsUniqueIncrementingIds', 0, () => {
      const ribbons: Ribbon[] = generateRibbons(10);
      for (let i = 0; i < ribbons.length; i++) {
        expect(ribbons[i].id).assertEqual(i);
      }
    });

    it('spreadsAnglesAcrossCircle', 0, () => {
      const ribbons: Ribbon[] = generateRibbons(10);
      // Normalize to [0, 360) and check we cover a wide range. ArkTS strict mode
      // disallows Function.apply, so min/max are computed with a plain loop.
      let min: number = 360;
      let max: number = 0;
      for (let i = 0; i < ribbons.length; i++) {
        const a: number = ((ribbons[i].angleDeg % 360) + 360) % 360;
        if (a < min) {
          min = a;
        }
        if (a > max) {
          max = a;
        }
      }
      expect(max - min >= 270).assertTrue();
    });

    it('colorsOnlyFromPalette', 0, () => {
      const ribbons: Ribbon[] = generateRibbons(10);
      for (let i = 0; i < ribbons.length; i++) {
        expect(RIBBON_COLORS.indexOf(ribbons[i].color) >= 0).assertTrue();
      }
    });

    it('isDeterministic', 0, () => {
      const a: Ribbon[] = generateRibbons(10);
      const b: Ribbon[] = generateRibbons(10);
      for (let i = 0; i < a.length; i++) {
        expect(a[i].angleDeg).assertEqual(b[i].angleDeg);
        expect(a[i].color).assertEqual(b[i].color);
      }
    });

    it('handlesZeroCount', 0, () => {
      const ribbons: Ribbon[] = generateRibbons(0);
      expect(ribbons.length).assertEqual(0);
    });
  });

  describe('computeRibbonFlyTarget', () => {
    // Small tolerance for floating-point trig.
    const EPS: number = 1e-6;

    it('appliesUpwardBiasOnHorizontalRightAngle', 0, () => {
      // angle 0° => pure right (cos=1, sin=0). y should be purely the upward
      // bias (negative in screen coords).
      const t: RibbonFlyTarget = computeRibbonFlyTarget(0);
      expect(Math.abs(t.x - RIBBON_FLY_RADIUS) < EPS).assertTrue();
      expect(Math.abs(t.y - (-RIBBON_UPWARD_BIAS)) < EPS).assertTrue();
    });

    it('shiftsDownwardRibbonsUpward', 0, () => {
      // angle 90° => pure "down" in screen coords (sin=1). Without bias y
      // would be +RADIUS; with bias it must be exactly RADIUS - BIAS and
      // strictly smaller than the no-bias value.
      const t: RibbonFlyTarget = computeRibbonFlyTarget(90);
      expect(Math.abs(t.x) < EPS).assertTrue();
      expect(Math.abs(t.y - (RIBBON_FLY_RADIUS - RIBBON_UPWARD_BIAS)) < EPS).assertTrue();
      expect(t.y < RIBBON_FLY_RADIUS).assertTrue();
    });

    it('increasesUpwardReachForUpwardRibbons', 0, () => {
      // angle 270° => pure "up" in screen coords (sin=-1). y should be
      // -RADIUS - BIAS, i.e. further up than the no-bias baseline.
      const t: RibbonFlyTarget = computeRibbonFlyTarget(270);
      expect(Math.abs(t.x) < EPS).assertTrue();
      expect(Math.abs(t.y - (-RIBBON_FLY_RADIUS - RIBBON_UPWARD_BIAS)) < EPS).assertTrue();
      expect(t.y < -RIBBON_FLY_RADIUS).assertTrue();
    });

    it('biasIsUniformAcrossAllAngles', 0, () => {
      // For every angle in generateRibbons, y_actual - sin(angle)*RADIUS
      // should equal exactly -RIBBON_UPWARD_BIAS. This pins the "uniform
      // upward impulse" semantics so future tweaks can't silently change it
      // into an asymmetric remapping.
      const ribbons: Ribbon[] = generateRibbons(10);
      for (let i = 0; i < ribbons.length; i++) {
        const a: number = ribbons[i].angleDeg;
        const t: RibbonFlyTarget = computeRibbonFlyTarget(a);
        const expectedYNoBias: number = Math.sin(a * Math.PI / 180) * RIBBON_FLY_RADIUS;
        expect(Math.abs((t.y - expectedYNoBias) - (-RIBBON_UPWARD_BIAS)) < EPS).assertTrue();
      }
    });

    it('biasIsPositiveAndWeakerThanRadius', 0, () => {
      // Guard against accidental sign flips or overly strong bias that would
      // overpower the radial burst.
      expect(RIBBON_UPWARD_BIAS > 0).assertTrue();
      expect(RIBBON_UPWARD_BIAS < RIBBON_FLY_RADIUS).assertTrue();
    });
  });

  describe('WordEntry', () => {
    it('acceptsValidEntry', 0, () => {
      const e: WordEntry = makeWord('fruit-apple', 'apple', '苹果', CATEGORY_FRUIT);
      expect(e.isValid()).assertTrue();
    });

    it('rejectsEmptyId', 0, () => {
      const e: WordEntry = makeWord('', 'apple', '苹果', CATEGORY_FRUIT);
      expect(e.isValid()).assertFalse();
    });

    it('rejectsEmptyWord', 0, () => {
      const e: WordEntry = makeWord('fruit-apple', '', '苹果', CATEGORY_FRUIT);
      expect(e.isValid()).assertFalse();
    });

    it('rejectsEmptyMeaning', 0, () => {
      const e: WordEntry = makeWord('fruit-apple', 'apple', '', CATEGORY_FRUIT);
      expect(e.isValid()).assertFalse();
    });

    it('rejectsNonPositiveDifficulty', 0, () => {
      const e: WordEntry = makeWord('fruit-apple', 'apple', '苹果', CATEGORY_FRUIT);
      e.difficulty = 0;
      expect(e.isValid()).assertFalse();
    });
  });

  describe('Question', () => {
    it('acceptsThreeUniqueOptionsWithAnswer', 0, () => {
      const q: Question = new Question();
      q.promptZh = '苹果';
      q.answer = 'apple';
      q.options = ['apple', 'banana', 'pear'];
      q.wordId = 'fruit-apple';
      expect(q.isValid()).assertTrue();
    });

    it('rejectsWrongOptionCount', 0, () => {
      const q: Question = new Question();
      q.promptZh = '苹果';
      q.answer = 'apple';
      q.options = ['apple', 'banana'];
      q.wordId = 'fruit-apple';
      expect(q.isValid()).assertFalse();
    });

    it('rejectsMissingAnswer', 0, () => {
      const q: Question = new Question();
      q.promptZh = '苹果';
      q.answer = 'apple';
      q.options = ['banana', 'pear', 'grape'];
      q.wordId = 'fruit-apple';
      expect(q.isValid()).assertFalse();
    });

    it('rejectsDuplicateOptions', 0, () => {
      const q: Question = new Question();
      q.promptZh = '苹果';
      q.answer = 'apple';
      q.options = ['apple', 'apple', 'banana'];
      q.wordId = 'fruit-apple';
      expect(q.isValid()).assertFalse();
    });
  });

  describe('WordRepository.parseWordsJson', () => {
    // ArkTS strict mode forbids inline object literals without a declared type.
    // Using raw JSON string literals keeps the test data ArkTS-compliant and
    // exercises the real `JSON.parse` path inside `parseWordsJson`.
    const sampleJson: string = '{"version":1,"words":['
      + '{"id":"fruit-apple","word":"apple","meaningZh":"苹果","category":"fruit","difficulty":1},'
      + '{"id":"fruit-banana","word":"banana","meaningZh":"香蕉","category":"fruit","difficulty":1},'
      + '{"id":"place-school","word":"school","meaningZh":"学校","category":"place","difficulty":1},'
      + '{"id":"home-bed","word":"bed","meaningZh":"床","category":"home","difficulty":1}'
      + ']}';

    it('parsesAllValidEntries', 0, () => {
      const entries: WordEntry[] = WordRepository.parseWordsJson(sampleJson);
      expect(entries.length).assertEqual(4);
    });

    it('keepsDataFidelityForFirstEntry', 0, () => {
      const entries: WordEntry[] = WordRepository.parseWordsJson(sampleJson);
      expect(entries[0].id).assertEqual('fruit-apple');
      expect(entries[0].word).assertEqual('apple');
      expect(entries[0].meaningZh).assertEqual('苹果');
      expect(entries[0].category).assertEqual(CATEGORY_FRUIT);
      expect(entries[0].difficulty).assertEqual(1);
    });

    it('dropsInvalidEntries', 0, () => {
      const mixed: string = '{"version":1,"words":['
        + '{"id":"fruit-apple","word":"apple","meaningZh":"苹果","category":"fruit","difficulty":1},'
        + '{"id":"","word":"ghost","meaningZh":"幽灵","category":"fruit","difficulty":1},'
        + '{"id":"bad-empty-word","word":"","meaningZh":"x","category":"fruit","difficulty":1},'
        + '{"id":"bad-difficulty","word":"bad","meaningZh":"坏","category":"fruit","difficulty":0}'
        + ']}';
      const entries: WordEntry[] = WordRepository.parseWordsJson(mixed);
      expect(entries.length).assertEqual(1);
      expect(entries[0].id).assertEqual('fruit-apple');
    });

    it('dropsDuplicateIds', 0, () => {
      const dup: string = '{"version":1,"words":['
        + '{"id":"fruit-apple","word":"apple","meaningZh":"苹果","category":"fruit","difficulty":1},'
        + '{"id":"fruit-apple","word":"pomme","meaningZh":"苹果(重复)","category":"fruit","difficulty":1}'
        + ']}';
      const entries: WordEntry[] = WordRepository.parseWordsJson(dup);
      expect(entries.length).assertEqual(1);
      expect(entries[0].word).assertEqual('apple');
    });

    it('returnsEmptyOnMalformedJson', 0, () => {
      const entries: WordEntry[] = WordRepository.parseWordsJson('{not valid json');
      expect(entries.length).assertEqual(0);
    });

    it('returnsEmptyOnEmptyInput', 0, () => {
      expect(WordRepository.parseWordsJson('').length).assertEqual(0);
    });

    it('filtersByCategory', 0, () => {
      const repo: WordRepository = new WordRepository();
      repo.setEntries(WordRepository.parseWordsJson(sampleJson));
      expect(repo.byCategory(CATEGORY_FRUIT).length).assertEqual(2);
      expect(repo.byCategory(CATEGORY_PLACE).length).assertEqual(1);
      expect(repo.byCategory(CATEGORY_HOME).length).assertEqual(1);
    });

    it('findByIdReturnsMatch', 0, () => {
      const repo: WordRepository = new WordRepository();
      repo.setEntries(WordRepository.parseWordsJson(sampleJson));
      const found: WordEntry | undefined = repo.findById('home-bed');
      expect(found !== undefined).assertTrue();
      if (found !== undefined) {
        expect(found.word).assertEqual('bed');
      }
    });

    it('findByIdReturnsUndefinedForMissing', 0, () => {
      const repo: WordRepository = new WordRepository();
      repo.setEntries(WordRepository.parseWordsJson(sampleJson));
      expect(repo.findById('nope') === undefined).assertTrue();
    });
  });

  describe('shuffle', () => {
    it('preservesLengthAndElements', 0, () => {
      const src: number[] = [1, 2, 3, 4, 5, 6, 7, 8];
      const rng: RandomFn = mulberry32(123);
      const out: number[] = shuffle<number>(src, rng);
      expect(out.length).assertEqual(src.length);
      const sum: number = out[0] + out[1] + out[2] + out[3] + out[4] + out[5] + out[6] + out[7];
      expect(sum).assertEqual(1 + 2 + 3 + 4 + 5 + 6 + 7 + 8);
    });

    it('doesNotMutateInput', 0, () => {
      const src: number[] = [1, 2, 3, 4, 5];
      const snapshot: number[] = src.slice();
      const rng: RandomFn = mulberry32(42);
      shuffle<number>(src, rng);
      for (let i = 0; i < snapshot.length; i++) {
        expect(src[i]).assertEqual(snapshot[i]);
      }
    });

    it('isDeterministicWithSameSeed', 0, () => {
      const src: number[] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
      const a: number[] = shuffle<number>(src, mulberry32(99));
      const b: number[] = shuffle<number>(src, mulberry32(99));
      for (let i = 0; i < a.length; i++) {
        expect(a[i]).assertEqual(b[i]);
      }
    });

    it('producesDifferentOrderForDifferentSeeds', 0, () => {
      const src: number[] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
      const a: number[] = shuffle<number>(src, mulberry32(1));
      const b: number[] = shuffle<number>(src, mulberry32(2));
      let anyDifference: boolean = false;
      for (let i = 0; i < a.length; i++) {
        if (a[i] !== b[i]) {
          anyDifference = true;
          break;
        }
      }
      expect(anyDifference).assertTrue();
    });

    it('handlesEmptyArray', 0, () => {
      const out: string[] = shuffle<string>([], mulberry32(1));
      expect(out.length).assertEqual(0);
    });
  });

  describe('QuestionGenerator', () => {
    it('producesExactlyThreeUniqueOptionsIncludingAnswer', 0, () => {
      const repo: WordRepository = buildFruitRepo();
      const gen: QuestionGenerator = new QuestionGenerator(repo, mulberry32(7));
      const q: Question = gen.nextQuestion();
      expect(q.isValid()).assertTrue();
      expect(q.options.length).assertEqual(OPTIONS_PER_QUESTION);
      expect(q.options.indexOf(q.answer) >= 0).assertTrue();
      const unique: Set<string> = new Set<string>();
      for (let i = 0; i < q.options.length; i++) {
        unique.add(q.options[i]);
      }
      expect(unique.size).assertEqual(OPTIONS_PER_QUESTION);
    });

    it('promptUsesMeaningZhOfAnswerWord', 0, () => {
      const repo: WordRepository = buildFruitRepo();
      const gen: QuestionGenerator = new QuestionGenerator(repo, mulberry32(11));
      const q: Question = gen.nextQuestion();
      const word: WordEntry | undefined = repo.findById(q.wordId);
      expect(word !== undefined).assertTrue();
      if (word !== undefined) {
        expect(q.promptZh).assertEqual(word.meaningZh);
        expect(q.answer).assertEqual(word.word);
      }
    });

    it('doesNotRepeatSameWordWhenLastWordIdProvided', 0, () => {
      const repo: WordRepository = buildFruitRepo();
      const gen: QuestionGenerator = new QuestionGenerator(repo, mulberry32(3));
      // Sweep many seeds to make sure no run slips through with lastWordId honored.
      for (let seed = 0; seed < 25; seed++) {
        const localGen: QuestionGenerator = new QuestionGenerator(repo, mulberry32(seed));
        const first: Question = localGen.nextQuestion();
        const second: Question = localGen.nextQuestion(first.wordId);
        expect(second.wordId === first.wordId).assertFalse();
      }
    });

    it('degradesToGlobalWhenCategoryPoolIsTooSmall', 0, () => {
      // Tiny fruit pool (1 fruit) forces the generator to borrow distractors
      // from other categories (spec §5.2 global fallback).
      const repo: WordRepository = new WordRepository();
      repo.setEntries([
        makeWord('fruit-apple', 'apple', '苹果', CATEGORY_FRUIT),
        makeWord('home-bed', 'bed', '床', CATEGORY_HOME),
        makeWord('place-zoo', 'zoo', '动物园', CATEGORY_PLACE)
      ]);

      const gen: QuestionGenerator = new QuestionGenerator(repo, mulberry32(5));
      // Force the answer to be the fruit by picking a seed where the first
      // choice is apple; if not, re-seed until it is. This keeps the test
      // focused on the fallback path.
      let q: Question = gen.nextQuestion();
      let seed: number = 5;
      while (q.wordId !== 'fruit-apple' && seed < 200) {
        seed++;
        const g: QuestionGenerator = new QuestionGenerator(repo, mulberry32(seed));
        q = g.nextQuestion();
      }
      expect(q.wordId).assertEqual('fruit-apple');
      expect(q.isValid()).assertTrue();
      expect(q.options.length).assertEqual(OPTIONS_PER_QUESTION);
      expect(q.options.indexOf('apple') >= 0).assertTrue();
      expect(q.options.indexOf('bed') >= 0 || q.options.indexOf('zoo') >= 0).assertTrue();
    });

    it('works_whenRepoHasExactlyThreeWords', 0, () => {
      const repo: WordRepository = new WordRepository();
      repo.setEntries([
        makeWord('fruit-apple', 'apple', '苹果', CATEGORY_FRUIT),
        makeWord('fruit-banana', 'banana', '香蕉', CATEGORY_FRUIT),
        makeWord('fruit-pear', 'pear', '梨', CATEGORY_FRUIT)
      ]);
      const gen: QuestionGenerator = new QuestionGenerator(repo, mulberry32(1));
      const q: Question = gen.nextQuestion();
      expect(q.isValid()).assertTrue();
      expect(q.options.length).assertEqual(3);
    });

    it('throws_whenRepoHasTooFewWords', 0, () => {
      const repo: WordRepository = new WordRepository();
      repo.setEntries([
        makeWord('fruit-apple', 'apple', '苹果', CATEGORY_FRUIT),
        makeWord('fruit-banana', 'banana', '香蕉', CATEGORY_FRUIT)
      ]);
      const gen: QuestionGenerator = new QuestionGenerator(repo, mulberry32(1));
      let threw: boolean = false;
      try {
        gen.nextQuestion();
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();
    });

    it('manyIterations_preserveInvariants', 0, () => {
      // Run a longer loop to catch any stray invalid question under randomness.
      const repo: WordRepository = buildFruitRepo();
      const gen: QuestionGenerator = new QuestionGenerator(repo, mulberry32(2026));
      let lastWordId: string | undefined = undefined;
      for (let i = 0; i < 50; i++) {
        const q: Question = gen.nextQuestion(lastWordId);
        expect(q.isValid()).assertTrue();
        expect(q.options.length).assertEqual(OPTIONS_PER_QUESTION);
        expect(q.options.indexOf(q.answer) >= 0).assertTrue();
        if (lastWordId !== undefined) {
          expect(q.wordId === lastWordId).assertFalse();
        }
        lastWordId = q.wordId;
      }
    });
  });
}
