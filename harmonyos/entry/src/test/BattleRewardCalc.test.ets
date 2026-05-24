import { describe, it, expect } from '@ohos/hypium';
import { MonsterLevel } from '../main/ets/data/MonsterCatalog';
import {
  coinValueForMonsterLevel,
  computeMonsterLevelCoinAward,
  computeRetiredBonusCoinDelta,
} from '../main/ets/services/BattleRewardCalc';

export default function battleRewardCalcTest() {
  describe('BattleRewardCalc', () => {
    it('mapsMonsterLevelsToCoinValues', 0, () => {
      expect(coinValueForMonsterLevel(MonsterLevel.Beginner)).assertEqual(1);
      expect(coinValueForMonsterLevel(MonsterLevel.Intermediate)).assertEqual(2);
      expect(coinValueForMonsterLevel(MonsterLevel.Advanced)).assertEqual(3);
      expect(coinValueForMonsterLevel(MonsterLevel.Super)).assertEqual(4);
    });

    it('usesMonsterLevelScoreAsTheFinalAward', 0, () => {
      expect(computeMonsterLevelCoinAward(9)).assertEqual(9);
      expect(computeMonsterLevelCoinAward(0)).assertEqual(0);
    });

    it('retiredBonusMultiplierNeverAddsCoins', 0, () => {
      expect(computeRetiredBonusCoinDelta(9, 2, true)).assertEqual(0);
      expect(computeRetiredBonusCoinDelta(9, 2, false)).assertEqual(0);
    });
  });
}
