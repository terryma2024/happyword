import { describe, it, expect } from '@ohos/hypium';
import { FamilyPackEnsureResult, FamilyPackFetchAdapter, FamilyPackService } from '../main/ets/services/FamilyPackService';
import { FamilyPacksBlob } from '../main/ets/services/FamilyPackMerge';
import { ParentFetchResult } from '../main/ets/services/ParentApiClient';
import { StringPreferencesLike } from '../main/ets/services/WrongAnswerStore';

class StubAdapter implements FamilyPackFetchAdapter {
  responses: Map<string, ParentFetchResult> = new Map<string, ParentFetchResult>();
  responseHeaders: Map<string, Map<string, string>> = new Map<string, Map<string, string>>();
  errorOn: Set<string> = new Set<string>();
  lastUrl: string = '';
  lastHeaders: Record<string, string> = {};
  lastMethod: string = '';
  private currentHeaders: Map<string, string> = new Map<string, string>();

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

  setResponseHeaders(key: string, headers: Map<string, string>): void {
    this.responseHeaders.set(key, headers);
  }

  lastResponseHeader(name: string): string {
    const v: string | undefined = this.currentHeaders.get(name);
    return v !== undefined ? v : '';
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
    const h: Map<string, string> | undefined = this.responseHeaders.get(key);
    this.currentHeaders = h !== undefined ? h : new Map<string, string>();
    return r;
  }
}

class MemPrefs implements StringPreferencesLike {
  store: Map<string, string> = new Map<string, string>();
  async getString(key: string): Promise<string> {
    return this.store.get(key) ?? '';
  }
  async putString(key: string, value: string): Promise<void> {
    this.store.set(key, value);
  }
  async flush(): Promise<void> {}
}

const BASE: string = 'https://happyword.vercel.app';
const URL_LATEST: string = `${BASE}/api/v1/child/family-packs/latest.json`;
const TOKEN: string = 'device.jwt.token';
const CACHE_KEY: string = 'family_packs_v1';

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
  return `{"schema_version":5,"family_id":"fam-aaaaaaaa","merged_at":"2026-05-01T08:00:00Z","packs":[{"pack_id":"${packId}","name":"${name}","version":1,"schema_version":5,"published_at":"2026-05-01T07:30:00Z","words":[{"id":"apple","meaningZh":"苹果"}]}]}`;
}

function headersWith(name: string, value: string): Map<string, string> {
  const m: Map<string, string> = new Map<string, string>();
  m.set(name, value);
  return m;
}

class Harness {
  svc: FamilyPackService;
  adapter: StubAdapter;
  prefs: MemPrefs;
  constructor(svc: FamilyPackService, adapter: StubAdapter, prefs: MemPrefs) {
    this.svc = svc;
    this.adapter = adapter;
    this.prefs = prefs;
  }
}

function buildSvc(): Harness {
  const adapter: StubAdapter = new StubAdapter();
  const prefs: MemPrefs = new MemPrefs();
  const svc: FamilyPackService = new FamilyPackService(adapter, BASE);
  svc.injectPreferences(prefs);
  svc.injectClock((): number => 1_700_000_000_000);
  return new Harness(svc, adapter, prefs);
}

export default function familyPackServiceTest() {
  describe('FamilyPackService', () => {
    it('ensureLatest_no_cache_writes_and_returns_blob', 0, async () => {
      const h: Harness = buildSvc();
      h.adapter.responses.set(`GET ${URL_LATEST}`, ok(fakeBody('pck-1', 'A')));
      h.adapter.setResponseHeaders(`GET ${URL_LATEST}`, headersWith('ETag', '"e1"'));
      const r: FamilyPackEnsureResult = await h.svc.ensureLatest(TOKEN);
      expect(r.status).assertEqual('updated');
      expect(r.blob !== null).assertTrue();
      expect(r.blob?.packs.length).assertEqual(1);
      expect(h.svc.currentBlob()?.packs[0].packId).assertEqual('pck-1');
      expect((h.prefs.store.get(CACHE_KEY) ?? '').length > 0).assertTrue();
    });

    it('ensureLatest_with_matching_etag_returns_not_modified', 0, async () => {
      const h: Harness = buildSvc();
      h.adapter.responses.set(`GET ${URL_LATEST}`, ok(fakeBody('pck-1', 'A')));
      h.adapter.setResponseHeaders(`GET ${URL_LATEST}`, headersWith('ETag', '"e1"'));
      await h.svc.ensureLatest(TOKEN);
      h.adapter.responses.set(`GET ${URL_LATEST}`, status(304));
      const r: FamilyPackEnsureResult = await h.svc.ensureLatest(TOKEN);
      expect(r.status).assertEqual('not_modified');
      expect(r.blob !== null).assertTrue();
      expect(h.adapter.lastHeaders['If-None-Match']).assertEqual('"e1"');
    });

    it('ensureLatest_204_clears_cache', 0, async () => {
      const h: Harness = buildSvc();
      h.adapter.responses.set(`GET ${URL_LATEST}`, ok(fakeBody('pck-1', 'A')));
      h.adapter.setResponseHeaders(`GET ${URL_LATEST}`, headersWith('ETag', '"e1"'));
      await h.svc.ensureLatest(TOKEN);
      h.adapter.responses.set(`GET ${URL_LATEST}`, status(204));
      const r: FamilyPackEnsureResult = await h.svc.ensureLatest(TOKEN);
      expect(r.status).assertEqual('cleared');
      expect(r.blob).assertEqual(null);
      expect(h.svc.currentBlob()).assertEqual(null);
      expect(h.prefs.store.get(CACHE_KEY) ?? '').assertEqual('');
    });

    it('ensureLatest_network_error_returns_cached_fallback', 0, async () => {
      const h: Harness = buildSvc();
      h.adapter.responses.set(`GET ${URL_LATEST}`, ok(fakeBody('pck-1', 'A')));
      h.adapter.setResponseHeaders(`GET ${URL_LATEST}`, headersWith('ETag', '"e1"'));
      await h.svc.ensureLatest(TOKEN);
      h.adapter.errorOn.add(`GET ${URL_LATEST}`);
      const r: FamilyPackEnsureResult = await h.svc.ensureLatest(TOKEN);
      expect(r.status).assertEqual('cached_fallback');
      expect(r.blob !== null).assertTrue();
    });

    it('ensureLatest_unbound_no_token_no_op', 0, async () => {
      const h: Harness = buildSvc();
      h.adapter.responses.set(`GET ${URL_LATEST}`, ok(fakeBody('pck-1', 'A')));
      const r: FamilyPackEnsureResult = await h.svc.ensureLatest('');
      expect(r.status).assertEqual('no_data');
      expect(r.blob).assertEqual(null);
      expect(h.adapter.lastUrl).assertEqual('');
    });

    it('peekRemoteEtag_returns_header_only', 0, async () => {
      const h: Harness = buildSvc();
      h.adapter.responses.set(`HEAD ${URL_LATEST}`, status(200));
      h.adapter.setResponseHeaders(`HEAD ${URL_LATEST}`, headersWith('etag', '"e2"'));
      const e: string | null = await h.svc.peekRemoteEtag(TOKEN);
      expect(e).assertEqual('"e2"');
    });

    it('peekRemoteEtag_204_returns_empty_string_marker', 0, async () => {
      const h: Harness = buildSvc();
      h.adapter.responses.set(`HEAD ${URL_LATEST}`, status(204));
      const e: string | null = await h.svc.peekRemoteEtag(TOKEN);
      expect(e).assertEqual('');
    });

    it('peekRemoteEtag_error_returns_null', 0, async () => {
      const h: Harness = buildSvc();
      h.adapter.errorOn.add(`HEAD ${URL_LATEST}`);
      const e: string | null = await h.svc.peekRemoteEtag(TOKEN);
      expect(e).assertEqual(null);
    });

    it('isRemoteStale_true_when_etag_differs', 0, async () => {
      const h: Harness = buildSvc();
      h.adapter.responses.set(`GET ${URL_LATEST}`, ok(fakeBody('pck-1', 'A')));
      h.adapter.setResponseHeaders(`GET ${URL_LATEST}`, headersWith('ETag', '"e1"'));
      await h.svc.ensureLatest(TOKEN);
      h.adapter.responses.set(`HEAD ${URL_LATEST}`, status(200));
      h.adapter.setResponseHeaders(`HEAD ${URL_LATEST}`, headersWith('ETag', '"e-different"'));
      expect(await h.svc.isRemoteStale(TOKEN)).assertTrue();
    });

    it('isRemoteStale_false_when_etag_matches', 0, async () => {
      const h: Harness = buildSvc();
      h.adapter.responses.set(`GET ${URL_LATEST}`, ok(fakeBody('pck-1', 'A')));
      h.adapter.setResponseHeaders(`GET ${URL_LATEST}`, headersWith('ETag', '"e1"'));
      await h.svc.ensureLatest(TOKEN);
      h.adapter.responses.set(`HEAD ${URL_LATEST}`, status(200));
      h.adapter.setResponseHeaders(`HEAD ${URL_LATEST}`, headersWith('ETag', '"e1"'));
      expect(await h.svc.isRemoteStale(TOKEN)).assertFalse();
    });

    it('warmFromCache_rehydrates_in_memory_blob', 0, async () => {
      const h: Harness = buildSvc();
      const env: string = `{"etag":"\\"warm\\"","body":${JSON.stringify(fakeBody('pck-warm', 'cold-start'))},"fetchedAtMs":1700000000000}`;
      h.prefs.store.set(CACHE_KEY, env);
      const out: FamilyPacksBlob | null = await h.svc.warmFromCache();
      expect(out !== null).assertTrue();
      expect(h.svc.currentBlob()?.packs[0].packId).assertEqual('pck-warm');
    });
  });
}
