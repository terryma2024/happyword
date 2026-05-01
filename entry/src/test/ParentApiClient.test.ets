import { describe, it, expect } from '@ohos/hypium';
import {
  ParentApiClient,
  ParentAuthError,
  ParentFetchAdapter,
  ParentFetchResult,
  ParentHttpError,
  ParentPackListPage,
  ParentPackPublished,
  ParentStats,
  ParentWordsPage,
} from '../main/ets/services/ParentApiClient';

class StubAdapter implements ParentFetchAdapter {
  responses: Map<string, ParentFetchResult> = new Map<string, ParentFetchResult>();
  lastHeaders: Record<string, string> = {};
  lastBody: string = '';
  lastUrl: string = '';
  lastMethod: string = '';

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

  private serve(
    method: string,
    url: string,
    headers: Record<string, string>,
    body: string,
  ): ParentFetchResult {
    this.lastMethod = method;
    this.lastUrl = url;
    this.lastHeaders = headers;
    this.lastBody = body;
    const r: ParentFetchResult | undefined = this.responses.get(`${method} ${url}`);
    if (r === undefined) {
      const fallback: ParentFetchResult = new ParentFetchResult();
      fallback.status = 500;
      fallback.body = '{"detail":{"error":{"code":"NO_STUB"}}}';
      return fallback;
    }
    return r;
  }
}

const BASE: string = 'https://happyword.vercel.app';

function fakeOk(body: string): ParentFetchResult {
  const r: ParentFetchResult = new ParentFetchResult();
  r.status = 200;
  r.body = body;
  return r;
}

function fake(status: number, body: string): ParentFetchResult {
  const r: ParentFetchResult = new ParentFetchResult();
  r.status = status;
  r.body = body;
  return r;
}

export default function parentApiClientTest(): void {
  describe('ParentApiClient.listWords', () => {
    it('parsesPageWithoutAuthHeader', 0, async () => {
      const ad: StubAdapter = new StubAdapter();
      ad.responses.set(
        `GET ${BASE}/api/v1/admin/words?page=1&size=10`,
        fakeOk(
          '{"items":[{"id":"fruit-apple","word":"apple","meaning_zh":"苹果","category":"fruit","difficulty":1,"created_at":"2026-05-01T00:00:00Z","updated_at":"2026-05-01T00:00:00Z"}],"total":1,"page":1,"size":10}',
        ),
      );
      const c: ParentApiClient = new ParentApiClient(ad, BASE);
      const page: ParentWordsPage = await c.listWords(1, 10);
      expect(page.items.length).assertEqual(1);
      expect(page.items[0].id).assertEqual('fruit-apple');
      expect(page.items[0].word).assertEqual('apple');
      expect(page.items[0].meaningZh).assertEqual('苹果');
      expect(page.total).assertEqual(1);
      // V0.5.8: client never sends Authorization (auth removed).
      expect(ad.lastHeaders['Authorization']).assertEqual(undefined);
    });

    it('throwsParentAuthErrorOn401', 0, async () => {
      const ad: StubAdapter = new StubAdapter();
      ad.responses.set(
        `GET ${BASE}/api/v1/admin/words?page=1&size=10`,
        fake(401, '{"detail":{"error":{"code":"UNAUTHORIZED"}}}'),
      );
      const c: ParentApiClient = new ParentApiClient(ad, BASE);
      let threw: boolean = false;
      try {
        await c.listWords(1, 10);
      } catch (e) {
        threw = e instanceof ParentAuthError;
      }
      expect(threw).assertTrue();
    });

    it('throwsParentHttpErrorOn500', 0, async () => {
      const ad: StubAdapter = new StubAdapter();
      ad.responses.set(`GET ${BASE}/api/v1/admin/words?page=1&size=10`, fake(500, '{}'));
      const c: ParentApiClient = new ParentApiClient(ad, BASE);
      let caught: ParentHttpError | undefined = undefined;
      try {
        await c.listWords(1, 10);
      } catch (e) {
        if (e instanceof ParentHttpError) {
          caught = e;
        }
      }
      expect(caught !== undefined).assertTrue();
      if (caught !== undefined) {
        expect(caught.status).assertEqual(500);
      }
    });
  });

  describe('ParentApiClient.getStats', () => {
    it('parsesAllScalarFields', 0, async () => {
      const ad: StubAdapter = new StubAdapter();
      ad.responses.set(
        `GET ${BASE}/api/v1/admin/stats`,
        fakeOk(
          '{"user_count":2,"word_count":50,"category_count":5,"pack_count":3,"latest_version":3,"last_published_at":"2026-05-01T00:00:00Z","llm_draft_pending":1,"lesson_import_draft_pending":0}',
        ),
      );
      const c: ParentApiClient = new ParentApiClient(ad, BASE);
      const s: ParentStats = await c.getStats();
      expect(s.userCount).assertEqual(2);
      expect(s.wordCount).assertEqual(50);
      expect(s.categoryCount).assertEqual(5);
      expect(s.packCount).assertEqual(3);
      expect(s.latestVersion).assertEqual(3);
      expect(s.llmDraftPending).assertEqual(1);
      expect(s.lessonImportDraftPending).assertEqual(0);
    });

    it('handlesNullableFields', 0, async () => {
      const ad: StubAdapter = new StubAdapter();
      ad.responses.set(
        `GET ${BASE}/api/v1/admin/stats`,
        fakeOk(
          '{"user_count":1,"word_count":0,"category_count":0,"pack_count":0,"latest_version":null,"last_published_at":null,"llm_draft_pending":0,"lesson_import_draft_pending":0}',
        ),
      );
      const c: ParentApiClient = new ParentApiClient(ad, BASE);
      const s: ParentStats = await c.getStats();
      expect(s.latestVersion).assertEqual(undefined);
      expect(s.lastPublishedAt).assertEqual(undefined);
    });
  });

  describe('ParentApiClient.listPacks + publishPack', () => {
    it('listPacksParsesItems', 0, async () => {
      const ad: StubAdapter = new StubAdapter();
      ad.responses.set(
        `GET ${BASE}/api/v1/admin/packs?page=1&size=20`,
        fakeOk(
          '{"items":[{"version":3,"schema_version":2,"published_at":"2026-05-01T00:00:00Z","published_by":"parent","word_count":50,"notes":"manual"}],"total":1,"page":1,"size":20}',
        ),
      );
      const c: ParentApiClient = new ParentApiClient(ad, BASE);
      const out: ParentPackListPage = await c.listPacks(1, 20);
      expect(out.items.length).assertEqual(1);
      expect(out.items[0].version).assertEqual(3);
      expect(out.items[0].publishedBy).assertEqual('parent');
    });

    it('publishPackParses201Response', 0, async () => {
      const ad: StubAdapter = new StubAdapter();
      const r: ParentFetchResult = new ParentFetchResult();
      r.status = 201;
      r.body =
        '{"version":4,"schema_version":2,"word_count":50,"published_at":"2026-05-01T00:00:00Z","published_by":"parent","notes":"manual"}';
      ad.responses.set(`POST ${BASE}/api/v1/admin/packs/publish`, r);
      const c: ParentApiClient = new ParentApiClient(ad, BASE);
      const pack: ParentPackPublished = await c.publishPack('manual');
      expect(pack.version).assertEqual(4);
      expect(pack.schemaVersion).assertEqual(2);
      expect(pack.wordCount).assertEqual(50);
      expect(pack.publishedBy).assertEqual('parent');
      expect(ad.lastBody.indexOf('manual') >= 0).assertTrue();
    });

    it('publishPackOmitsNotesWhenUndefined', 0, async () => {
      const ad: StubAdapter = new StubAdapter();
      const r: ParentFetchResult = new ParentFetchResult();
      r.status = 201;
      r.body =
        '{"version":5,"schema_version":2,"word_count":50,"published_at":"2026-05-01T00:00:00Z","published_by":"parent"}';
      ad.responses.set(`POST ${BASE}/api/v1/admin/packs/publish`, r);
      const c: ParentApiClient = new ParentApiClient(ad, BASE);
      const pack: ParentPackPublished = await c.publishPack();
      expect(pack.version).assertEqual(5);
      expect(pack.notes).assertEqual(undefined);
    });
  });
}
