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

/** Effective base URL for this build (read once at module load). */
export const SERVER_BASE_URL: string = pickServerBaseUrl(BuildProfile.BUILD_MODE_NAME);

/** Compose the full /packs/latest.json URL on top of any base. */
export function buildLatestPackUrl(base: string): string {
  if (base.length === 0) {
    return '';
  }
  return `${base}/api/v1/packs/latest.json`;
}

/** Convenience: full URL for this build mode. */
export function latestPackUrl(): string {
  return buildLatestPackUrl(SERVER_BASE_URL);
}
