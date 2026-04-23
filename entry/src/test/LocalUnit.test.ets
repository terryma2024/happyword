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
import {
  BattleEngine,
  BattleConfig,
  AnswerOutcome,
  TickOutcome,
  DEFAULT_PLAYER_HP,
  DEFAULT_MONSTER_HP,
  DEFAULT_MONSTERS_TOTAL,
  DEFAULT_STARTING_SECONDS
} from '../main/ets/services/BattleEngine';
import { BattleState, BattleStatus } from '../main/ets/models/BattleState';
import { SessionResult } from '../main/ets/models/SessionResult';
import {
  GameConfig,
  TIMER_CHOICES,
  HP_MIN,
  HP_MAX,
  MONSTER_COUNT_MIN,
  MONSTER_COUNT_MAX,
  KNOWN_CATEGORIES,
  CUSTOM_CATEGORY_KEY,
  MIN_POOL_SIZE,
  cloneGameConfig,
  parseCustomWords,
  computeFinalPool
} from '../main/ets/models/GameConfig';
import {
  AudioService,
  ALL_SOUND_KEYS,
  SoundKeys
} from '../main/ets/services/AudioService';

function makeWord(id: string, word: string, meaning: string, category: string): WordEntry {
  const e: WordEntry = new WordEntry();
  e.id = id;
  e.word = word;
  e.meaningZh = meaning;
  e.category = category;
  e.difficulty = 1;
  return e;
}

/** For GameConfig.computeFinalPool tests: meaningZh mirrors English word. */
function makeEntry(id: string, word: string, category: string): WordEntry {
  const e: WordEntry = new WordEntry();
  e.id = id;
  e.word = word;
  e.meaningZh = word;
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

/**
 * Build a BattleEngine over the fruit repo with deterministic RNG so the
 * BattleEngine tests can reason about a reproducible question sequence.
 * Declared at module scope because ArkTS strict mode does not permit
 * nested function declarations inside `describe`/`it` callbacks.
 */
function engineWithFruit(seed: number, config?: BattleConfig): BattleEngine {
  const repo: WordRepository = buildFruitRepo();
  const gen: QuestionGenerator = new QuestionGenerator(repo, mulberry32(seed));
  const engine: BattleEngine = new BattleEngine(gen, config);
  engine.start();
  return engine;
}

/** Pick any option from `q` that is not the correct answer. */
function pickWrongOption(q: Question): string {
  for (let i = 0; i < q.options.length; i++) {
    if (q.options[i] !== q.answer) {
      return q.options[i];
    }
  }
  return '';
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

  describe('BattleEngine', () => {
    /**
     * T6 unit tests for the pure battle-rules layer (spec §4.1–§4.3, §8.3).
     *
     * These tests fix BattleEngine behaviour independently from the UI so
     * regressions show up as LocalUnit failures rather than as visual bugs
     * that only surface on the emulator. Each test constructs its own
     * QuestionGenerator with a deterministic Mulberry32 seed so the
     * sequence of questions is reproducible across runs.
     *
     * T6 deliberately uses constant 1-damage-per-hit. The 3-combo 2× damage
     * bonus and its visual feedback land in T7 and are covered by separate
     * tests added at that time; here we only assert that comboCount is
     * tracked and resets correctly.
     */

    it('startInitializesPlayingStateWithDefaults', 0, () => {
      const engine: BattleEngine = engineWithFruit(1);
      const state: BattleState = engine.getState();
      expect(state.status).assertEqual(BattleStatus.Playing);
      expect(state.playerHp).assertEqual(DEFAULT_PLAYER_HP);
      expect(state.playerMaxHp).assertEqual(DEFAULT_PLAYER_HP);
      expect(state.monsterHp).assertEqual(DEFAULT_MONSTER_HP);
      expect(state.monsterMaxHp).assertEqual(DEFAULT_MONSTER_HP);
      expect(state.monsterIndex).assertEqual(1);
      expect(state.monstersTotal).assertEqual(DEFAULT_MONSTERS_TOTAL);
      expect(state.comboCount).assertEqual(0);
      expect(state.totalAnswers).assertEqual(0);
      expect(state.correctAnswers).assertEqual(0);
      expect(state.defeatedMonsters).assertEqual(0);
      expect(state.currentQuestion !== undefined).assertTrue();
    });

    it('startHonorsCustomConfig', 0, () => {
      const cfg: BattleConfig = new BattleConfig();
      cfg.playerMaxHp = 2;
      cfg.monsterMaxHp = 1;
      cfg.monstersTotal = 3;
      const engine: BattleEngine = engineWithFruit(1, cfg);
      const state: BattleState = engine.getState();
      expect(state.playerHp).assertEqual(2);
      expect(state.playerMaxHp).assertEqual(2);
      expect(state.monsterHp).assertEqual(1);
      expect(state.monsterMaxHp).assertEqual(1);
      expect(state.monstersTotal).assertEqual(3);
    });

    it('submitCorrectAnswerDealsOneDamageAndIncrementsCombo', 0, () => {
      const engine: BattleEngine = engineWithFruit(1);
      const state0: BattleState = engine.getState();
      const firstQuestion: Question = state0.currentQuestion!;
      const outcome: AnswerOutcome = engine.submitAnswer(firstQuestion.answer);
      const state1: BattleState = engine.getState();

      expect(outcome.correct).assertTrue();
      expect(outcome.damage).assertEqual(1);
      expect(outcome.monsterDefeated).assertFalse();
      expect(outcome.battleEnded).assertFalse();

      expect(state1.monsterHp).assertEqual(DEFAULT_MONSTER_HP - 1);
      expect(state1.playerHp).assertEqual(DEFAULT_PLAYER_HP);
      expect(state1.comboCount).assertEqual(1);
      expect(state1.totalAnswers).assertEqual(1);
      expect(state1.correctAnswers).assertEqual(1);
      expect(state1.status).assertEqual(BattleStatus.Playing);
      // A new question has been spawned and it is a different word.
      expect(state1.currentQuestion !== undefined).assertTrue();
      expect(state1.currentQuestion!.wordId === firstQuestion.wordId).assertFalse();
    });

    it('submitWrongAnswerHurtsPlayerAndResetsCombo', 0, () => {
      const engine: BattleEngine = engineWithFruit(1);
      const q0: Question = engine.getState().currentQuestion!;

      // Prime a combo first so the reset is observable.
      engine.submitAnswer(q0.answer);
      expect(engine.getState().comboCount).assertEqual(1);

      const q1: Question = engine.getState().currentQuestion!;
      const wrong1: string = pickWrongOption(q1);
      expect(wrong1.length > 0).assertTrue();
      const outcome: AnswerOutcome = engine.submitAnswer(wrong1);
      const state: BattleState = engine.getState();

      expect(outcome.correct).assertFalse();
      expect(outcome.damage).assertEqual(1);
      expect(outcome.battleEnded).assertFalse();

      expect(state.monsterHp).assertEqual(DEFAULT_MONSTER_HP - 1); // only from the earlier correct hit
      expect(state.playerHp).assertEqual(DEFAULT_PLAYER_HP - 1);
      expect(state.comboCount).assertEqual(0);
      expect(state.totalAnswers).assertEqual(2);
      expect(state.correctAnswers).assertEqual(1);
      expect(state.status).assertEqual(BattleStatus.Playing);
    });

    it('monsterDefeatedSpawnsNextMonsterAndPreservesCombo', 0, () => {
      // monsterMaxHp = 1 so a single correct answer drops the monster.
      const cfg: BattleConfig = new BattleConfig();
      cfg.monsterMaxHp = 1;
      cfg.monstersTotal = 3;
      const engine: BattleEngine = engineWithFruit(1, cfg);

      const q: Question = engine.getState().currentQuestion!;
      const outcome: AnswerOutcome = engine.submitAnswer(q.answer);
      const state: BattleState = engine.getState();

      expect(outcome.correct).assertTrue();
      expect(outcome.monsterDefeated).assertTrue();
      expect(outcome.newMonsterSpawned).assertTrue();
      expect(outcome.battleEnded).assertFalse();

      expect(state.defeatedMonsters).assertEqual(1);
      expect(state.monsterIndex).assertEqual(2);
      // Next monster spawns at full HP — spec §4.1 treats each monster
      // independently so the next slime is fresh.
      expect(state.monsterHp).assertEqual(1);
      expect(state.monsterMaxHp).assertEqual(1);
      // Combo survives a monster kill — only wrong answers reset combo.
      expect(state.comboCount).assertEqual(1);
      expect(state.status).assertEqual(BattleStatus.Playing);
    });

    it('defeatingFinalMonsterTransitionsToWon', 0, () => {
      const cfg: BattleConfig = new BattleConfig();
      cfg.monsterMaxHp = 1;
      cfg.monstersTotal = 2;
      const engine: BattleEngine = engineWithFruit(1, cfg);

      // Two correct answers defeat both monsters.
      const outcome1: AnswerOutcome = engine.submitAnswer(engine.getState().currentQuestion!.answer);
      expect(outcome1.battleEnded).assertFalse();
      const outcome2: AnswerOutcome = engine.submitAnswer(engine.getState().currentQuestion!.answer);
      const state: BattleState = engine.getState();

      expect(outcome2.monsterDefeated).assertTrue();
      expect(outcome2.newMonsterSpawned).assertFalse();
      expect(outcome2.battleEnded).assertTrue();
      expect(outcome2.endStatus).assertEqual(BattleStatus.Won);

      expect(state.defeatedMonsters).assertEqual(2);
      expect(state.status).assertEqual(BattleStatus.Won);
      // After a final win, currentQuestion is cleared so the UI knows not to
      // keep rendering a stale prompt.
      expect(state.currentQuestion === undefined).assertTrue();
    });

    it('drainingPlayerHpTransitionsToLost', 0, () => {
      const cfg: BattleConfig = new BattleConfig();
      cfg.playerMaxHp = 2;
      cfg.monsterMaxHp = 10; // keep the monster alive so the player dies first
      const engine: BattleEngine = engineWithFruit(1, cfg);

      engine.submitAnswer(pickWrongOption(engine.getState().currentQuestion!));
      expect(engine.getState().playerHp).assertEqual(1);
      expect(engine.getState().status).assertEqual(BattleStatus.Playing);

      const outcome: AnswerOutcome = engine.submitAnswer(pickWrongOption(engine.getState().currentQuestion!));
      const state: BattleState = engine.getState();

      expect(outcome.correct).assertFalse();
      expect(outcome.battleEnded).assertTrue();
      expect(outcome.endStatus).assertEqual(BattleStatus.Lost);
      expect(state.playerHp).assertEqual(0);
      expect(state.status).assertEqual(BattleStatus.Lost);
      expect(state.currentQuestion === undefined).assertTrue();
    });

    it('rejectsUnknownOption', 0, () => {
      const engine: BattleEngine = engineWithFruit(1);
      let threw: boolean = false;
      try {
        engine.submitAnswer('not-a-real-option');
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();
      // State must not change on an invalid input.
      const state: BattleState = engine.getState();
      expect(state.totalAnswers).assertEqual(0);
      expect(state.playerHp).assertEqual(DEFAULT_PLAYER_HP);
      expect(state.monsterHp).assertEqual(DEFAULT_MONSTER_HP);
    });

    it('rejectsSubmitAfterBattleEnded', 0, () => {
      const cfg: BattleConfig = new BattleConfig();
      cfg.monsterMaxHp = 1;
      cfg.monstersTotal = 1;
      const engine: BattleEngine = engineWithFruit(1, cfg);
      engine.submitAnswer(engine.getState().currentQuestion!.answer);
      expect(engine.getState().status).assertEqual(BattleStatus.Won);

      let threw: boolean = false;
      try {
        engine.submitAnswer('anything');
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();
    });

    it('comboIncrementsOnStreakAndResetsOnWrong', 0, () => {
      // T7 changes the combo semantics: the 3rd consecutive correct deals
      // 2 damage and immediately resets the counter to 0. The counter
      // therefore walks 1 -> 2 -> 0, not 1 -> 2 -> 3. See dedicated T7
      // tests below for the trigger behaviour; this test only confirms
      // that a non-triggering wrong answer resets a short streak.
      const engine: BattleEngine = engineWithFruit(1);
      const firstOutcome: AnswerOutcome = engine.submitAnswer(engine.getState().currentQuestion!.answer);
      expect(firstOutcome.damage).assertEqual(1);
      expect(firstOutcome.comboTriggered).assertFalse();
      expect(engine.getState().comboCount).assertEqual(1);

      engine.submitAnswer(engine.getState().currentQuestion!.answer);
      expect(engine.getState().comboCount).assertEqual(2);

      // Wrong answer with combo = 2 resets the counter without triggering.
      const wrongOutcome: AnswerOutcome = engine.submitAnswer(pickWrongOption(engine.getState().currentQuestion!));
      expect(wrongOutcome.comboTriggered).assertFalse();
      expect(engine.getState().comboCount).assertEqual(0);
      expect(engine.getState().correctAnswers).assertEqual(2);
      expect(engine.getState().totalAnswers).assertEqual(3);
    });

    it('thirdConsecutiveCorrectTriggersComboBurst', 0, () => {
      // Spec §4.3: 每次答对后 comboCount 加 1；当 comboCount 达到 3 时，
      // 本次伤害为 2，触发魔法爆发反馈，并将 comboCount 重置为 0.
      //
      // Use a high-HP monster so the 2× damage on the 3rd correct can't
      // overlap with a monster-defeat transition — this test isolates the
      // combo-burst rule from the defeat cascade.
      const cfg: BattleConfig = new BattleConfig();
      cfg.monsterMaxHp = 10;
      const engine: BattleEngine = engineWithFruit(1, cfg);

      const o1: AnswerOutcome = engine.submitAnswer(engine.getState().currentQuestion!.answer);
      expect(o1.damage).assertEqual(1);
      expect(o1.comboTriggered).assertFalse();
      expect(engine.getState().comboCount).assertEqual(1);

      const o2: AnswerOutcome = engine.submitAnswer(engine.getState().currentQuestion!.answer);
      expect(o2.damage).assertEqual(1);
      expect(o2.comboTriggered).assertFalse();
      expect(engine.getState().comboCount).assertEqual(2);

      const o3: AnswerOutcome = engine.submitAnswer(engine.getState().currentQuestion!.answer);
      expect(o3.damage).assertEqual(2);
      expect(o3.comboTriggered).assertTrue();
      // Counter resets the moment the burst fires, per spec.
      expect(engine.getState().comboCount).assertEqual(0);
      // Total monster damage so far: 1 + 1 + 2 = 4.
      expect(engine.getState().monsterHp).assertEqual(10 - 4);
    });

    it('fourthCorrectAfterBurstIsNormalDamage', 0, () => {
      // After the burst resets the counter, the next correct answer must
      // start a fresh streak at damage 1, not continue doubling.
      const cfg: BattleConfig = new BattleConfig();
      cfg.monsterMaxHp = 20;
      const engine: BattleEngine = engineWithFruit(1, cfg);

      engine.submitAnswer(engine.getState().currentQuestion!.answer);
      engine.submitAnswer(engine.getState().currentQuestion!.answer);
      engine.submitAnswer(engine.getState().currentQuestion!.answer); // burst

      const o4: AnswerOutcome = engine.submitAnswer(engine.getState().currentQuestion!.answer);
      expect(o4.damage).assertEqual(1);
      expect(o4.comboTriggered).assertFalse();
      expect(engine.getState().comboCount).assertEqual(1);
    });

    it('comboBurstSurvivesMonsterKill', 0, () => {
      // If the 3rd-correct burst also kills the current monster, the
      // combo counter must still reset (spec wording is about the burst
      // firing, independent of which monster is on screen).
      const cfg: BattleConfig = new BattleConfig();
      cfg.monsterMaxHp = 4; // 1 + 1 + 2 = 4 damage defeats exactly.
      cfg.monstersTotal = 3;
      const engine: BattleEngine = engineWithFruit(1, cfg);

      engine.submitAnswer(engine.getState().currentQuestion!.answer);
      engine.submitAnswer(engine.getState().currentQuestion!.answer);
      const o3: AnswerOutcome = engine.submitAnswer(engine.getState().currentQuestion!.answer);

      expect(o3.comboTriggered).assertTrue();
      expect(o3.damage).assertEqual(2);
      expect(o3.monsterDefeated).assertTrue();
      expect(o3.newMonsterSpawned).assertTrue();
      expect(engine.getState().comboCount).assertEqual(0);
      expect(engine.getState().defeatedMonsters).assertEqual(1);
      expect(engine.getState().monsterIndex).assertEqual(2);
    });

    it('wrongAnswerNeverTriggersCombo', 0, () => {
      const engine: BattleEngine = engineWithFruit(1);
      const outcome: AnswerOutcome = engine.submitAnswer(pickWrongOption(engine.getState().currentQuestion!));
      expect(outcome.correct).assertFalse();
      expect(outcome.comboTriggered).assertFalse();
      expect(outcome.damage).assertEqual(1);
    });
  });

  describe('BattleEngine.learnedWords', () => {
    it('tracksEachUniqueWordShown', 0, () => {
      const engine: BattleEngine = engineWithFruit(1);
      // The first question is spawned by start(); subsequent ones by
      // submitAnswer. QuestionGenerator's avoid-same-word rule only
      // looks one step back, so with a 5-word repo we may see repeats
      // across 4 questions. What MUST hold is: learnedWordIds grows
      // monotonically and contains no duplicates.
      const initialLearned: number = engine.getState().learnedWordIds.length;
      expect(initialLearned).assertEqual(1);

      engine.submitAnswer(engine.getState().currentQuestion!.answer);
      engine.submitAnswer(pickWrongOption(engine.getState().currentQuestion!));
      engine.submitAnswer(engine.getState().currentQuestion!.answer);

      const learned: string[] = engine.getState().learnedWordIds;
      // Four questions have been posed; we saw at least two distinct
      // words and at most four.
      expect(learned.length >= 2).assertTrue();
      expect(learned.length <= 4).assertTrue();
      // The list must contain no duplicates (it's conceptually a Set).
      const seen: Map<string, boolean> = new Map<string, boolean>();
      for (let i = 0; i < learned.length; i++) {
        expect(seen.has(learned[i])).assertFalse();
        seen.set(learned[i], true);
      }
    });
  });

  describe('BattleEngine.tick', () => {
    it('decrementsRemainingSecondsWhilePlaying', 0, () => {
      const engine: BattleEngine = engineWithFruit(1);
      const startSeconds: number = engine.getState().remainingSeconds;
      const outcome: TickOutcome = engine.tick(1);
      expect(outcome.battleEnded).assertFalse();
      expect(engine.getState().remainingSeconds).assertEqual(startSeconds - 1);
    });

    it('clampsRemainingSecondsAtZeroAndEndsBattleAsLost', 0, () => {
      const cfg: BattleConfig = new BattleConfig();
      cfg.startingSeconds = 5;
      const engine: BattleEngine = engineWithFruit(1, cfg);
      // Tick past zero; the engine must clamp and transition to Lost.
      const outcome: TickOutcome = engine.tick(10);
      expect(outcome.battleEnded).assertTrue();
      expect(outcome.endStatus).assertEqual(BattleStatus.Lost);
      expect(engine.getState().remainingSeconds).assertEqual(0);
      expect(engine.getState().status).assertEqual(BattleStatus.Lost);
    });

    it('isNoOpAfterBattleEnded', 0, () => {
      const cfg: BattleConfig = new BattleConfig();
      cfg.startingSeconds = 5;
      const engine: BattleEngine = engineWithFruit(1, cfg);
      engine.tick(10); // Lost
      const before: number = engine.getState().remainingSeconds;
      const outcome: TickOutcome = engine.tick(5);
      // Post-end ticks do nothing — they don't change seconds and don't
      // re-fire the battleEnded signal (BattlePage only navigates on the
      // *first* end signal).
      expect(outcome.battleEnded).assertFalse();
      expect(engine.getState().remainingSeconds).assertEqual(before);
    });

    it('rejectsSubmitAnswerAfterTimeExpires', 0, () => {
      const cfg: BattleConfig = new BattleConfig();
      cfg.startingSeconds = 1;
      const engine: BattleEngine = engineWithFruit(1, cfg);
      engine.tick(1);
      let threw: boolean = false;
      try {
        engine.submitAnswer(engine.getState().currentQuestion !== undefined
          ? engine.getState().currentQuestion!.options[0]
          : 'anything');
      } catch (_e) {
        threw = true;
      }
      expect(threw).assertTrue();
    });
  });

  describe('BattleEngine.buildSessionResult', () => {
    it('throwsWhileBattleStillInProgress', 0, () => {
      const engine: BattleEngine = engineWithFruit(1);
      let threw: boolean = false;
      try {
        engine.buildSessionResult();
      } catch (_e) {
        threw = true;
      }
      expect(threw).assertTrue();
    });

    it('wonWithPerfectAccuracyYieldsThreeStars', 0, () => {
      // Small fight: 2 monsters, 1 HP each, so we can win with 2 corrects.
      const cfg: BattleConfig = new BattleConfig();
      cfg.monsterMaxHp = 1;
      cfg.monstersTotal = 2;
      const engine: BattleEngine = engineWithFruit(1, cfg);
      engine.submitAnswer(engine.getState().currentQuestion!.answer);
      engine.submitAnswer(engine.getState().currentQuestion!.answer);

      expect(engine.getState().status).assertEqual(BattleStatus.Won);
      const result: SessionResult = engine.buildSessionResult();
      expect(result.status).assertEqual(BattleStatus.Won);
      expect(result.defeatedMonsters).assertEqual(2);
      expect(result.totalAnswers).assertEqual(2);
      expect(result.correctAnswers).assertEqual(2);
      expect(result.correctRate).assertEqual(1);
      expect(result.stars).assertEqual(3);
    });

    it('wonWithLowAccuracyYieldsTwoStars', 0, () => {
      // Win with accuracy < 80%. Use 1-HP monsters so each correct kills
      // one, and sprinkle enough wrongs to drag accuracy below 0.8 without
      // losing the battle (need player HP > 0 at end).
      const cfg: BattleConfig = new BattleConfig();
      cfg.monsterMaxHp = 1;
      cfg.monstersTotal = 2;
      cfg.playerMaxHp = 5;
      const engine: BattleEngine = engineWithFruit(1, cfg);
      // 2 wrongs + 2 corrects = 50% accuracy, player HP 3/5 at end.
      engine.submitAnswer(pickWrongOption(engine.getState().currentQuestion!));
      engine.submitAnswer(pickWrongOption(engine.getState().currentQuestion!));
      engine.submitAnswer(engine.getState().currentQuestion!.answer);
      engine.submitAnswer(engine.getState().currentQuestion!.answer);

      expect(engine.getState().status).assertEqual(BattleStatus.Won);
      const result: SessionResult = engine.buildSessionResult();
      expect(result.status).assertEqual(BattleStatus.Won);
      expect(result.correctRate < 0.8).assertTrue();
      expect(result.stars).assertEqual(2);
    });

    it('lostWithThreeDefeatsYieldsTwoStars', 0, () => {
      // Lose after defeating exactly 3 monsters. Spec §4.4 tier-2 row's
      // OR-clause: at least 3 monsters defeated grants 2 stars even on a
      // loss. Configure so 3 corrects kill 3 monsters, then enough wrongs
      // drain the player HP to zero.
      const cfg: BattleConfig = new BattleConfig();
      cfg.monsterMaxHp = 1;
      cfg.monstersTotal = 5;
      cfg.playerMaxHp = 3;
      const engine: BattleEngine = engineWithFruit(1, cfg);
      engine.submitAnswer(engine.getState().currentQuestion!.answer);
      engine.submitAnswer(engine.getState().currentQuestion!.answer);
      engine.submitAnswer(engine.getState().currentQuestion!.answer);
      // 3 wrongs drain the 3 HP the player has left.
      engine.submitAnswer(pickWrongOption(engine.getState().currentQuestion!));
      engine.submitAnswer(pickWrongOption(engine.getState().currentQuestion!));
      engine.submitAnswer(pickWrongOption(engine.getState().currentQuestion!));

      expect(engine.getState().status).assertEqual(BattleStatus.Lost);
      const result: SessionResult = engine.buildSessionResult();
      expect(result.defeatedMonsters).assertEqual(3);
      expect(result.stars).assertEqual(2);
    });

    it('lostWithOneDefeatYieldsOneStar', 0, () => {
      const cfg: BattleConfig = new BattleConfig();
      cfg.monsterMaxHp = 1;
      cfg.monstersTotal = 5;
      cfg.playerMaxHp = 2;
      const engine: BattleEngine = engineWithFruit(1, cfg);
      engine.submitAnswer(engine.getState().currentQuestion!.answer); // kill 1
      engine.submitAnswer(pickWrongOption(engine.getState().currentQuestion!));
      engine.submitAnswer(pickWrongOption(engine.getState().currentQuestion!));

      expect(engine.getState().status).assertEqual(BattleStatus.Lost);
      const result: SessionResult = engine.buildSessionResult();
      expect(result.defeatedMonsters).assertEqual(1);
      expect(result.stars).assertEqual(1);
    });

    it('lostWithoutDefeatYieldsZeroStars', 0, () => {
      const cfg: BattleConfig = new BattleConfig();
      cfg.playerMaxHp = 2;
      const engine: BattleEngine = engineWithFruit(1, cfg);
      engine.submitAnswer(pickWrongOption(engine.getState().currentQuestion!));
      engine.submitAnswer(pickWrongOption(engine.getState().currentQuestion!));

      expect(engine.getState().status).assertEqual(BattleStatus.Lost);
      const result: SessionResult = engine.buildSessionResult();
      expect(result.defeatedMonsters).assertEqual(0);
      expect(result.stars).assertEqual(0);
    });

    it('reportsLearnedWordCount', 0, () => {
      const cfg: BattleConfig = new BattleConfig();
      cfg.monsterMaxHp = 1;
      cfg.monstersTotal = 2;
      const engine: BattleEngine = engineWithFruit(1, cfg);
      engine.submitAnswer(engine.getState().currentQuestion!.answer);
      engine.submitAnswer(engine.getState().currentQuestion!.answer);
      const result: SessionResult = engine.buildSessionResult();
      // start() primes 1 word, the first correct spawns monster #2 plus
      // a fresh question (word #2), and the second correct wins the
      // battle WITHOUT spawning another question. So exactly 2 unique
      // words were shown this session.
      expect(result.learnedWordCount).assertEqual(2);
    });

    it('correctRateIsZeroWhenNoAnswersSubmittedAndTimeRanOut', 0, () => {
      const cfg: BattleConfig = new BattleConfig();
      cfg.startingSeconds = 1;
      const engine: BattleEngine = engineWithFruit(1, cfg);
      engine.tick(1);
      const result: SessionResult = engine.buildSessionResult();
      expect(result.status).assertEqual(BattleStatus.Lost);
      expect(result.totalAnswers).assertEqual(0);
      expect(result.correctRate).assertEqual(0);
      expect(result.stars).assertEqual(0);
    });
  });

  describe('GameConfig.defaults', () => {
    it('defaultsMatchEngineDefaults', 0, () => {
      const c: GameConfig = new GameConfig();
      expect(c.playerMaxHp).assertEqual(DEFAULT_PLAYER_HP);
      expect(c.monsterMaxHp).assertEqual(DEFAULT_MONSTER_HP);
      expect(c.monstersTotal).assertEqual(DEFAULT_MONSTERS_TOTAL);
      expect(c.startingSeconds).assertEqual(DEFAULT_STARTING_SECONDS);
      expect(c.customWordsRaw).assertEqual('');
      expect(c.enabledCategories.length).assertEqual(KNOWN_CATEGORIES.length);
      for (let i = 0; i < KNOWN_CATEGORIES.length; i++) {
        expect(c.enabledCategories.indexOf(KNOWN_CATEGORIES[i]) >= 0).assertTrue();
      }
      expect(HP_MIN).assertEqual(1);
      expect(HP_MAX).assertEqual(10);
      expect(MONSTER_COUNT_MIN).assertEqual(1);
      expect(MONSTER_COUNT_MAX).assertEqual(10);
      expect(MIN_POOL_SIZE).assertEqual(3);
      expect(CUSTOM_CATEGORY_KEY).assertEqual('custom');
      expect(TIMER_CHOICES.indexOf(DEFAULT_STARTING_SECONDS) >= 0).assertTrue();
      expect(TIMER_CHOICES.indexOf(3) >= 0).assertTrue();
    });
  });

  describe('GameConfig.cloneGameConfig', () => {
    it('cloneIsDeepEnoughToIsolateDraft', 0, () => {
      const original: GameConfig = new GameConfig();
      original.customWordsRaw = '苹果:apple';
      const beforePlayer: number = original.playerMaxHp;
      const beforeCats: string[] = original.enabledCategories.slice();
      const beforeRaw: string = original.customWordsRaw;

      const clone: GameConfig = cloneGameConfig(original);
      clone.playerMaxHp = 1;
      clone.monsterMaxHp = 9;
      clone.monstersTotal = 2;
      clone.startingSeconds = 3;
      clone.enabledCategories.push('mutated');
      clone.customWordsRaw = 'mutated';

      expect(original.playerMaxHp).assertEqual(beforePlayer);
      expect(original.enabledCategories.length).assertEqual(beforeCats.length);
      for (let i = 0; i < beforeCats.length; i++) {
        expect(original.enabledCategories[i]).assertEqual(beforeCats[i]);
      }
      expect(original.customWordsRaw).assertEqual(beforeRaw);
    });
  });

  describe('GameConfig.parseCustomWords', () => {
    it('emptyReturnsEmpty', 0, () => {
      expect(parseCustomWords('').length).assertEqual(0);
      expect(parseCustomWords('\n\n  \n').length).assertEqual(0);
    });

    it('acceptsAsciiAndFullwidthColon', 0, () => {
      const out: WordEntry[] = parseCustomWords('苹果:apple\n香蕉：banana');
      expect(out.length).assertEqual(2);
      expect(out[0].meaningZh).assertEqual('苹果');
      expect(out[0].word).assertEqual('apple');
      expect(out[0].category).assertEqual(CUSTOM_CATEGORY_KEY);
      expect(out[0].id).assertEqual('custom-0');
      expect(out[1].meaningZh).assertEqual('香蕉');
      expect(out[1].word).assertEqual('banana');
      expect(out[1].id).assertEqual('custom-1');
    });

    it('skipsInvalidLinesAndKeepsIdsSequential', 0, () => {
      const raw: string = [
        '苹果:apple',
        'no colon here',
        ':only-right',
        '香蕉:banana',
        '左边只有:',
        '   ',
        '梨:pear'
      ].join('\n');
      const out: WordEntry[] = parseCustomWords(raw);
      expect(out.length).assertEqual(3);
      expect(out[0].id).assertEqual('custom-0');
      expect(out[0].word).assertEqual('apple');
      expect(out[1].id).assertEqual('custom-1');
      expect(out[1].word).assertEqual('banana');
      expect(out[2].id).assertEqual('custom-2');
      expect(out[2].word).assertEqual('pear');
    });
  });

  describe('GameConfig.computeFinalPool', () => {
    it('customDisabledIgnoresRaw', 0, () => {
      const all: WordEntry[] = [
        makeEntry('a1', 'apple', 'fruit'),
        makeEntry('p1', 'park', 'place'),
        makeEntry('h1', 'home', 'home')
      ];
      const out: WordEntry[] = computeFinalPool(all, ['fruit'], '你好:hello');
      expect(out.length).assertEqual(1);
      expect(out[0].category).assertEqual('fruit');
    });

    it('customEnabledMergesCustoms', 0, () => {
      const all: WordEntry[] = [
        makeEntry('a1', 'apple', 'fruit'),
        makeEntry('a2', 'pear', 'fruit')
      ];
      const out: WordEntry[] = computeFinalPool(all, ['fruit', CUSTOM_CATEGORY_KEY], '你好:hello');
      expect(out.length).assertEqual(3);
      expect(out[2].category).assertEqual(CUSTOM_CATEGORY_KEY);
      expect(out[2].word).assertEqual('hello');
    });

    it('customOnlyEmpty', 0, () => {
      const all: WordEntry[] = [
        makeEntry('a1', 'apple', 'fruit')
      ];
      const out: WordEntry[] = computeFinalPool(all, [CUSTOM_CATEGORY_KEY], '');
      expect(out.length).assertEqual(0);
    });

    it('customOnlyWithValidCustoms', 0, () => {
      const all: WordEntry[] = [
        makeEntry('a1', 'apple', 'fruit')
      ];
      const out: WordEntry[] = computeFinalPool(
        all,
        [CUSTOM_CATEGORY_KEY],
        '一:one\n二:two\n三:three');
      expect(out.length).assertEqual(3);
      expect(out[0].category).assertEqual(CUSTOM_CATEGORY_KEY);
    });

    it('builtinOnlyFilters', 0, () => {
      const all: WordEntry[] = [
        makeEntry('a1', 'apple', 'fruit'),
        makeEntry('p1', 'park', 'place'),
        makeEntry('h1', 'home', 'home'),
        makeEntry('a2', 'pear', 'fruit')
      ];
      const out: WordEntry[] = computeFinalPool(all, ['fruit', 'home'], '');
      expect(out.length).assertEqual(3);
    });
  });

  describe('AudioService', () => {
    it('exposesAllSixSoundKeys', 0, () => {
      // Guards against silently dropping a key when the SFX table is
      // edited — every key BattlePage expects must be in the preload list.
      expect(ALL_SOUND_KEYS.length).assertEqual(6);
      expect(ALL_SOUND_KEYS.indexOf(SoundKeys.HIT_NORMAL) >= 0).assertTrue();
      expect(ALL_SOUND_KEYS.indexOf(SoundKeys.HIT_CRIT) >= 0).assertTrue();
      expect(ALL_SOUND_KEYS.indexOf(SoundKeys.ANSWER_WRONG) >= 0).assertTrue();
      expect(ALL_SOUND_KEYS.indexOf(SoundKeys.MONSTER_DEFEAT) >= 0).assertTrue();
      expect(ALL_SOUND_KEYS.indexOf(SoundKeys.VICTORY) >= 0).assertTrue();
      expect(ALL_SOUND_KEYS.indexOf(SoundKeys.DEFEAT) >= 0).assertTrue();
    });

    it('playBeforePreloadIsSafeNoOp', 0, () => {
      // New service with no preload should tolerate play() without
      // throwing — this is the state during BattlePage's first render
      // before AudioService.preload resolves.
      const svc: AudioService = new AudioService();
      svc.play(SoundKeys.HIT_NORMAL);
      svc.play('unknown_key');
      expect(svc.hasKey(SoundKeys.HIT_NORMAL)).assertFalse();
      expect(svc.isPlayable(SoundKeys.HIT_NORMAL)).assertFalse();
    });

    it('playAfterDisposeIsNoOp', 0, async () => {
      const svc: AudioService = new AudioService();
      await svc.dispose();
      svc.play(SoundKeys.HIT_NORMAL);
      expect(svc.hasKey(SoundKeys.HIT_NORMAL)).assertFalse();
    });
  });
}
