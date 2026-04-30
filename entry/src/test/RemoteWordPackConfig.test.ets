import { describe, it, expect } from '@ohos/hypium';
import {
  pickServerBaseUrl,
  pickServerBaseUrlExplicit,
  buildLatestPackUrl,
  DEV_BASE_URL,
  PROD_BASE_URL,
  USE_LOCAL_DEV_SERVER,
} from '../main/ets/services/RemoteWordPackConfig';

export default function remoteWordPackConfigTest() {
  describe('RemoteWordPackConfig', () => {
    it('localDevServerToggleDefaultsOff', 0, () => {
      expect(USE_LOCAL_DEV_SERVER).assertEqual(false);
    });
    it('debugBuildHitsProdByDefault', 0, () => {
      expect(pickServerBaseUrl('debug')).assertEqual(PROD_BASE_URL);
    });
    it('releaseBuildHitsProd', 0, () => {
      expect(pickServerBaseUrl('release')).assertEqual(PROD_BASE_URL);
    });
    it('unknownBuildModeFallsBackToProd', 0, () => {
      expect(pickServerBaseUrl('something-else')).assertEqual(PROD_BASE_URL);
    });
    it('explicitDebugWithLocalDevServerOnPicksDevUrl', 0, () => {
      expect(pickServerBaseUrlExplicit('debug', true)).assertEqual(DEV_BASE_URL);
    });
    it('explicitDebugWithLocalDevServerOffPicksProd', 0, () => {
      expect(pickServerBaseUrlExplicit('debug', false)).assertEqual(PROD_BASE_URL);
    });
    it('explicitReleaseAlwaysIgnoresLocalDevServerToggle', 0, () => {
      expect(pickServerBaseUrlExplicit('release', true)).assertEqual(PROD_BASE_URL);
      expect(pickServerBaseUrlExplicit('release', false)).assertEqual(PROD_BASE_URL);
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
