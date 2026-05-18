import { describe, it, expect } from '@ohos/hypium';
import { Question, QuestionKind } from '../main/ets/models/Question';
import { BattleStatus } from '../main/ets/models/BattleState';
import { IQuestionSource } from '../main/ets/services/IQuestionSource';
import {
  BattleConfig,
  BattleEngine,
  computePlayerDamage,
  rollMonsterBonus,
} from '../main/ets/services/BattleEngine';
import { MonsterLevel } from '../main/ets/data/MonsterCatalog';

class StubQuestionSource implements IQuestionSource {
  nextQuestion(_lastWordId?: string): Question {
    const q: Question = new Question();
    q.kind = QuestionKind.Choice;
    q.promptZh = 'test';
    q.answer = 'cat';
    q.options = ['cat', 'dog', 'pig'];
    q.wordId = 'w-cat';
    return q;
  }
}

export default function battleEngineTest() {
  describe('BattleEngine damage and bonus (V0.8.3)', () => {
    it('beginnerMonsterAlwaysDamagesOne', 0, () => {
      const rng = (): number => 0;
      for (let i: number = 0; i < 10; i++) {
        expect(computePlayerDamage(MonsterLevel.Beginner, rng)).assertEqual(1);
      }
    });

    it('superMonsterDamagesTwoWhenRngLow', 0, () => {
      expect(computePlayerDamage(MonsterLevel.Super, (): number => 0)).assertEqual(2);
    });

    it('superMonsterDamagesOneWhenRngHigh', 0, () => {
      expect(computePlayerDamage(MonsterLevel.Super, (): number => 0.5)).assertEqual(1);
    });

    it('intermediateMonsterNeverBonus', 0, () => {
      expect(rollMonsterBonus(MonsterLevel.Intermediate, (): number => 0)).assertFalse();
    });

    it('advancedMonsterBonusWhenRngLow', 0, () => {
      expect(rollMonsterBonus(MonsterLevel.Advanced, (): number => 0)).assertTrue();
    });

    it('superMonsterBonusWhenRngHigh', 0, () => {
      expect(rollMonsterBonus(MonsterLevel.Super, (): number => 0.99)).assertFalse();
    });

    it('wrongAnswerFromSuperDealsTwoDamageWhenRngLow', 0, () => {
      const bc: BattleConfig = new BattleConfig();
      bc.catalogIndexProvider = (): number => 10;
      bc.rng = (): number => 0;
      const engine: BattleEngine = new BattleEngine(new StubQuestionSource(), bc);
      engine.start();
      const outcome = engine.submitAnswer('dog');
      expect(outcome.correct).assertFalse();
      expect(outcome.damage).assertEqual(2);
      expect(engine.getState().playerHp).assertEqual(8);
    });

    it('spellWrongTapDamagesOne', 0, () => {
      const engine: BattleEngine = new BattleEngine(new StubQuestionSource());
      engine.start();
      const damage = engine.applySpellLetterPenalty();
      expect(damage).assertEqual(1);
      expect(engine.getState().playerHp).assertEqual(9);
      expect(engine.getState().status).assertEqual(BattleStatus.Playing);
    });

    it('spellWrongTapAtOneHpEndsBattle', 0, () => {
      const bc: BattleConfig = new BattleConfig();
      bc.playerMaxHp = 1;
      const engine: BattleEngine = new BattleEngine(new StubQuestionSource(), bc);
      engine.start();
      engine.applySpellLetterPenalty();
      expect(engine.getState().playerHp).assertEqual(0);
      expect(engine.getState().status).assertEqual(BattleStatus.Lost);
    });

    it('bonusKillCountIncrementsOnKill', 0, () => {
      const bc: BattleConfig = new BattleConfig();
      bc.monstersTotal = 1;
      bc.monsterMaxHp = 1;
      bc.catalogIndexProvider = (): number => 10;
      bc.rng = (): number => 0;
      const engine: BattleEngine = new BattleEngine(new StubQuestionSource(), bc);
      engine.start();
      expect(engine.getState().currentMonsterBonus).assertTrue();
      engine.submitAnswer('cat');
      const result = engine.buildSessionResult();
      expect(result.bonusKillCount).assertEqual(1);
      expect(result.status).assertEqual(BattleStatus.Won);
    });
  });
}
