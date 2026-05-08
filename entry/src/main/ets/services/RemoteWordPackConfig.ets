import BuildProfile from 'BuildProfile';

/**
 * V0.7: Remote API base URL routing for word packs and cloud APIs.
 *
 * STAGING_BASE_URL is the default hosted backend (Vercel production deploy).
 * PROD_BASE_URL is reserved for a future dedicated production slot — empty
 * until V0.7+ wires it; resolvers fall back to STAGING_BASE_URL.
 *
 * Debug builds may choose Local / Preview (manual URL or manifest) / Staging
 * via DevMenu (Preferences + AppStorage mirrors). Release builds ignore those
 * prefs and always use STAGING_BASE_URL (or PROD_BASE_URL once non-empty).
 *
 * For real devices on LAN: point LOCAL_BASE_URL at the dev machine IP or USB
 * port forwarding (see project README).
 */
export const LOCAL_BASE_URL: string = 'http://10.0.2.2:8000';
export const STAGING_BASE_URL: string = 'https://happyword.vercel.app';
/** Reserved — empty string means “not configured”; non-empty enables prod routing. */
export const PROD_BASE_URL: string = '';

/**
 * DevMenu preview-manifest fetch origin — **always** the production Vercel app,
 * independent of `BackendEnv`, `effectiveServerBaseUrl()`, preview deployments,
 * or `x-vercel-protection-bypass`. The JSON lists PR preview URLs; the manifest
 * endpoint itself is served from stable prod (`GET /api/v1/preview-urls.json`).
 */
export const PREVIEW_MANIFEST_ORIGIN: string = 'https://happyword.vercel.app';

export const PREVIEW_MANIFEST_JSON_URL: string =
  `${PREVIEW_MANIFEST_ORIGIN}/api/v1/preview-urls.json`;

/** AppStorage mirrors written by BackendEnv — read synchronously by pickServerBaseUrl. */
export const BACKEND_ENV_CACHE_KEY: string = 'backend_env_cache';
export const BACKEND_PREVIEW_URL_CACHE_KEY: string = 'backend_preview_url_cache';
/**
 * Mirror of the user-entered Vercel "Protection Bypass for Automation"
 * secret. Read synchronously by `BackendHeaders.vercelBypassHeader()`
 * so every outgoing request can attach `x-vercel-protection-bypass`
 * without `await`-ing prefs. Only meaningful in debug builds + when
 * env=preview; release builds never write this key.
 */
export const BACKEND_BYPASS_SECRET_CACHE_KEY: string = 'backend_bypass_secret_cache';

/** Cap for a single fetch round-trip; exceeded => fallback to cache. */
export const REMOTE_FETCH_TIMEOUT_MS: number = 8000;

/**
 * Pure picker for tests and DevMenu — env is `local` | `preview` | `staging` | `prod`.
 */
export function pickServerBaseUrlExplicit(
  buildModeName: string,
  env: string,
  previewUrl: string,
): string {
  if (buildModeName !== 'debug') {
    return PROD_BASE_URL.length > 0 ? PROD_BASE_URL : STAGING_BASE_URL;
  }
  if (env === 'local') {
    return LOCAL_BASE_URL;
  }
  if (env === 'preview') {
    return previewUrl.length > 0 ? previewUrl : STAGING_BASE_URL;
  }
  if (env === 'prod') {
    return PROD_BASE_URL.length > 0 ? PROD_BASE_URL : STAGING_BASE_URL;
  }
  return STAGING_BASE_URL;
}

/**
 * Reads persisted backend env from AppStorage mirrors (filled by BackendEnv.init).
 */
export function pickServerBaseUrl(buildModeName: string): string {
  const envRaw: string | undefined = AppStorage.get<string>(BACKEND_ENV_CACHE_KEY);
  const env: string = envRaw ?? '';
  const previewRaw: string | undefined = AppStorage.get<string>(BACKEND_PREVIEW_URL_CACHE_KEY);
  const previewUrl: string = previewRaw ?? '';
  return pickServerBaseUrlExplicit(buildModeName, env, previewUrl);
}

/**
 * AppStorage key set by the ohosTest harness in `List.test.ets`'s
 * `testsuite()` BEFORE any flow runs. When present (non-empty
 * string), `effectiveServerBaseUrl()` routes every HTTP call to the
 * value of this key instead of the prod / dev base URL.
 *
 * Production code MUST NEVER write this key — the only writer is the
 * test runner, so a release build never picks up an override.
 */
export const SERVER_BASE_URL_OVERRIDE_KEY: string = 'serverBaseUrlOverride';

export function resolveServerBaseUrl(
  override: string | undefined,
  buildModeName: string,
): string {
  if (typeof override === 'string' && override.length > 0) {
    return override;
  }
  return pickServerBaseUrl(buildModeName);
}

export function effectiveServerBaseUrl(): string {
  const override: string | undefined =
    AppStorage.get<string>(SERVER_BASE_URL_OVERRIDE_KEY);
  return resolveServerBaseUrl(override, BuildProfile.BUILD_MODE_NAME);
}

export const SERVER_BASE_URL: string = pickServerBaseUrl(BuildProfile.BUILD_MODE_NAME);

export function buildLatestPackUrl(base: string): string {
  if (base.length === 0) {
    return '';
  }
  return `${base}/api/v1/packs/latest.json`;
}

export function latestPackUrl(): string {
  return buildLatestPackUrl(effectiveServerBaseUrl());
}
