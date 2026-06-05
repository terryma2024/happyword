import { describe, it, expect } from '@ohos/hypium';
import { coverImageSourceForCachedPath } from '../main/ets/services/SpellbookCoverCache';

export default function spellbookCoverCacheTest(): void {
  describe('SpellbookCoverCache', () => {
    it('formatsCachedSandboxPathAsFileUriForImage', 0, () => {
      const path: string = '/data/app/el2/100/base/com.app/haps/entry/files/asset-cache/covers/cover.png';

      expect(coverImageSourceForCachedPath(path)).assertEqual(
        'file:///data/app/el2/100/base/com.app/haps/entry/files/asset-cache/covers/cover.png',
      );
    });

    it('leavesExistingFileUriUnchanged', 0, () => {
      expect(coverImageSourceForCachedPath('file:///tmp/cover.png')).assertEqual('file:///tmp/cover.png');
    });
  });
}
