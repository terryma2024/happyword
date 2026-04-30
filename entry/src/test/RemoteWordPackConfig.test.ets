import { describe, it, expect } from '@ohos/hypium';
import {
  pickServerBaseUrl,
  buildLatestPackUrl,
  DEV_BASE_URL,
  PROD_BASE_URL,
} from '../main/ets/services/RemoteWordPackConfig';

export default function remoteWordPackConfigTest() {
  describe('RemoteWordPackConfig', () => {
    it('debugBuildPicksDevUrl', 0, () => {
      expect(pickServerBaseUrl('debug')).assertEqual(DEV_BASE_URL);
    });
    it('releaseBuildPicksProdUrl', 0, () => {
      expect(pickServerBaseUrl('release')).assertEqual(PROD_BASE_URL);
    });
    it('unknownBuildModeFallsBackToProd', 0, () => {
      expect(pickServerBaseUrl('something-else')).assertEqual(PROD_BASE_URL);
    });
    it('devUrlIsEmulatorHostLoopback', 0, () => {
      expect(DEV_BASE_URL).assertEqual('http://10.0.2.2:8000');
    });
    it('prodUrlIsVercelDomain', 0, () => {
      expect(PROD_BASE_URL).assertEqual('https://happyword.vercel.app');
    });
    it('buildLatestPackUrlAppendsCorrectPath', 0, () => {
      expect(buildLatestPackUrl(PROD_BASE_URL)).assertEqual(
        'https://happyword.vercel.app/api/v1/packs/latest.json',
      );
    });
    it('buildLatestPackUrlReturnsEmptyForEmptyBase', 0, () => {
      expect(buildLatestPackUrl('')).assertEqual('');
    });
  });
}
