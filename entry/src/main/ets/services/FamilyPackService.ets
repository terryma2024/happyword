import preferences from '@ohos.data.preferences';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@ohos.base';
import { StringPreferencesLike } from './WrongAnswerStore';
import { ParentFetchAdapter, ParentFetchResult } from './ParentApiClient';
import { FamilyPacksBlob, parseFamilyPacksBlob } from './FamilyPackMerge';

/**
 * V0.6.3 — client cache + HTTP wrapper for the merged family-pack JSON.
 *
 * The cache lives in its own preferences bag (`wordmagic_family_packs`)
 * so we never mix it with the global `word_pack_cache` slot. A successful
 * `ensureLatest` writes an envelope `{ etag, body, fetchedAtMs }`; a 204
 * clears the slot so the bootstrapper sees no overlay. Network failures
 * fall back to whatever is cached and never throw — the parent's last-known
 * pack is always preferable to silently breaking BattlePage.
 */

const PREFS_NAME: string = 'wordmagic_family_packs';
const KEY_BLOB: string = 'family_packs_v1';

const HEADER_AUTH: string = 'Authorization';
const HEADER_IF_NONE_MATCH: string = 'If-None-Match';
const HEADER_ETAG: string = 'ETag';
const HEADER_ETAG_LOWER: string = 'etag';

class CachedEnvelope {
  etag: string = '';
  body: string = '';
  fetchedAtMs: number = 0;
}

interface RawEnvelope {
  etag?: string;
  body?: string;
  fetchedAtMs?: number;
}

/** HTTP contract — same shape as `ParentFetchAdapter` plus a `head` verb
 *  so the banner-detection path can poll the ETag without pulling the body. */
export interface FamilyPackFetchAdapter extends ParentFetchAdapter {
  head(url: string, headers: Record<string, string>): Promise<ParentFetchResult>;
  /** Optional response-header probe; tests stub by reading the last response.
   *  Returns the value or '' if missing. */
  lastResponseHeader(name: string): string;
}

class RealFamilyPackPrefs implements StringPreferencesLike {
  private readonly handle: preferences.Preferences;
  constructor(handle: preferences.Preferences) {
    this.handle = handle;
  }
  async getString(key: string): Promise<string> {
    try {
      const v: preferences.ValueType = await this.handle.get(key, '');
      return typeof v === 'string' ? v : '';
    } catch (err) {
      console.error(`FamilyPackService.RealFamilyPackPrefs.getString failed: ${JSON.stringify(err as BusinessError)}`);
      return '';
    }
  }
  async putString(key: string, value: string): Promise<void> {
    try {
      await this.handle.put(key, value);
    } catch (err) {
      console.error(`FamilyPackService.RealFamilyPackPrefs.putString failed: ${JSON.stringify(err as BusinessError)}`);
    }
  }
  async flush(): Promise<void> {
    try {
      await this.handle.flush();
    } catch (err) {
      console.error(`FamilyPackService.RealFamilyPackPrefs.flush failed: ${JSON.stringify(err as BusinessError)}`);
    }
  }
}

export class FamilyPackEnsureResult {
  status: 'updated' | 'not_modified' | 'cleared' | 'cached_fallback' | 'no_data' = 'no_data';
  blob: FamilyPacksBlob | null = null;
}

export class FamilyPackService {
  private readonly adapter: FamilyPackFetchAdapter;
  private readonly baseUrl: string;
  private prefs?: StringPreferencesLike;
  private nowMs: () => number = (): number => Date.now();
  private memoryBlob: FamilyPacksBlob | null = null;
  private memoryEnvelope: CachedEnvelope | null = null;

  constructor(adapter: FamilyPackFetchAdapter, baseUrl: string) {
    this.adapter = adapter;
    this.baseUrl = FamilyPackService.trimTrailingSlash(baseUrl);
  }

  injectPreferences(p: StringPreferencesLike): void {
    this.prefs = p;
  }

  injectClock(now: () => number): void {
    this.nowMs = now;
  }

  async init(ctx: common.UIAbilityContext): Promise<void> {
    if (this.prefs !== undefined) {
      return;
    }
    try {
      const real: preferences.Preferences = await preferences.getPreferences(ctx, PREFS_NAME);
      this.prefs = new RealFamilyPackPrefs(real);
    } catch (err) {
      console.error(`FamilyPackService.init failed: ${JSON.stringify(err as BusinessError)}`);
    }
  }

  /** Synchronous read; bootstrapper calls this after `init`. */
  currentBlob(): FamilyPacksBlob | null {
    return this.memoryBlob;
  }

  /** Pre-load the in-memory cache from preferences. Tests call this
   *  manually after injecting their stub. */
  async warmFromCache(): Promise<FamilyPacksBlob | null> {
    const env: CachedEnvelope | null = await this.readCache();
    if (env === null) {
      this.memoryBlob = null;
      this.memoryEnvelope = null;
      return null;
    }
    this.memoryEnvelope = env;
    this.memoryBlob = parseFamilyPacksBlob(env.body, env.etag);
    return this.memoryBlob;
  }

  /** Pull (or revalidate) the latest merged JSON. Never throws. */
  async ensureLatest(deviceToken: string): Promise<FamilyPackEnsureResult> {
    const out: FamilyPackEnsureResult = new FamilyPackEnsureResult();
    if (deviceToken.length === 0) {
      // Unbound; nothing to do.
      out.status = 'no_data';
      return out;
    }
    const url: string = `${this.baseUrl}/api/v1/child/family-packs/latest.json`;
    const headers: Record<string, string> = {};
    headers[HEADER_AUTH] = `Bearer ${deviceToken}`;

    const cached: CachedEnvelope | null = this.memoryEnvelope ?? await this.readCache();
    if (cached !== null && cached.etag.length > 0) {
      headers[HEADER_IF_NONE_MATCH] = cached.etag;
    }

    let res: ParentFetchResult;
    try {
      res = await this.adapter.get(url, headers);
    } catch (_err) {
      // Network error → return cached blob if any.
      out.status = 'cached_fallback';
      out.blob = this.memoryBlob;
      return out;
    }

    if (res.status === 304) {
      out.status = 'not_modified';
      out.blob = this.memoryBlob;
      if (cached !== null) {
        cached.fetchedAtMs = this.nowMs();
        await this.writeCache(cached);
      }
      return out;
    }

    if (res.status === 204) {
      await this.clearCache();
      this.memoryBlob = null;
      this.memoryEnvelope = null;
      out.status = 'cleared';
      out.blob = null;
      return out;
    }

    if (res.status === 200 || res.status === 201) {
      const etagHeader: string = this.adapter.lastResponseHeader(HEADER_ETAG);
      const etagFallback: string = this.adapter.lastResponseHeader(HEADER_ETAG_LOWER);
      const etag: string = etagHeader.length > 0 ? etagHeader : etagFallback;
      const env: CachedEnvelope = new CachedEnvelope();
      env.etag = etag;
      env.body = res.body;
      env.fetchedAtMs = this.nowMs();
      await this.writeCache(env);
      this.memoryEnvelope = env;
      this.memoryBlob = parseFamilyPacksBlob(env.body, env.etag);
      out.status = 'updated';
      out.blob = this.memoryBlob;
      return out;
    }

    // 4xx/5xx → return whatever's cached.
    out.status = 'cached_fallback';
    out.blob = this.memoryBlob;
    return out;
  }

  /** HEAD-only ETag probe. Returns null on error; never throws. */
  async peekRemoteEtag(deviceToken: string): Promise<string | null> {
    if (deviceToken.length === 0) {
      return null;
    }
    const url: string = `${this.baseUrl}/api/v1/child/family-packs/latest.json`;
    const headers: Record<string, string> = {};
    headers[HEADER_AUTH] = `Bearer ${deviceToken}`;
    try {
      const res: ParentFetchResult = await this.adapter.head(url, headers);
      if (res.status === 204) {
        return '';  // Server explicitly says "no packs".
      }
      if (res.status >= 400) {
        return null;
      }
    } catch (_err) {
      return null;
    }
    const etagHeader: string = this.adapter.lastResponseHeader(HEADER_ETAG);
    const etagFallback: string = this.adapter.lastResponseHeader(HEADER_ETAG_LOWER);
    const etag: string = etagHeader.length > 0 ? etagHeader : etagFallback;
    return etag.length > 0 ? etag : null;
  }

  /** True when the server reports a different ETag from what we cached.
   *  Returns false on network error or when both sides agree. */
  async isRemoteStale(deviceToken: string): Promise<boolean> {
    const remote: string | null = await this.peekRemoteEtag(deviceToken);
    if (remote === null) {
      return false;
    }
    const localEtag: string = this.memoryEnvelope?.etag ?? '';
    return remote !== localEtag;
  }

  private async readCache(): Promise<CachedEnvelope | null> {
    if (this.prefs === undefined) {
      return null;
    }
    const raw: string = await this.prefs.getString(KEY_BLOB);
    if (raw.length === 0) {
      return null;
    }
    try {
      const env: RawEnvelope = JSON.parse(raw) as RawEnvelope;
      const out: CachedEnvelope = new CachedEnvelope();
      out.etag = typeof env.etag === 'string' ? env.etag : '';
      out.body = typeof env.body === 'string' ? env.body : '';
      out.fetchedAtMs = typeof env.fetchedAtMs === 'number' ? env.fetchedAtMs : 0;
      return out;
    } catch (_err) {
      return null;
    }
  }

  private async writeCache(env: CachedEnvelope): Promise<void> {
    if (this.prefs === undefined) {
      return;
    }
    const wire: RawEnvelope = { etag: env.etag, body: env.body, fetchedAtMs: env.fetchedAtMs };
    await this.prefs.putString(KEY_BLOB, JSON.stringify(wire));
    await this.prefs.flush();
  }

  private async clearCache(): Promise<void> {
    if (this.prefs === undefined) {
      return;
    }
    await this.prefs.putString(KEY_BLOB, '');
    await this.prefs.flush();
  }

  private static trimTrailingSlash(p: string): string {
    let end: number = p.length;
    while (end > 0 && p.charAt(end - 1) === '/') {
      end -= 1;
    }
    return p.substring(0, end);
  }
}
