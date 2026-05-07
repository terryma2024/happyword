import http from '@ohos.net.http';
import preferences from '@ohos.data.preferences';
import { BusinessError } from '@ohos.base';
import { common } from '@kit.AbilityKit';

const MANIFEST_URL: string =
  'https://raw.githubusercontent.com/terryma2024/happyword/main/docs/preview-urls.json';
const PREFS_NAME: string = 'wm_dev_menu';
const CACHE_KEY: string = 'preview_manifest_cache';
const CACHE_TTL_MS: number = 5 * 60 * 1000;
const SCHEMA_VERSION: number = 1;
const TITLE_MAX: number = 80;
const PREVIEWS_CAP: number = 50;

export interface ManifestRow {
  pr: number;
  title: string;
  branch: string;
  url: string;
  author: string;
  head_sha: string;
  updated_at: string;
}

export interface PreviewManifest {
  schema_version: number;
  updated_at: string;
  previews: ManifestRow[];
}

interface CacheEnvelope {
  fetched_at: number;
  manifest: PreviewManifest;
}

interface RawManifestV1 {
  schema_version?: number;
  updated_at?: string;
  previews?: RawManifestRow[];
}

interface RawManifestRow {
  pr?: number;
  title?: string;
  branch?: string;
  url?: string;
  author?: string;
  head_sha?: string;
  updated_at?: string;
}

function sanitiseTitle(raw: string): string {
  return raw.replace(/[\r\n]+/g, ' ').slice(0, TITLE_MAX);
}

/** Vercel previews use hosts like happyword-git-<branch>-terrymas-projects.vercel.app */
function isValidUrl(url: string): boolean {
  return url.startsWith('https://') && url.endsWith('.vercel.app');
}

export function parseManifest(json: string): PreviewManifest | null {
  let obj: RawManifestV1;
  try {
    obj = JSON.parse(json) as RawManifestV1;
  } catch (err) {
    console.error(`PreviewManifest.parse failed: ${JSON.stringify(err)}`);
    return null;
  }
  if (obj.schema_version !== SCHEMA_VERSION) {
    return null;
  }
  const previews: ManifestRow[] = [];
  const rows: RawManifestRow[] | undefined = obj.previews;
  if (rows !== undefined) {
    for (let i = 0; i < rows.length; i++) {
      const r: RawManifestRow = rows[i];
      if (typeof r.pr !== 'number' || typeof r.title !== 'string' || typeof r.branch !== 'string'
        || typeof r.url !== 'string' || typeof r.author !== 'string'
        || typeof r.head_sha !== 'string' || typeof r.updated_at !== 'string') {
        continue;
      }
      if (!isValidUrl(r.url)) {
        continue;
      }
      previews.push({
        pr: r.pr,
        title: sanitiseTitle(r.title),
        branch: r.branch,
        url: r.url,
        author: r.author,
        head_sha: r.head_sha,
        updated_at: r.updated_at,
      });
    }
  }
  const updatedAt: string = typeof obj.updated_at === 'string' ? obj.updated_at : '';
  return {
    schema_version: SCHEMA_VERSION,
    updated_at: updatedAt,
    previews: previews.slice(0, PREVIEWS_CAP),
  };
}

let prefsHandle: preferences.Preferences | null = null;
let memCache: CacheEnvelope | null = null;

export async function initPreviewManifestService(ctx: common.UIAbilityContext): Promise<void> {
  if (prefsHandle === null) {
    try {
      prefsHandle = await preferences.getPreferences(ctx, PREFS_NAME);
    } catch (err) {
      console.error(`PreviewManifest.init failed: ${JSON.stringify(err as BusinessError)}`);
    }
  }
  if (memCache === null && prefsHandle !== null) {
    try {
      const raw: preferences.ValueType = await prefsHandle.get(CACHE_KEY, '');
      if (typeof raw === 'string' && raw.length > 0) {
        const parsed: CacheEnvelope = JSON.parse(raw) as CacheEnvelope;
        memCache = parsed;
      }
    } catch (err) {
      console.error(`PreviewManifest.loadCache failed: ${JSON.stringify(err)}`);
    }
  }
}

export function getCached(): PreviewManifest | null {
  return memCache?.manifest ?? null;
}

export async function fetchManifest(force: boolean): Promise<PreviewManifest | null> {
  const now: number = Date.now();
  if (!force && memCache !== null && (now - memCache.fetched_at) < CACHE_TTL_MS) {
    return memCache.manifest;
  }
  const req: http.HttpRequest = http.createHttp();
  try {
    const resp: http.HttpResponse = await req.request(MANIFEST_URL, {
      method: http.RequestMethod.GET,
      readTimeout: 5000,
      connectTimeout: 5000,
    });
    if (resp.responseCode !== 200 || typeof resp.result !== 'string') {
      return memCache?.manifest ?? null;
    }
    const parsed: PreviewManifest | null = parseManifest(resp.result as string);
    if (parsed === null) {
      return memCache?.manifest ?? null;
    }
    memCache = { fetched_at: now, manifest: parsed };
    if (prefsHandle !== null) {
      try {
        await prefsHandle.put(CACHE_KEY, JSON.stringify(memCache));
        await prefsHandle.flush();
      } catch (err) {
        console.error(`PreviewManifest.saveCache failed: ${JSON.stringify(err)}`);
      }
    }
    return parsed;
  } catch (err) {
    console.error(`PreviewManifest.fetch network error: ${JSON.stringify(err)}`);
    return memCache?.manifest ?? null;
  } finally {
    req.destroy();
  }
}
