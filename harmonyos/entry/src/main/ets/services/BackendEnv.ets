import preferences from '@ohos.data.preferences';
import { BusinessError } from '@ohos.base';
import { common } from '@kit.AbilityKit';
import {
  BACKEND_BYPASS_SECRET_CACHE_KEY,
  BACKEND_DEBUG_SESSION_CACHE_KEY,
  BACKEND_ENV_CACHE_KEY,
  BACKEND_PREVIEW_URL_CACHE_KEY,
  LOCAL_BASE_URL,
  PROD_BASE_URL,
  STAGING_BASE_URL,
} from './RemoteWordPackConfig';

const PREFS_NAME: string = 'wm_dev_menu';
const KEY_ENV: string = 'backend_env';
const KEY_PREVIEW_URL: string = 'backend_preview_url';
const KEY_HISTORY: string = 'backend_preview_history';
const KEY_AUDIT: string = 'dev_menu_audit';
/**
 * Vercel "Protection Bypass for Automation" secret entered via the
 * DevMenu Preview-card prompt. Mirrored to AppStorage on init so any
 * outgoing request to a Preview deployment can attach the
 * `x-vercel-protection-bypass` header synchronously. Persists across
 * app relaunches; cleared only when the user explicitly re-enters or
 * via a future "clear bypass secret" action (not yet wired).
 */
const KEY_BYPASS_SECRET: string = 'backend_bypass_secret';
const KEY_DEBUG_SESSION: string = 'backend_debug_session';

const HISTORY_CAP: number = 5;
const AUDIT_CAP: number = 50;

export enum BackendEnv {
  LOCAL = 'local',
  PREVIEW = 'preview',
  STAGING = 'staging',
  PROD = 'prod',
}

export interface BackendEnvMeta {
  env: BackendEnv;
  label: string;
  description: string;
  defaultUrl: string;
  allowsCustomUrl: boolean;
  enabledInDebug: boolean;
  enabledInRelease: boolean;
}

export interface AuditRow {
  ts: number;
  from: string;
  to: string;
  preview_url: string;
}

let prefsHandle: preferences.Preferences | null = null;

function prodConfigured(): boolean {
  return PROD_BASE_URL.length > 0;
}

export function metaFor(env: BackendEnv): BackendEnvMeta {
  switch (env) {
    case BackendEnv.LOCAL:
      return {
        env: BackendEnv.LOCAL,
        label: 'Local',
        description: LOCAL_BASE_URL,
        defaultUrl: LOCAL_BASE_URL,
        allowsCustomUrl: false,
        enabledInDebug: true,
        enabledInRelease: false,
      };
    case BackendEnv.PREVIEW:
      return {
        env: BackendEnv.PREVIEW,
        label: 'Preview',
        description: 'Pick from manifest or paste URL',
        defaultUrl: '',
        allowsCustomUrl: true,
        enabledInDebug: true,
        enabledInRelease: false,
      };
    case BackendEnv.STAGING:
      return {
        env: BackendEnv.STAGING,
        label: 'Staging',
        description: STAGING_BASE_URL,
        defaultUrl: STAGING_BASE_URL,
        allowsCustomUrl: false,
        enabledInDebug: true,
        enabledInRelease: true,
      };
    case BackendEnv.PROD:
      return {
        env: BackendEnv.PROD,
        label: 'Production',
        description: prodConfigured() ? PROD_BASE_URL : '(disabled)',
        defaultUrl: PROD_BASE_URL,
        allowsCustomUrl: false,
        enabledInDebug: prodConfigured(),
        enabledInRelease: prodConfigured(),
      };
    default:
      return metaFor(BackendEnv.STAGING);
  }
}

export function enabledEnvsForBuildMode(buildMode: string): BackendEnv[] {
  const out: BackendEnv[] = [];
  if (buildMode !== 'debug') {
    out.push(BackendEnv.STAGING);
    return out;
  }
  out.push(BackendEnv.LOCAL);
  out.push(BackendEnv.PREVIEW);
  out.push(BackendEnv.STAGING);
  if (prodConfigured()) {
    out.push(BackendEnv.PROD);
  }
  return out;
}

export function pushHistory(prev: string[], url: string): string[] {
  const filtered: string[] = prev.filter((x: string) => x !== url);
  filtered.unshift(url);
  return filtered.slice(0, HISTORY_CAP);
}

export function trimAuditLog(prev: object[], cap: number = AUDIT_CAP): object[] {
  if (prev.length <= cap) {
    return prev;
  }
  return prev.slice(prev.length - cap);
}

export async function initBackendEnvPrefs(ctx: common.UIAbilityContext): Promise<void> {
  if (prefsHandle !== null) {
    return;
  }
  try {
    prefsHandle = await preferences.getPreferences(ctx, PREFS_NAME);
    const envVt: preferences.ValueType = await prefsHandle.get(KEY_ENV, BackendEnv.STAGING);
    const urlVt: preferences.ValueType = await prefsHandle.get(KEY_PREVIEW_URL, '');
    const secretVt: preferences.ValueType = await prefsHandle.get(KEY_BYPASS_SECRET, '');
    const debugSessionVt: preferences.ValueType = await prefsHandle.get(KEY_DEBUG_SESSION, '');
    const envStr: string = typeof envVt === 'string' ? envVt : BackendEnv.STAGING;
    const urlStr: string = typeof urlVt === 'string' ? urlVt : '';
    const secretStr: string = typeof secretVt === 'string' ? secretVt : '';
    const debugSessionStr: string = typeof debugSessionVt === 'string' ? debugSessionVt : '';
    AppStorage.setOrCreate<string>(BACKEND_ENV_CACHE_KEY, envStr);
    AppStorage.setOrCreate<string>(BACKEND_PREVIEW_URL_CACHE_KEY, urlStr);
    AppStorage.setOrCreate<string>(BACKEND_BYPASS_SECRET_CACHE_KEY, secretStr);
    AppStorage.setOrCreate<string>(BACKEND_DEBUG_SESSION_CACHE_KEY, debugSessionStr);
  } catch (err) {
    console.error(`BackendEnv.initPrefs failed: ${JSON.stringify(err as BusinessError)}`);
    AppStorage.setOrCreate<string>(BACKEND_ENV_CACHE_KEY, BackendEnv.STAGING);
    AppStorage.setOrCreate<string>(BACKEND_PREVIEW_URL_CACHE_KEY, '');
    AppStorage.setOrCreate<string>(BACKEND_BYPASS_SECRET_CACHE_KEY, '');
    AppStorage.setOrCreate<string>(BACKEND_DEBUG_SESSION_CACHE_KEY, '');
  }
}

async function putAndFlush(key: string, value: string): Promise<void> {
  if (prefsHandle === null) {
    return;
  }
  try {
    await prefsHandle.put(key, value);
    await prefsHandle.flush();
  } catch (err) {
    console.error(`BackendEnv.put(${key}) failed: ${JSON.stringify(err as BusinessError)}`);
  }
}

export async function loadBackendEnv(): Promise<BackendEnv> {
  if (prefsHandle === null) {
    return BackendEnv.STAGING;
  }
  try {
    const raw: preferences.ValueType = await prefsHandle.get(KEY_ENV, BackendEnv.STAGING);
    const s: string = typeof raw === 'string' ? raw : BackendEnv.STAGING;
    if (s === BackendEnv.LOCAL || s === BackendEnv.PREVIEW || s === BackendEnv.STAGING || s === BackendEnv.PROD) {
      return s as BackendEnv;
    }
  } catch (err) {
    console.error(`BackendEnv.loadBackendEnv failed: ${JSON.stringify(err as BusinessError)}`);
  }
  return BackendEnv.STAGING;
}

export async function saveBackendEnv(env: BackendEnv): Promise<void> {
  await putAndFlush(KEY_ENV, env);
  AppStorage.setOrCreate<string>(BACKEND_ENV_CACHE_KEY, env);
}

export async function loadPreviewUrl(): Promise<string> {
  if (prefsHandle === null) {
    return '';
  }
  try {
    const raw: preferences.ValueType = await prefsHandle.get(KEY_PREVIEW_URL, '');
    return typeof raw === 'string' ? raw : '';
  } catch (err) {
    console.error(`BackendEnv.loadPreviewUrl failed: ${JSON.stringify(err as BusinessError)}`);
    return '';
  }
}

export async function savePreviewUrl(url: string): Promise<void> {
  await putAndFlush(KEY_PREVIEW_URL, url);
  AppStorage.setOrCreate<string>(BACKEND_PREVIEW_URL_CACHE_KEY, url);
}

/**
 * Read the persisted Vercel bypass-secret. Returns '' when prefs
 * aren't initialised yet (boot races) or when the user has never
 * entered one. The DevMenu uses '' as the trigger for "open prompt".
 */
export async function loadBypassSecret(): Promise<string> {
  if (prefsHandle === null) {
    return '';
  }
  try {
    const raw: preferences.ValueType = await prefsHandle.get(KEY_BYPASS_SECRET, '');
    return typeof raw === 'string' ? raw : '';
  } catch (err) {
    console.error(`BackendEnv.loadBypassSecret failed: ${JSON.stringify(err as BusinessError)}`);
    return '';
  }
}

/**
 * Persist the Vercel bypass-secret and update the AppStorage mirror so
 * subsequent HTTP calls pick it up immediately (no relaunch needed).
 * Saving '' acts as a "clear" — useful if we ever wire a "forget
 * bypass secret" action into the DevMenu.
 */
export async function saveBypassSecret(secret: string): Promise<void> {
  await putAndFlush(KEY_BYPASS_SECRET, secret);
  AppStorage.setOrCreate<string>(BACKEND_BYPASS_SECRET_CACHE_KEY, secret);
}

export async function loadDebugSessionId(): Promise<string> {
  if (prefsHandle === null) {
    return '';
  }
  try {
    const raw: preferences.ValueType = await prefsHandle.get(KEY_DEBUG_SESSION, '');
    return typeof raw === 'string' ? raw : '';
  } catch (err) {
    console.error(`BackendEnv.loadDebugSessionId failed: ${JSON.stringify(err as BusinessError)}`);
    return '';
  }
}

export async function saveDebugSessionId(sessionId: string): Promise<void> {
  await putAndFlush(KEY_DEBUG_SESSION, sessionId.trim());
  AppStorage.setOrCreate<string>(BACKEND_DEBUG_SESSION_CACHE_KEY, sessionId.trim());
}

export async function loadHistory(): Promise<string[]> {
  if (prefsHandle === null) {
    return [];
  }
  try {
    const raw: preferences.ValueType = await prefsHandle.get(KEY_HISTORY, '[]');
    const txt: string = typeof raw === 'string' ? raw : '[]';
    const parsed: object = JSON.parse(txt) as object;
    if (Array.isArray(parsed)) {
      return (parsed as string[]).filter((x: string) => typeof x === 'string');
    }
  } catch (err) {
    console.error(`BackendEnv.loadHistory failed: ${JSON.stringify(err)}`);
  }
  return [];
}

export async function saveHistory(history: string[]): Promise<void> {
  await putAndFlush(KEY_HISTORY, JSON.stringify(history));
}

export async function loadAuditLog(): Promise<AuditRow[]> {
  if (prefsHandle === null) {
    return [];
  }
  try {
    const raw: preferences.ValueType = await prefsHandle.get(KEY_AUDIT, '[]');
    const txt: string = typeof raw === 'string' ? raw : '[]';
    const parsed: object = JSON.parse(txt) as object;
    if (Array.isArray(parsed)) {
      return parsed as AuditRow[];
    }
  } catch (err) {
    console.error(`BackendEnv.loadAuditLog failed: ${JSON.stringify(err)}`);
  }
  return [];
}

export async function appendAuditLog(row: AuditRow): Promise<void> {
  const prev: AuditRow[] = await loadAuditLog();
  prev.push(row);
  const trimmed: AuditRow[] = trimAuditLog(prev) as AuditRow[];
  await putAndFlush(KEY_AUDIT, JSON.stringify(trimmed));
}
