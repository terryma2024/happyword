import { describe, it, expect } from '@ohos/hypium';
import {
  pickServerBaseUrl,
  pickServerBaseUrlExplicit,
  buildLatestPackUrl,
  resolveServerBaseUrl,
  effectiveServerBaseUrl,
  SERVER_BASE_URL_OVERRIDE_KEY,
  LOCAL_BASE_URL,
  STAGING_BASE_URL,
  PROD_BASE_URL,
  PREVIEW_MANIFEST_ORIGIN,
  PREVIEW_MANIFEST_JSON_URL,
  BACKEND_ENV_CACHE_KEY,
  BACKEND_PREVIEW_URL_CACHE_KEY,
} from '../main/ets/services/RemoteWordPackConfig';

export default function remoteWordPackConfigTest() {
  describe('RemoteWordPackConfig', () => {
    it('localUrlIsEmulatorHostLoopback', 0, () => {
      expect(LOCAL_BASE_URL).assertEqual('http://10.0.2.2:8000');
    });
    it('stagingUrlIsVercelDomain', 0, () => {
      expect(STAGING_BASE_URL).assertEqual('https://happyword.vercel.app');
    });
    it('previewManifestAlwaysUsesProdOriginNotBackendEnv', 0, () => {
      expect(PREVIEW_MANIFEST_ORIGIN).assertEqual('https://happyword.vercel.app');
      expect(PREVIEW_MANIFEST_JSON_URL).assertEqual(
        'https://happyword.vercel.app/api/v1/preview-urls.json',
      );
    });
    it('prodUrlReservedEmpty', 0, () => {
      expect(PROD_BASE_URL === '').assertTrue();
    });

    it('releaseAlwaysLandsOnStagingWhenProdUnset', 0, () => {
      expect(pickServerBaseUrlExplicit('release', '', '')).assertEqual(STAGING_BASE_URL);
      expect(pickServerBaseUrlExplicit('release', 'local', '')).assertEqual(STAGING_BASE_URL);
      expect(pickServerBaseUrlExplicit('release', 'preview', 'http://x')).assertEqual(STAGING_BASE_URL);
    });
    it('debugWithEmptyEnvDefaultsToStaging', 0, () => {
      expect(pickServerBaseUrlExplicit('debug', '', '')).assertEqual(STAGING_BASE_URL);
    });
    it('debugLocalReturnsLocalUrl', 0, () => {
      expect(pickServerBaseUrlExplicit('debug', 'local', '')).assertEqual(LOCAL_BASE_URL);
    });
    it('debugPreviewWithUrlReturnsPreviewUrl', 0, () => {
      expect(pickServerBaseUrlExplicit('debug', 'preview', 'https://pr-42.vercel.app'))
        .assertEqual('https://pr-42.vercel.app');
    });
    it('debugPreviewWithEmptyFallsBackToStaging', 0, () => {
      expect(pickServerBaseUrlExplicit('debug', 'preview', '')).assertEqual(STAGING_BASE_URL);
    });
    it('debugProdFallsBackToStagingUntilProdIsLive', 0, () => {
      expect(pickServerBaseUrlExplicit('debug', 'prod', '')).assertEqual(STAGING_BASE_URL);
    });

    it('overrideKeyIsStableForGrep', 0, () => {
      expect(SERVER_BASE_URL_OVERRIDE_KEY).assertEqual('serverBaseUrlOverride');
    });
    it('resolveServerBaseUrlReturnsOverrideWhenPresent', 0, () => {
      expect(resolveServerBaseUrl('http://127.0.0.1:8123', 'debug'))
        .assertEqual('http://127.0.0.1:8123');
      expect(resolveServerBaseUrl('http://127.0.0.1:8123', 'release'))
        .assertEqual('http://127.0.0.1:8123');
    });
    it('resolveServerBaseUrlIgnoresEmptyOverride', 0, () => {
      AppStorage.delete(BACKEND_ENV_CACHE_KEY);
      AppStorage.delete(BACKEND_PREVIEW_URL_CACHE_KEY);
      expect(resolveServerBaseUrl('', 'debug')).assertEqual(STAGING_BASE_URL);
      expect(resolveServerBaseUrl('', 'release')).assertEqual(STAGING_BASE_URL);
    });
    it('resolveServerBaseUrlIgnoresUndefinedOverride', 0, () => {
      AppStorage.delete(BACKEND_ENV_CACHE_KEY);
      AppStorage.delete(BACKEND_PREVIEW_URL_CACHE_KEY);
      expect(resolveServerBaseUrl(undefined, 'debug')).assertEqual(STAGING_BASE_URL);
      expect(resolveServerBaseUrl(undefined, 'release')).assertEqual(STAGING_BASE_URL);
    });

    it('effectiveServerBaseUrlReadsAppStorageOverride', 0, () => {
      AppStorage.delete(SERVER_BASE_URL_OVERRIDE_KEY);
      AppStorage.delete(BACKEND_ENV_CACHE_KEY);
      AppStorage.delete(BACKEND_PREVIEW_URL_CACHE_KEY);
      expect(effectiveServerBaseUrl()).assertEqual(STAGING_BASE_URL);
      AppStorage.setOrCreate<string>(SERVER_BASE_URL_OVERRIDE_KEY, 'http://127.0.0.1:8123');
      expect(effectiveServerBaseUrl()).assertEqual('http://127.0.0.1:8123');
      AppStorage.delete(SERVER_BASE_URL_OVERRIDE_KEY);
      expect(effectiveServerBaseUrl()).assertEqual(STAGING_BASE_URL);
    });

    it('debugLocalEnvFromAppStorageRoutesToLocalUrl', 0, () => {
      AppStorage.delete(SERVER_BASE_URL_OVERRIDE_KEY);
      AppStorage.setOrCreate<string>(BACKEND_ENV_CACHE_KEY, 'local');
      AppStorage.setOrCreate<string>(BACKEND_PREVIEW_URL_CACHE_KEY, '');
      expect(pickServerBaseUrl('debug')).assertEqual(LOCAL_BASE_URL);
      AppStorage.delete(BACKEND_ENV_CACHE_KEY);
      AppStorage.delete(BACKEND_PREVIEW_URL_CACHE_KEY);
    });

    it('buildLatestPackUrlAppendsCorrectPath', 0, () => {
      expect(buildLatestPackUrl(STAGING_BASE_URL))
        .assertEqual('https://happyword.vercel.app/api/v1/packs/latest.json');
    });
    it('buildLatestPackUrlReturnsEmptyForEmptyBase', 0, () => {
      expect(buildLatestPackUrl('')).assertEqual('');
    });
  });
}
