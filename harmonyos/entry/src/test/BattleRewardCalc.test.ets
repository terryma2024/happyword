import { describe, it, expect } from '@ohos/hypium';
import {
  computeBonusCoinDelta,
  computeFinalCoinAward,
} from '../main/ets/services/BattleRewardCalc';

export default function battleRewardCalcTest() {
  describe('BattleRewardCalc', () => {
    it('noBonusKillsKeepsCoinsEqualToStars', 0, () => {
      expect(computeFinalCoinAward(3, 0, true)).assertEqual(3);
      expect(computeBonusCoinDelta(3, 0, true)).assertEqual(0);
    });

    it('oneBonusKillCeilsBaseTimes13', 0, () => {
      expect(computeFinalCoinAward(3, 1, true)).assertEqual(4);
      expect(computeBonusCoinDelta(3, 1, true)).assertEqual(1);
    });

    it('lossWithBonusKillsStillGivesNoBonus', 0, () => {
      expect(computeFinalCoinAward(3, 2, false)).assertEqual(3);
      expect(computeBonusCoinDelta(3, 2, false)).assertEqual(0);
    });
  });
}
