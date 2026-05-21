import { describe, it, expect } from '@ohos/hypium';
import { parseManifest } from '../main/ets/services/PreviewManifestService';

export default function previewManifestServiceTest(): void {
  describe('PreviewManifestService', () => {
    it('keepsCloudBaseStagingRows', 0, () => {
      const payload: string = '{"schema_version":1,"updated_at":"2026-05-20T00:00:00Z","previews":[{"pr":0,"title":"CloudBase Staging","branch":"shared-staging","url":"https://happyword-server-staging-255236-5-1429584068.sh.run.tcloudbase.com","author":"cloudbase","head_sha":"inline","updated_at":"2026-05-20T00:00:00Z"}]}';
      const manifest = parseManifest(payload);

      expect(manifest !== null).assertTrue();
      expect(manifest?.previews.length).assertEqual(1);
      expect(manifest?.previews[0].title).assertEqual('CloudBase Staging');
      expect(manifest?.previews[0].url).assertEqual(
        'https://happyword-server-staging-255236-5-1429584068.sh.run.tcloudbase.com',
      );
    });
  });
}
