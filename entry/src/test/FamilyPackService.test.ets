import { describe, it, expect } from '@ohos/hypium';
import { FamilyPackEnsureResult, FamilyPackFetchAdapter, FamilyPackService } from '../main/ets/services/FamilyPackService';
import { ParentFetchResult } from '../main/ets/services/ParentApiClient';
import { StringPreferencesLike } from '../main/ets/services/WrongAnswerStore';

class StubAdapter implements FamilyPackFetchAdapter {
  responses: Map<string, ParentFetchResult> = new Map<string, ParentFetchResult>();
  responseHeaders: Map<string, Record<string, string>> = new Map<string, Record<string, string>>();
  errorOn: Set<string> = new Set<string>();
  lastUrl: string = '';
  lastHeaders: Record<string, string> = {};
  lastMethod: string = '';
  private currentHeaders: Record<string, string> = {};

  async get(url: string, headers: Record<string, string>): Promise<ParentFetchResult> {
    return this.serve('GET', url, headers, '');
  }
  async post(url: string, headers: Record<string, string>, body: string): Promise<ParentFetchResult> {
    return this.serve('POST', url, headers, body);
  }
  async put(url: string, headers: Record<string, string>, body: string): Promise<ParentFetchResult> {
    return this.serve('PUT', url, headers, body);
  }
  async patch(url: string, headers: Record<string, string>, body: string): Promise<ParentFetchResult> {
    return this.serve('PATCH', url, headers, body);
  }
  async del(url: string, headers: Record<string, string>): Promise<ParentFetchResult> {
    return this.serve('DELETE', url, headers, '');
  }
  async head(url: string, headers: Record<string, string>): Promise<ParentFetchResult> {
    return this.serve('HEAD', url, headers, '');
  }

  lastResponseHeader(name: string): string {
    return this.currentHeaders[name] !== undefined ? this.currentHeaders[name] : '';
  }

  private serve(
    method: string,
    url: string,
    headers: Record<string, string>,
    _body: string,
  ): ParentFetchResult {
    this.lastMethod = method;
    this.lastUrl = url;
    this.lastHeaders = headers;
    if (this.errorOn.has(`${method} ${url}`)) {
      throw new Error('stub-network-error');
    }
    const key: string = `${method} ${url}`;
    const r: ParentFetchResult | undefined = this.responses.get(key);
    if (r === undefined) {
      const fallback: ParentFetchResult = new ParentFetchResult();
      fallback.status = 500;
      return fallback;
    }
    this.currentHeaders = this.responseHeaders.get(key) !== undefined
      ? this.responseHeaders.get(key) as Record<string, string>
      : {};
    return r;
  }
}

class MemPrefs implements StringPreferencesLike {
  store: Record<string, string> = {};
  async getString(key: string): Promise<string> {
    return this.store[key] !== undefined ? this.store[key] : '';
  }
  async putString(key: string, value: string): Promise<void> {
    this.store[key] = value;
  }
  async flush(): Promise<void> {
    // no-op
  }
}

const BASE: string = 'https://happyword.vercel.app';
const URL_LATEST: string = `${BASE}/api/v1/child/family-packs/latest.json`;
const TOKEN: string = 'device.jwt.token';

function ok(body: string): ParentFetchResult {
  const r: ParentFetchResult = new ParentFetchResult();
  r.status = 200;
  r.body = body;
  return r;
}

function status(code: number): ParentFetchResult {
  const r: ParentFetchResult = new ParentFetchResult();
  r.status = code;
  return r;
}

function fakeBody(packId: string, name: string): string {
  return JSON.stringify({
    schema_version: 5,
    family_id: 'fam-aaaaaaaa',
    merged_at: '2026-05-01T08:00:00Z',
    packs: [{
      pack_id: packId,
      name,
      version: 1,
      schema_version: 5,
      published_at: '2026-05-01T07:30:00Z',
      words: [{ id: 'apple', meaningZh: '苹果' }],
    }],
  });
}

function buildSvc(): { svc: FamilyPackService, adapter: StubAdapter, prefs: MemPrefs } {
  const adapter: StubAdapter = new StubAdapter();
  const prefs: MemPrefs = new MemPrefs();
  const svc: FamilyPackService = new FamilyPackService(adapter, BASE);
  svc.injectPreferences(prefs);
  svc.injectClock((): number => 1_700_000_000_000);
  return { svc, adapter, prefs };
}

export default function familyPackServiceTest() {
  describe('FamilyPackService', () => {
    it('ensureLatest_no_cache_writes_and_returns_blob', 0, async () => {
      const { svc, adapter, prefs } = buildSvc();
      adapter.responses.set(`GET ${URL_LATEST}`, ok(fakeBody('pck-1', 'A')));
      const headers: Record<string, string> = { 'ETag': '"e1"' };
      adapter.responseHeaders.set(`GET ${URL_LATEST}`, headers);
      const r: FamilyPackEnsureResult = await svc.ensureLatest(TOKEN);
      expect(r.status).assertEqual('updated');
      expect(r.blob !== null).assertTrue();
      expect(r.blob?.packs.length).assertEqual(1);
      expect(svc.currentBlob()?.packs[0].packId).assertEqual('pck-1');
      // Cache populated.
      expect(prefs.store['family_packs_v1'].length > 0).assertTrue();
    });

    it('ensureLatest_with_matching_etag_returns_not_modified', 0, async () => {
      const { svc, adapter } = buildSvc();
      adapter.responses.set(`GET ${URL_LATEST}`, ok(fakeBody('pck-1', 'A')));
      adapter.responseHeaders.set(`GET ${URL_LATEST}`, { 'ETag': '"e1"' });
      await svc.ensureLatest(TOKEN);
      adapter.responses.set(`GET ${URL_LATEST}`, status(304));
      const r: FamilyPackEnsureResult = await svc.ensureLatest(TOKEN);
      expect(r.status).assertEqual('not_modified');
      expect(r.blob !== null).assertTrue();
      expect(adapter.lastHeaders['If-None-Match']).assertEqual('"e1"');
    });

    it('ensureLatest_204_clears_cache', 0, async () => {
      const { svc, adapter, prefs } = buildSvc();
      adapter.responses.set(`GET ${URL_LATEST}`, ok(fakeBody('pck-1', 'A')));
      adapter.responseHeaders.set(`GET ${URL_LATEST}`, { 'ETag': '"e1"' });
      await svc.ensureLatest(TOKEN);
      adapter.responses.set(`GET ${URL_LATEST}`, status(204));
      const r: FamilyPackEnsureResult = await svc.ensureLatest(TOKEN);
      expect(r.status).assertEqual('cleared');
      expect(r.blob).assertEqual(null);
      expect(svc.currentBlob()).assertEqual(null);
      expect(prefs.store['family_packs_v1']).assertEqual('');
    });

    it('ensureLatest_network_error_returns_cached_fallback', 0, async () => {
      const { svc, adapter } = buildSvc();
      adapter.responses.set(`GET ${URL_LATEST}`, ok(fakeBody('pck-1', 'A')));
      adapter.responseHeaders.set(`GET ${URL_LATEST}`, { 'ETag': '"e1"' });
      await svc.ensureLatest(TOKEN);
      adapter.errorOn.add(`GET ${URL_LATEST}`);
      const r: FamilyPackEnsureResult = await svc.ensureLatest(TOKEN);
      expect(r.status).assertEqual('cached_fallback');
      expect(r.blob !== null).assertTrue();
    });

    it('ensureLatest_unbound_no_token_no_op', 0, async () => {
      const { svc, adapter } = buildSvc();
      adapter.responses.set(`GET ${URL_LATEST}`, ok(fakeBody('pck-1', 'A')));
      const r: FamilyPackEnsureResult = await svc.ensureLatest('');
      expect(r.status).assertEqual('no_data');
      expect(r.blob).assertEqual(null);
      expect(adapter.lastUrl).assertEqual('');
    });

    it('peekRemoteEtag_returns_header_only', 0, async () => {
      const { svc, adapter } = buildSvc();
      adapter.responses.set(`HEAD ${URL_LATEST}`, status(200));
      adapter.responseHeaders.set(`HEAD ${URL_LATEST}`, { 'etag': '"e2"' });
      const e: string | null = await svc.peekRemoteEtag(TOKEN);
      expect(e).assertEqual('"e2"');
    });

    it('peekRemoteEtag_204_returns_empty_string_marker', 0, async () => {
      const { svc, adapter } = buildSvc();
      adapter.responses.set(`HEAD ${URL_LATEST}`, status(204));
      const e: string | null = await svc.peekRemoteEtag(TOKEN);
      expect(e).assertEqual('');
    });

    it('peekRemoteEtag_error_returns_null', 0, async () => {
      const { svc, adapter } = buildSvc();
      adapter.errorOn.add(`HEAD ${URL_LATEST}`);
      const e: string | null = await svc.peekRemoteEtag(TOKEN);
      expect(e).assertEqual(null);
    });

    it('isRemoteStale_true_when_etag_differs', 0, async () => {
      const { svc, adapter } = buildSvc();
      adapter.responses.set(`GET ${URL_LATEST}`, ok(fakeBody('pck-1', 'A')));
      adapter.responseHeaders.set(`GET ${URL_LATEST}`, { 'ETag': '"e1"' });
      await svc.ensureLatest(TOKEN);
      adapter.responses.set(`HEAD ${URL_LATEST}`, status(200));
      adapter.responseHeaders.set(`HEAD ${URL_LATEST}`, { 'ETag': '"e-different"' });
      expect(await svc.isRemoteStale(TOKEN)).assertTrue();
    });

    it('isRemoteStale_false_when_etag_matches', 0, async () => {
      const { svc, adapter } = buildSvc();
      adapter.responses.set(`GET ${URL_LATEST}`, ok(fakeBody('pck-1', 'A')));
      adapter.responseHeaders.set(`GET ${URL_LATEST}`, { 'ETag': '"e1"' });
      await svc.ensureLatest(TOKEN);
      adapter.responses.set(`HEAD ${URL_LATEST}`, status(200));
      adapter.responseHeaders.set(`HEAD ${URL_LATEST}`, { 'ETag': '"e1"' });
      expect(await svc.isRemoteStale(TOKEN)).assertFalse();
    });

    it('warmFromCache_rehydrates_in_memory_blob', 0, async () => {
      const { svc, prefs } = buildSvc();
      const env: object = {
        etag: '"warm"',
        body: fakeBody('pck-warm', 'cold-start'),
        fetchedAtMs: 1_700_000_000_000,
      };
      prefs.store['family_packs_v1'] = JSON.stringify(env);
      const out = await svc.warmFromCache();
      expect(out !== null).assertTrue();
      expect(svc.currentBlob()?.packs[0].packId).assertEqual('pck-warm');
    });
  });
}
