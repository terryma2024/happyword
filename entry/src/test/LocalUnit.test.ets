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
}
