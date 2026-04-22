import { describe, it, expect } from '@ohos/hypium';
import { generateRibbons, Ribbon, RIBBON_COLORS } from '../main/ets/components/GiftBox';

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
}
