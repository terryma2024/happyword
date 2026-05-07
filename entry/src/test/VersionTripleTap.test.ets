import { describe, it, expect } from '@ohos/hypium';
import { VersionTripleTap } from '../main/ets/services/VersionTripleTap';

export default function versionTripleTapTest(): void {
  describe('VersionTripleTap', () => {
    it('firesOnThirdTapInsideWindow', 0, () => {
      const t: VersionTripleTap = new VersionTripleTap(1000);
      expect(t.onTap(0)).assertEqual(false);
      expect(t.onTap(200)).assertEqual(false);
      expect(t.onTap(400)).assertEqual(true);
    });

    it('doesNotReFireOnFourthTap', 0, () => {
      const t: VersionTripleTap = new VersionTripleTap(1000);
      t.onTap(0);
      t.onTap(100);
      expect(t.onTap(200)).assertEqual(true);
      // Tap 4 inside window must NOT fire — counter resets after firing.
      expect(t.onTap(205)).assertEqual(false);
      expect(t.onTap(210)).assertEqual(false);
      expect(t.onTap(215)).assertEqual(true);
    });

    it('resetsWhenGapExceedsWindow', 0, () => {
      const t: VersionTripleTap = new VersionTripleTap(1000);
      expect(t.onTap(0)).assertEqual(false);
      expect(t.onTap(500)).assertEqual(false);
      // 1500ms gap exceeds the 1000ms window → counter resets.
      expect(t.onTap(2001)).assertEqual(false);
      expect(t.pendingCount()).assertEqual(1);
    });

    it('honoursCustomWindow', 0, () => {
      const fast: VersionTripleTap = new VersionTripleTap(500);
      expect(fast.onTap(0)).assertEqual(false);
      expect(fast.onTap(200)).assertEqual(false);
      expect(fast.onTap(400)).assertEqual(true);

      const slow: VersionTripleTap = new VersionTripleTap(500);
      expect(slow.onTap(0)).assertEqual(false);
      expect(slow.onTap(300)).assertEqual(false);
      // 700 - 300 = 400 ≤ 500, this DOES fire. Use a larger gap to
      // assert reset behaviour at the custom window boundary.
      expect(slow.onTap(900)).assertEqual(false);
      expect(slow.pendingCount()).assertEqual(1);
    });

    it('pendingCountReflectsInternalCounter', 0, () => {
      const t: VersionTripleTap = new VersionTripleTap(1000);
      expect(t.pendingCount()).assertEqual(0);
      t.onTap(0);
      expect(t.pendingCount()).assertEqual(1);
      t.onTap(100);
      expect(t.pendingCount()).assertEqual(2);
      t.onTap(200);
      // Counter zeroed after firing on tap 3.
      expect(t.pendingCount()).assertEqual(0);
    });
  });
}
