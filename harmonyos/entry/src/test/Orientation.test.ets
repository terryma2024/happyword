import { describe, it, expect } from '@ohos/hypium';
import {
  lockPortrait,
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
  });
}
