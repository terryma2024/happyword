import { describe, it, expect } from '@ohos/hypium';
import {
  desiredOrientationForPage,
  lockPortrait,
  PAD_SHORT_EDGE_BREAKPOINT_VP,
  restoreAutoLandscape,
  IOrientationAdapter,
  OrientationName,
} from '../main/ets/utils/orientation';

class StubAdapter implements IOrientationAdapter {
  setCalls: OrientationName[] = [];
  shouldThrow: boolean = false;

  async setPreferredOrientation(name: OrientationName): Promise<void> {
    if (this.shouldThrow) {
      throw new Error('window not ready');
    }
    this.setCalls.push(name);
  }
}

export default function orientationTest(): void {
  describe('orientation helpers', () => {
    it('lockPortrait calls adapter with PORTRAIT', 0, async () => {
      const a: StubAdapter = new StubAdapter();
      await lockPortrait(a);
      expect(a.setCalls.length).assertEqual(1);
      expect(a.setCalls[0]).assertEqual('PORTRAIT');
    });

    it('restoreAutoLandscape calls adapter with AUTO_ROTATION_LANDSCAPE', 0, async () => {
      const a: StubAdapter = new StubAdapter();
      await restoreAutoLandscape(a);
      expect(a.setCalls.length).assertEqual(1);
      expect(a.setCalls[0]).assertEqual('AUTO_ROTATION_LANDSCAPE');
    });

    it('lockPortrait swallows adapter errors', 0, async () => {
      const a: StubAdapter = new StubAdapter();
      a.shouldThrow = true;
      await lockPortrait(a);
      expect(a.setCalls.length).assertEqual(0);
    });

    it('restoreAutoLandscape swallows adapter errors', 0, async () => {
      const a: StubAdapter = new StubAdapter();
      a.shouldThrow = true;
      await restoreAutoLandscape(a);
      expect(a.setCalls.length).assertEqual(0);
    });

    it('phone landscape pages request auto-rotation landscape', 0, () => {
      expect(desiredOrientationForPage('HomePage', PAD_SHORT_EDGE_BREAKPOINT_VP - 1))
        .assertEqual('AUTO_ROTATION_LANDSCAPE');
      expect(desiredOrientationForPage('WishlistPage', PAD_SHORT_EDGE_BREAKPOINT_VP - 1))
        .assertEqual('AUTO_ROTATION_LANDSCAPE');
    });

    it('phone portrait pages request portrait', 0, () => {
      expect(desiredOrientationForPage('ConfigPage', PAD_SHORT_EDGE_BREAKPOINT_VP - 1))
        .assertEqual('PORTRAIT');
      expect(desiredOrientationForPage('TodayPlanPage', PAD_SHORT_EDGE_BREAKPOINT_VP - 1))
        .assertEqual('PORTRAIT');
      expect(desiredOrientationForPage('LessonDraftReviewPage', PAD_SHORT_EDGE_BREAKPOINT_VP - 1))
        .assertEqual('PORTRAIT');
      expect(desiredOrientationForPage('InAppBrowserPage', PAD_SHORT_EDGE_BREAKPOINT_VP - 1))
        .assertEqual('PORTRAIT');
    });

    it('pad pages release to full auto-rotation', 0, () => {
      expect(desiredOrientationForPage('BattlePage', PAD_SHORT_EDGE_BREAKPOINT_VP))
        .assertEqual('AUTO_ROTATION');
      expect(desiredOrientationForPage('PackManagerPage', PAD_SHORT_EDGE_BREAKPOINT_VP))
        .assertEqual('AUTO_ROTATION');
    });
  });
}
