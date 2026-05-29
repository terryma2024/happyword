import { describe, it, expect } from '@ohos/hypium';
import {
  GlobalPackEnsureResult,
  GlobalPackFetchAdapter,
  GlobalPackService,
} from '../main/ets/services/GlobalPackService';
import { Pack } from '../main/ets/models/Pack';
import { ParentFetchResult } from '../main/ets/services/ParentApiClient';
import { StringPreferencesLike } from '../main/ets/services/WrongAnswerStore';
import { MonsterKind } from '../main/ets/data/MonsterCatalog';

class StubAdapter implements GlobalPackFetchAdapter {
  responses: Map<string, ParentFetchResult> = new Map<string, ParentFetchResult>();
  responseHeaders: Map<string, Map<string, string>> = new Map<string, Map<string, string>>();
  errorOn: Set<string> = new Set<string>();
  lastUrl: string = '';
  lastHeaders: Record<string, string> = {};
  lastMethod: string = '';
  private currentHeaders: Map<string, string> = new Map<string, string>();

  async get(url: string, headers: Record<string, string>): Promise<ParentFetchResult> {
    return this.serve('GET', url, headers);
  }
  async post(url: string, headers: Record<string, string>, _body: string): Promise<ParentFetchResult> {
    return this.serve('POST', url, headers);
  }
  async put(url: string, headers: Record<string, string>, _body: string): Promise<ParentFetchResult> {
    return this.serve('PUT', url, headers);
  }
  async patch(url: string, headers: Record<string, string>, _body: string): Promise<ParentFetchResult> {
    return this.serve('PATCH', url, headers);
  }
  async del(url: string, headers: Record<string, string>): Promise<ParentFetchResult> {
    return this.serve('DELETE', url, headers);
  }
  async head(url: string, headers: Record<string, string>): Promise<ParentFetchResult> {
    return this.serve('HEAD', url, headers);
  }

  setResponseHeaders(key: string, headers: Map<string, string>): void {
    this.responseHeaders.set(key, headers);
  }

  lastResponseHeader(name: string): string {
    const v: string | undefined = this.currentHeaders.get(name);
    return v !== undefined ? v : '';
  }

  private serve(method: string, url: string, headers: Record<string, string>): ParentFetchResult {
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

const BASE: string = 'https://happyword.cool';
const URL_LATEST: string = `${BASE}/api/v1/public/global-packs/latest.json`;
const CACHE_KEY: string = 'global_packs_v1';

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

function headersWith(name: string, value: string): Map<string, string> {
  const m: Map<string, string> = new Map<string, string>();
  m.set(name, value);
  return m;
}

// String literal — ArkTS strict mode rejects untyped object literals,
// so the SAMPLE_BODY is hand-built as a JSON string.
const SAMPLE_BODY: string =
  '{"schema_version":5,"merged_at":"2026-05-01T08:00:00Z",' +
  '"packs":[{"pack_id":"fruit-forest-global",' +
  '"name":"Fruit Forest Global",' +
  '"description":"水果森林（global）",' +
  '"version":3,"schema_version":5,' +
  '"published_at":"2026-05-01T07:30:00Z",' +
  '"scene":{"bgPrimary":"#FFF6E0","bgAccent":"#FFD49A",' +
  '"bossName":"Orchard Sentinel","bossCandidates":[4,5,6],' +
  '"spellbook_cover_url":"https://blob.example/covers/fruit-global.png",' +
  '"storyEn":"A global fruit path opens under warm lanterns.",' +
  '"storyZh":"全局水果小路在暖灯下打开。",' +
  '"monsterPlan":[{"kind":"normal","catalogIndex":0},' +
  '{"kind":"boss","catalogIndex":4}]},' +
  '"words":[' +
  '{"id":"gpk-apple","word":"apple","meaningZh":"苹果","category":"fruit","difficulty":1},' +
  '{"id":"gpk-banana","word":"banana","meaningZh":"香蕉","category":"fruit","difficulty":1}' +
  ']}]}';

const SKIP_BODY: string =
  '{"packs":[{"name":"no-id"},' +
  '{"pack_id":"good","name":"good","words":[]}]}';

class Harness {
  svc: GlobalPackService;
  adapter: StubAdapter;
  prefs: MemPrefs;
  constructor(svc: GlobalPackService, adapter: StubAdapter, prefs: MemPrefs) {
    this.svc = svc;
    this.adapter = adapter;
    this.prefs = prefs;
  }
}

function buildSvc(): Harness {
  const adapter: StubAdapter = new StubAdapter();
  const prefs: MemPrefs = new MemPrefs();
  const svc: GlobalPackService = new GlobalPackService(adapter, BASE);
  svc.injectPreferences(prefs);
  svc.injectClock((): number => 1_700_000_000_000);
  return new Harness(svc, adapter, prefs);
}

export default function GlobalPackServiceTest() {
  describe('GlobalPackService.parsePacks', () => {
    it('parses scene + words into Pack[] with source=global', 0, () => {
      const packs: Pack[] = GlobalPackService.parsePacks(SAMPLE_BODY);
      expect(packs.length).assertEqual(1);
      const p: Pack = packs[0];
      expect(p.id).assertEqual('fruit-forest-global');
      expect(p.source).assertEqual('global');
      expect(p.labelZh).assertEqual('水果森林（global）');
      expect(p.version).assertEqual(3);
      expect(p.scene.bossName).assertEqual('Orchard Sentinel');
      expect(p.scene.spellbookCoverUrl).assertEqual('https://blob.example/covers/fruit-global.png');
      expect(p.scene.storyEn).assertEqual('A global fruit path opens under warm lanterns.');
      expect(p.scene.storyZh).assertEqual('全局水果小路在暖灯下打开。');
      expect(p.scene.bossCandidates.length).assertEqual(3);
      expect(p.scene.monsterPlan.slots.length).assertEqual(2);
      expect(p.scene.monsterPlan.slots[1].kind).assertEqual(MonsterKind.Boss);
      expect(p.words.length).assertEqual(2);
      expect(p.publishedAtMs > 0).assertTrue();
    });

    it('returns empty list on malformed JSON', 0, () => {
      expect(GlobalPackService.parsePacks('{not-json').length).assertEqual(0);
      expect(GlobalPackService.parsePacks('').length).assertEqual(0);
    });

    it('skips packs without pack_id', 0, () => {
      const packs: Pack[] = GlobalPackService.parsePacks(SKIP_BODY);
      expect(packs.length).assertEqual(1);
      expect(packs[0].id).assertEqual('good');
    });
  });

  describe('GlobalPackService.ensureLatest', () => {
    it('writes cache + returns Pack[] on 200', 0, async (done: () => void) => {
      const h: Harness = buildSvc();
      h.adapter.responses.set(`GET ${URL_LATEST}`, ok(SAMPLE_BODY));
      h.adapter.setResponseHeaders(`GET ${URL_LATEST}`, headersWith('ETag', '"v1"'));
      const out: GlobalPackEnsureResult = await h.svc.ensureLatest();
      expect(out.status).assertEqual('updated');
      expect(out.packs.length).assertEqual(1);
      expect(out.packs[0].id).assertEqual('fruit-forest-global');
      expect(h.prefs.store.get(CACHE_KEY) !== undefined).assertTrue();
      done();
    });

    it('honours 304 by returning cached packs', 0, async (done: () => void) => {
      const h: Harness = buildSvc();
      h.adapter.responses.set(`GET ${URL_LATEST}`, ok(SAMPLE_BODY));
      h.adapter.setResponseHeaders(`GET ${URL_LATEST}`, headersWith('ETag', '"v1"'));
      await h.svc.ensureLatest();
      h.adapter.responses.set(`GET ${URL_LATEST}`, status(304));
      const out: GlobalPackEnsureResult = await h.svc.ensureLatest();
      expect(out.status).assertEqual('not_modified');
      expect(out.packs.length).assertEqual(1);
      done();
    });

    it('clears cache + returns empty on 204', 0, async (done: () => void) => {
      const h: Harness = buildSvc();
      h.adapter.responses.set(`GET ${URL_LATEST}`, ok(SAMPLE_BODY));
      h.adapter.setResponseHeaders(`GET ${URL_LATEST}`, headersWith('ETag', '"v1"'));
      await h.svc.ensureLatest();
      h.adapter.responses.set(`GET ${URL_LATEST}`, status(204));
      const out: GlobalPackEnsureResult = await h.svc.ensureLatest();
      expect(out.status).assertEqual('cleared');
      expect(out.packs.length).assertEqual(0);
      expect(h.prefs.store.get(CACHE_KEY) ?? '').assertEqual('');
      done();
    });

    it('falls back to cache on network error', 0, async (done: () => void) => {
      const h: Harness = buildSvc();
      h.adapter.responses.set(`GET ${URL_LATEST}`, ok(SAMPLE_BODY));
      h.adapter.setResponseHeaders(`GET ${URL_LATEST}`, headersWith('ETag', '"v1"'));
      await h.svc.ensureLatest();
      h.adapter.errorOn.add(`GET ${URL_LATEST}`);
      const out: GlobalPackEnsureResult = await h.svc.ensureLatest();
      expect(out.status).assertEqual('cached_fallback');
      expect(out.packs.length).assertEqual(1);
      done();
    });

    it('warmFromCache hydrates memoryPacks from prefs', 0, async (done: () => void) => {
      const h: Harness = buildSvc();
      h.adapter.responses.set(`GET ${URL_LATEST}`, ok(SAMPLE_BODY));
      h.adapter.setResponseHeaders(`GET ${URL_LATEST}`, headersWith('ETag', '"v1"'));
      await h.svc.ensureLatest();

      const fresh: GlobalPackService = new GlobalPackService(h.adapter, BASE);
      fresh.injectPreferences(h.prefs);
      const packs: Pack[] = await fresh.warmFromCache();
      expect(packs.length).assertEqual(1);
      expect(fresh.currentPacks().length).assertEqual(1);
      done();
    });

    it('does not send Authorization header (anonymous endpoint)', 0, async (done: () => void) => {
      const h: Harness = buildSvc();
      h.adapter.responses.set(`GET ${URL_LATEST}`, ok(SAMPLE_BODY));
      h.adapter.setResponseHeaders(`GET ${URL_LATEST}`, headersWith('ETag', '"v1"'));
      await h.svc.ensureLatest();
      expect(h.adapter.lastHeaders['Authorization']).assertEqual(undefined);
      done();
    });
  });

  describe('GlobalPackService.peekRemoteEtag', () => {
    it('returns ETag from HEAD response', 0, async (done: () => void) => {
      const h: Harness = buildSvc();
      h.adapter.responses.set(`HEAD ${URL_LATEST}`, status(200));
      h.adapter.setResponseHeaders(`HEAD ${URL_LATEST}`, headersWith('ETag', '"v9"'));
      const etag: string | null = await h.svc.peekRemoteEtag();
      expect(etag).assertEqual('"v9"');
      done();
    });

    it('returns empty string on 204', 0, async (done: () => void) => {
      const h: Harness = buildSvc();
      h.adapter.responses.set(`HEAD ${URL_LATEST}`, status(204));
      const etag: string | null = await h.svc.peekRemoteEtag();
      expect(etag).assertEqual('');
      done();
    });

    it('returns null on 5xx', 0, async (done: () => void) => {
      const h: Harness = buildSvc();
      h.adapter.responses.set(`HEAD ${URL_LATEST}`, status(500));
      const etag: string | null = await h.svc.peekRemoteEtag();
      expect(etag === null).assertTrue();
      done();
    });
  });
}
