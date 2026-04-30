import BuildProfile from 'BuildProfile';

/**
 * V0.5.1: server base URL for the remote word pack.
 *
 * Switch is driven by hvigor's auto-generated `BuildProfile.BUILD_MODE_NAME`
 * (`'debug'` for `assembleHap` default, `'release'` for the `release`
 * buildOptionSet). Production builds always hit Vercel; debug builds hit
 * the emulator host loopback so the FastAPI server running on the dev
 * machine is reachable from the HarmonyOS emulator without a tunnel.
 *
 * If you switch to a real device on LAN, change `DEV_BASE_URL` to the dev
 * machine's LAN IP (e.g. `http://192.168.1.100:8000`). If you use
 * `hdc fport tcp:8000 tcp:8000`, change to `http://127.0.0.1:8000`.
 */
export const DEV_BASE_URL: string = 'http://10.0.2.2:8000';
export const PROD_BASE_URL: string = 'https://happyword.vercel.app';

/** Cap for a single fetch round-trip; exceeded => fallback to cache. */
export const REMOTE_FETCH_TIMEOUT_MS: number = 8000;

/**
 * Pure function: pick the appropriate base URL given a build mode name.
 * 'debug' -> DEV; everything else (including 'release' and unknown) -> PROD.
 * Kept pure so unit tests cover every branch without touching BuildProfile.
 */
export function pickServerBaseUrl(buildModeName: string): string {
  if (buildModeName === 'debug') {
    return DEV_BASE_URL;
  }
  return PROD_BASE_URL;
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
