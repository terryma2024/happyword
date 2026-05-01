import BuildProfile from 'BuildProfile';

/**
 * V0.5.1: server base URL for the remote word pack.
 *
 * Default routing: BOTH debug and release builds hit `PROD_BASE_URL`
 * (https://happyword.vercel.app). This makes the cold-start path
 * exercise the real production round-trip every time, which is what
 * the V0.5.1 walking skeleton needs to verify.
 *
 * When you start V0.5.2+ work that actually iterates on a local
 * FastAPI server, flip `USE_LOCAL_DEV_SERVER` to `true` below. With
 * that toggle on, debug builds route to `DEV_BASE_URL`
 * (`http://10.0.2.2:8000` — the emulator's host loopback) while
 * release builds keep hitting prod. Remember to flip it back to
 * `false` before tagging another release.
 *
 * For real devices on LAN: change `DEV_BASE_URL` to the dev
 * machine's LAN IP (e.g. `http://192.168.1.100:8000`). For USB
 * `hdc fport tcp:8000 tcp:8000`, change to `http://127.0.0.1:8000`.
 */
export const DEV_BASE_URL: string = 'http://10.0.2.2:8000';
export const PROD_BASE_URL: string = 'https://happyword.vercel.app';

/** One-line toggle: set to `true` only when actively iterating on the local FastAPI server. */
export const USE_LOCAL_DEV_SERVER: boolean = false;

/** Cap for a single fetch round-trip; exceeded => fallback to cache. */
export const REMOTE_FETCH_TIMEOUT_MS: number = 8000;

/**
 * Pure picker that takes the toggle value explicitly. Tests use this
 * to cover both states without mutating the module-level constant.
 *
 * Rule:
 *   - useLocalDevServer && buildModeName === 'debug'  -> DEV_BASE_URL
 *   - everything else (release, unknown modes, toggle off)  -> PROD_BASE_URL
 */
export function pickServerBaseUrlExplicit(
  buildModeName: string,
  useLocalDevServer: boolean,
): string {
  if (useLocalDevServer && buildModeName === 'debug') {
    return DEV_BASE_URL;
  }
  return PROD_BASE_URL;
}

/**
 * Production picker: applies the module-level USE_LOCAL_DEV_SERVER
 * constant. Kept as a thin wrapper so module bootstrap stays a
 * single function call and call-sites don't have to know about the
 * toggle.
 */
export function pickServerBaseUrl(buildModeName: string): string {
  return pickServerBaseUrlExplicit(buildModeName, USE_LOCAL_DEV_SERVER);
}

/**
 * AppStorage key set by the ohosTest harness in `List.test.ets`'s
 * `testsuite()` BEFORE any flow runs. When present (non-empty
 * string), `effectiveServerBaseUrl()` routes every HTTP call to the
 * value of this key instead of the prod / dev base URL.
 *
 * Production code MUST NEVER write this key — the only writer is the
 * test runner, so a release build never picks up an override. We keep
 * the key intentionally namespaced to make grep audits trivial.
 */
export const SERVER_BASE_URL_OVERRIDE_KEY: string = 'serverBaseUrlOverride';

/**
 * Pure resolver — given an override candidate and a build mode, decide
 * which URL wins. Tests cover both branches without touching
 * AppStorage directly.
 */
export function resolveServerBaseUrl(
  override: string | undefined,
  buildModeName: string,
): string {
  if (typeof override === 'string' && override.length > 0) {
    return override;
  }
  return pickServerBaseUrl(buildModeName);
}

/**
 * Runtime base URL. Reads the AppStorage override on every call so
 * the ohosTest harness can flip the value before any page is mounted.
 * Production code never sets the override and lands on the same
 * `pickServerBaseUrl(buildMode)` path it had before.
 */
export function effectiveServerBaseUrl(): string {
  const override: string | undefined =
    AppStorage.get<string>(SERVER_BASE_URL_OVERRIDE_KEY);
  return resolveServerBaseUrl(override, BuildProfile.BUILD_MODE_NAME);
}

/**
 * Default base URL captured at module load — purely for backward
 * compatibility with code that imported `SERVER_BASE_URL` before the
 * V0.5.8 ohosTest mock-injection landed. New call-sites should use
 * `effectiveServerBaseUrl()` so they pick up the override.
 */
export const SERVER_BASE_URL: string = pickServerBaseUrl(BuildProfile.BUILD_MODE_NAME);

/** Compose the full /packs/latest.json URL on top of any base. */
export function buildLatestPackUrl(base: string): string {
  if (base.length === 0) {
    return '';
  }
  return `${base}/api/v1/packs/latest.json`;
}

/** Convenience: full URL for this build mode (honours override). */
export function latestPackUrl(): string {
  return buildLatestPackUrl(effectiveServerBaseUrl());
}
