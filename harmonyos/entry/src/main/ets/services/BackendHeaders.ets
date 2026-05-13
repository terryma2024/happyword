import { BackendEnv } from './BackendEnv';
import {
  BACKEND_BYPASS_SECRET_CACHE_KEY,
  BACKEND_DEBUG_SESSION_CACHE_KEY,
  BACKEND_ENV_CACHE_KEY,
} from './RemoteWordPackConfig';

/**
 * V0.6.2 — Vercel "Protection Bypass for Automation" header support.
 *
 * Vercel preview deployments default to auth-gated (Deployment
 * Protection): every API call is intercepted at the edge with HTTP
 * 401 + an HTML SSO page UNLESS the request carries the per-project
 * `x-vercel-protection-bypass: <secret>` header.
 *
 * This mirrors the server-side e2e driver pattern in
 * `server/tests/e2e/_utils/vercel.py` — the only difference is where
 * the secret comes from. The driver reads it from the
 * `E2E_VERCEL_PROTECTION_BYPASS` env var; the on-device DevMenu
 * prompts the user for it the first time they tap a Preview card and
 * persists it via `BackendEnv.saveBypassSecret`.
 *
 * The header is attached ONLY when:
 *   - active env is `BackendEnv.PREVIEW` (Local / Staging / Prod
 *     never need it; Local hits LAN, Staging/Prod hit unprotected
 *     deployments).
 *   - the secret has been entered (non-empty AppStorage mirror).
 *
 * Release builds never write the bypass-secret pref so the helper is
 * a no-op there (env is always Staging/Prod and the secret AppStorage
 * mirror is empty). This means it's safe to call from production code
 * paths uniformly without an explicit BUILD_MODE_NAME guard.
 *
 * Docs:
 *   https://vercel.com/docs/deployment-protection/methods-to-bypass-deployment-protection/protection-bypass-automation
 */

/** HTTP header name Vercel checks for the bypass secret. */
export const VERCEL_BYPASS_HEADER: string = 'x-vercel-protection-bypass';
export const DEBUG_SESSION_HEADER: string = 'x-hw-debug-session';

/**
 * Pure helper — exposed for unit tests. Returns the bypass header dict
 * (or empty) given the active env and stored secret. Mirrors the
 * server e2e helper's branch logic so the on-device behavior is
 * trivially auditable against the test driver.
 */
export function buildVercelBypassHeader(
  env: string,
  secret: string,
): Record<string, string> {
  if (env !== BackendEnv.PREVIEW) {
    return {};
  }
  if (secret.length === 0) {
    return {};
  }
  const out: Record<string, string> = {};
  out[VERCEL_BYPASS_HEADER] = secret;
  return out;
}

/**
 * AppStorage-backed wrapper. Reads the env + secret synchronously
 * from the mirrors populated by `initBackendEnvPrefs`. Safe to call
 * from any HTTP call site without `await`.
 */
export function vercelBypassHeader(): Record<string, string> {
  const envRaw: string | undefined = AppStorage.get<string>(BACKEND_ENV_CACHE_KEY);
  const env: string = envRaw ?? '';
  const secretRaw: string | undefined = AppStorage.get<string>(BACKEND_BYPASS_SECRET_CACHE_KEY);
  const secret: string = secretRaw ?? '';
  return buildVercelBypassHeader(env, secret);
}

export function debugSessionHeader(): Record<string, string> {
  const envRaw: string | undefined = AppStorage.get<string>(BACKEND_ENV_CACHE_KEY);
  const env: string = envRaw ?? '';
  if (env !== BackendEnv.PREVIEW) {
    return {};
  }
  const sessionRaw: string | undefined = AppStorage.get<string>(BACKEND_DEBUG_SESSION_CACHE_KEY);
  const sessionId: string = (sessionRaw ?? '').trim();
  if (sessionId.length === 0) {
    return {};
  }
  const out: Record<string, string> = {};
  out[DEBUG_SESSION_HEADER] = sessionId;
  return out;
}

/**
 * Pure helper — merges two header dicts, with `extra` taking
 * precedence on key collision. Exposed so unit tests can verify
 * collision handling without touching AppStorage.
 */
export function mergeHeaders(
  base: Record<string, string>,
  extra: Record<string, string>,
): Record<string, string> {
  const out: Record<string, string> = {};
  const baseKeys: string[] = Object.keys(base);
  for (let i = 0; i < baseKeys.length; i++) {
    const k: string = baseKeys[i];
    out[k] = base[k];
  }
  const extraKeys: string[] = Object.keys(extra);
  for (let i = 0; i < extraKeys.length; i++) {
    const k: string = extraKeys[i];
    out[k] = extra[k];
  }
  return out;
}

/**
 * Convenience — most call sites already build a `Record<string, string>`
 * and just want "add the bypass header if relevant". Returns a NEW
 * dict so the caller's local doesn't get mutated.
 */
export function withBypassHeaders(
  base: Record<string, string>,
): Record<string, string> {
  const extra: Record<string, string> = mergeHeaders(vercelBypassHeader(), debugSessionHeader());
  if (Object.keys(extra).length === 0) {
    return base;
  }
  return mergeHeaders(base, extra);
}
