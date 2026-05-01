import { describe, it, expect } from '@ohos/hypium';
import {
  pickServerBaseUrl,
  pickServerBaseUrlExplicit,
  buildLatestPackUrl,
  resolveServerBaseUrl,
  effectiveServerBaseUrl,
  SERVER_BASE_URL_OVERRIDE_KEY,
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
    it('overrideKeyIsStableForGrep', 0, () => {
      // The ohosTest harness writes this exact key in beforeAll. If
      // we ever rename it, both production resolveServerBaseUrl and
      // List.test.ets must move together — this assertion guards
      // against half-renames that silently leak prod traffic.
      expect(SERVER_BASE_URL_OVERRIDE_KEY).assertEqual('serverBaseUrlOverride');
    });
    it('resolveServerBaseUrlReturnsOverrideWhenPresent', 0, () => {
      expect(resolveServerBaseUrl('http://127.0.0.1:8123', 'debug'))
        .assertEqual('http://127.0.0.1:8123');
      expect(resolveServerBaseUrl('http://127.0.0.1:8123', 'release'))
        .assertEqual('http://127.0.0.1:8123');
    });
    it('resolveServerBaseUrlIgnoresEmptyOverride', 0, () => {
      expect(resolveServerBaseUrl('', 'debug')).assertEqual(PROD_BASE_URL);
      expect(resolveServerBaseUrl('', 'release')).assertEqual(PROD_BASE_URL);
    });
    it('resolveServerBaseUrlIgnoresUndefinedOverride', 0, () => {
      expect(resolveServerBaseUrl(undefined, 'debug')).assertEqual(PROD_BASE_URL);
      expect(resolveServerBaseUrl(undefined, 'release')).assertEqual(PROD_BASE_URL);
    });
    it('effectiveServerBaseUrlReadsAppStorageOverride', 0, () => {
      // Sanity: with no override written, production builds land on
      // PROD_BASE_URL. We avoid mutating AppStorage from the unit
      // test process to keep the assertion deterministic across
      // suite ordering — see the beforeAll write in
      // entry/src/ohosTest/ets/test/List.test.ets for the mocked path.
      AppStorage.delete(SERVER_BASE_URL_OVERRIDE_KEY);
      expect(effectiveServerBaseUrl()).assertEqual(PROD_BASE_URL);

      // Write the override and confirm the next read picks it up.
      AppStorage.setOrCreate<string>(
        SERVER_BASE_URL_OVERRIDE_KEY,
        'http://127.0.0.1:8123',
      );
      expect(effectiveServerBaseUrl()).assertEqual('http://127.0.0.1:8123');

      // Clean up so the rest of the unit-test suite stays on PROD.
      AppStorage.delete(SERVER_BASE_URL_OVERRIDE_KEY);
      expect(effectiveServerBaseUrl()).assertEqual(PROD_BASE_URL);
    });
  });
}
