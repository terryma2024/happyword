import { describe, it, expect } from '@ohos/hypium';
import { GameConfig, cloneGameConfig } from '../main/ets/models/GameConfig';
import { gameConfigFromJson, gameConfigToJson } from '../main/ets/services/GameConfigPersistence';
import { MonsterKind, MonsterLevel } from '../main/ets/data/MonsterCatalog';
import { QuestionKind } from '../main/ets/models/Question';
import { WordEntry } from '../main/ets/models/WordEntry';
import {
  BATTLE_QUESTION_TYPE_SENTENCE_FILL,
  DEFAULT_ENABLED_QUESTION_TYPES,
  questionTypeForMonsterKind,
  questionTypeForMonsterLevel,
  questionTypeToMonsterKind,
  resolveQuestionTypeForWord,
  sanitizeEnabledQuestionTypes,
  wordSupportsQuestionType,
} from '../main/ets/services/BattleQuestionTypePolicy';

function makeWord(id: string, word: string): WordEntry {
  const w: WordEntry = new WordEntry();
  w.id = id;
  w.word = word;
  w.meaningZh = word;
  w.category = 'test';
  w.difficulty = 1;
  return w;
}

export default function battleQuestionTypePolicyTest() {
  describe('BattleQuestionTypePolicy', () => {
    it('defaultsToAllImplementedTypesInDifficultyOrder', 0, () => {
      expect(DEFAULT_ENABLED_QUESTION_TYPES.length).assertEqual(4);
      expect(DEFAULT_ENABLED_QUESTION_TYPES[0]).assertEqual(QuestionKind.Choice);
      expect(DEFAULT_ENABLED_QUESTION_TYPES[1]).assertEqual(QuestionKind.FillLetter);
      expect(DEFAULT_ENABLED_QUESTION_TYPES[2]).assertEqual(QuestionKind.FillLetterMedium);
      expect(DEFAULT_ENABLED_QUESTION_TYPES[3]).assertEqual(QuestionKind.Spell);
    });

    it('sanitizesUnknownDuplicateAndFutureTypes', 0, () => {
      const out: string[] = sanitizeEnabledQuestionTypes([
        QuestionKind.Spell,
        'unknown-kind',
        QuestionKind.FillLetter,
        BATTLE_QUESTION_TYPE_SENTENCE_FILL,
        QuestionKind.Spell,
      ]);
      expect(out.length).assertEqual(2);
      expect(out[0]).assertEqual(QuestionKind.FillLetter);
      expect(out[1]).assertEqual(QuestionKind.Spell);
    });

    it('fallsBackToDefaultWhenStoredListHasNoImplementedType', 0, () => {
      const out: string[] = sanitizeEnabledQuestionTypes([
        'unknown-kind',
        BATTLE_QUESTION_TYPE_SENTENCE_FILL,
      ]);
      expect(out.length).assertEqual(DEFAULT_ENABLED_QUESTION_TYPES.length);
      expect(out[0]).assertEqual(QuestionKind.Choice);
    });

    it('mapsQuestionTypesToStrictMonsterKinds', 0, () => {
      expect(questionTypeToMonsterKind(QuestionKind.Choice)).assertEqual(MonsterKind.Normal);
      expect(questionTypeToMonsterKind(QuestionKind.FillLetter)).assertEqual(MonsterKind.Spelling);
      expect(questionTypeToMonsterKind(QuestionKind.FillLetterMedium)).assertEqual(MonsterKind.Elite);
      expect(questionTypeToMonsterKind(QuestionKind.Spell)).assertEqual(MonsterKind.Boss);
      expect(questionTypeForMonsterKind(MonsterKind.Review)).assertEqual(QuestionKind.Choice);
    });

    it('routesQuestionTypesByMonsterLevel', 0, () => {
      expect(questionTypeForMonsterLevel(MonsterLevel.Beginner)).assertEqual(QuestionKind.Choice);
      expect(questionTypeForMonsterLevel(MonsterLevel.Intermediate)).assertEqual(QuestionKind.FillLetter);
      expect(questionTypeForMonsterLevel(MonsterLevel.Advanced)).assertEqual(QuestionKind.FillLetterMedium);
      expect(questionTypeForMonsterLevel(MonsterLevel.Super)).assertEqual(QuestionKind.Spell);
    });

    it('degradesGracefullyForShortWordOnAdvanced', 0, () => {
      const zoo: WordEntry = makeWord('place-zoo', 'zoo');
      const resolved: string = resolveQuestionTypeForWord(
        zoo,
        questionTypeForMonsterLevel(MonsterLevel.Advanced),
      );
      expect(resolved).assertEqual(QuestionKind.Choice);
    });

    it('checksWordEligibilityForImplementedTypes', 0, () => {
      expect(wordSupportsQuestionType(makeWord('w-tv', 'TV'), QuestionKind.Choice)).assertTrue();
      expect(wordSupportsQuestionType(makeWord('w-tv', 'TV'), QuestionKind.FillLetter)).assertFalse();
      expect(wordSupportsQuestionType(makeWord('w-cat', 'cat'), QuestionKind.FillLetter)).assertTrue();
      expect(wordSupportsQuestionType(makeWord('w-cat', 'cat'), QuestionKind.FillLetterMedium)).assertFalse();
      expect(wordSupportsQuestionType(makeWord('w-fish', 'fish'), QuestionKind.FillLetterMedium)).assertTrue();
      expect(wordSupportsQuestionType(makeWord('w-fish', 'fish'), QuestionKind.Spell)).assertTrue();
      expect(wordSupportsQuestionType(makeWord('w-strawberry', 'strawberry'), QuestionKind.Spell)).assertFalse();
    });
  });

  describe('GameConfig question types', () => {
    it('clonePreservesEnabledQuestionTypesWithoutSharingArray', 0, () => {
      const cfg: GameConfig = new GameConfig();
      cfg.enabledQuestionTypes = [QuestionKind.Spell];
      const cloned: GameConfig = cloneGameConfig(cfg);
      expect(cloned.enabledQuestionTypes.length).assertEqual(1);
      expect(cloned.enabledQuestionTypes[0]).assertEqual(QuestionKind.Spell);
      cfg.enabledQuestionTypes[0] = QuestionKind.Choice;
      expect(cloned.enabledQuestionTypes[0]).assertEqual(QuestionKind.Spell);
    });

    it('persistsAndSanitizesQuestionTypes', 0, () => {
      const cfg: GameConfig = new GameConfig();
      cfg.enabledQuestionTypes = [QuestionKind.Spell, QuestionKind.FillLetter];
      const roundTrip: GameConfig = gameConfigFromJson(gameConfigToJson(cfg));
      expect(roundTrip.enabledQuestionTypes.length).assertEqual(2);
      expect(roundTrip.enabledQuestionTypes[0]).assertEqual(QuestionKind.FillLetter);
      expect(roundTrip.enabledQuestionTypes[1]).assertEqual(QuestionKind.Spell);
    });
  });
}
