import { describe, it, expect } from '@ohos/hypium';
import {
  DamageFloaterStyle,
  pickFloaterStyle,
} from '../main/ets/components/DamageFloaterLabel';

export default function damageFloaterLabelTest() {
  describe('DamageFloaterLabel.pickFloaterStyle', () => {
    it('pickFloaterStyleForOneIsBright', 0, () => {
      const style: DamageFloaterStyle = pickFloaterStyle(1);
      expect(style.text).assertEqual('-1');
      expect(style.color).assertEqual('#F87171');
      expect(style.fontSize).assertEqual(18);
    });

    it('pickFloaterStyleForTwoIsDeep', 0, () => {
      const style: DamageFloaterStyle = pickFloaterStyle(2);
      expect(style.text).assertEqual('-2');
      expect(style.color).assertEqual('#7F1D1D');
      expect(style.fontSize).assertEqual(20);
    });

    it('pickFloaterStyleForOneHasStroke', 0, () => {
      const style: DamageFloaterStyle = pickFloaterStyle(1);
      expect(style.hasStroke).assertTrue();
      expect(style.shadowRadius).assertEqual(0);
    });

    it('pickFloaterStyleForTwoHasShadow', 0, () => {
      const style: DamageFloaterStyle = pickFloaterStyle(2);
      expect(style.hasStroke).assertFalse();
      expect(style.shadowRadius).assertEqual(2);
    });
  });
}
