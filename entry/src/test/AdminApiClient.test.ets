import { describe, it, expect } from '@ohos/hypium';
import {
  AdminApiClient,
  AdminAuthError,
  AdminFetchAdapter,
  AdminFetchResult,
  AdminHttpError,
  AdminPackListPage,
  AdminPackPublished,
  AdminStats,
  AdminWordsPage,
} from '../main/ets/services/AdminApiClient';

class StubAdapter implements AdminFetchAdapter {
  responses: Map<string, AdminFetchResult> = new Map<string, AdminFetchResult>();
  lastHeaders: Record<string, string> = {};
  lastBody: string = '';
  lastUrl: string = '';
  lastMethod: string = '';

  async get(url: string, headers: Record<string, string>): Promise<AdminFetchResult> {
    return this.serve('GET', url, headers, '');
  }

  async post(url: string, headers: Record<string, string>, body: string): Promise<AdminFetchResult> {
    return this.serve('POST', url, headers, body);
  }

  async put(url: string, headers: Record<string, string>, body: string): Promise<AdminFetchResult> {
    return this.serve('PUT', url, headers, body);
  }

  async del(url: string, headers: Record<string, string>): Promise<AdminFetchResult> {
    return this.serve('DELETE', url, headers, '');
  }

  private serve(
    method: string,
    url: string,
    headers: Record<string, string>,
    body: string,
  ): AdminFetchResult {
    this.lastMethod = method;
    this.lastUrl = url;
    this.lastHeaders = headers;
    this.lastBody = body;
    const r: AdminFetchResult | undefined = this.responses.get(`${method} ${url}`);
    if (r === undefined) {
      const fallback: AdminFetchResult = new AdminFetchResult();
      fallback.status = 500;
      fallback.body = '{"detail":{"error":{"code":"NO_STUB"}}}';
      return fallback;
    }
    return r;
  }
}

const BASE: string = 'https://happyword.vercel.app';

function fakeOk(body: string): AdminFetchResult {
  const r: AdminFetchResult = new AdminFetchResult();
  r.status = 200;
  r.body = body;
  return r;
}

function fake(status: number, body: string): AdminFetchResult {
  const r: AdminFetchResult = new AdminFetchResult();
  r.status = status;
  r.body = body;
  return r;
}

export default function adminApiClientTest(): void {
  describe('AdminApiClient.login', () => {
    it('storesBearerTokenOnSuccess', 0, async () => {
      const ad: StubAdapter = new StubAdapter();
      ad.responses.set(
        `POST ${BASE}/api/v1/auth/login`,
        fakeOk('{"access_token":"tok-123","token_type":"bearer","expires_in":86400}'),
      );
      const c: AdminApiClient = new AdminApiClient(ad, BASE);
      const tok: string = await c.login('admin', 'pw');
      expect(tok).assertEqual('tok-123');
      expect(ad.lastBody.indexOf('admin') >= 0).assertTrue();
      // Subsequent calls should use the bearer token automatically.
      const cAuth: string | undefined = ad.lastHeaders['Content-Type'];
      expect(cAuth !== undefined).assertTrue();
      if (cAuth !== undefined) {
        expect(cAuth.indexOf('application/json') === 0).assertTrue();
      }
    });

    it('throwsAdminAuthErrorOn401', 0, async () => {
      const ad: StubAdapter = new StubAdapter();
      ad.responses.set(
        `POST ${BASE}/api/v1/auth/login`,
        fake(401, '{"detail":{"error":{"code":"UNAUTHORIZED"}}}'),
      );
      const c: AdminApiClient = new AdminApiClient(ad, BASE);
      let threw: boolean = false;
      try {
        await c.login('admin', 'wrong');
      } catch (e) {
        threw = e instanceof AdminAuthError;
      }
      expect(threw).assertTrue();
    });

    it('throwsAdminHttpErrorOn500', 0, async () => {
      const ad: StubAdapter = new StubAdapter();
      ad.responses.set(`POST ${BASE}/api/v1/auth/login`, fake(500, '{}'));
      const c: AdminApiClient = new AdminApiClient(ad, BASE);
      let caught: AdminHttpError | undefined = undefined;
      try {
        await c.login('admin', 'pw');
      } catch (e) {
        if (e instanceof AdminHttpError) {
          caught = e;
        }
      }
      expect(caught !== undefined).assertTrue();
      if (caught !== undefined) {
        expect(caught.status).assertEqual(500);
      }
    });
  });

  describe('AdminApiClient.listWords', () => {
    it('sendsBearerTokenAndParsesPage', 0, async () => {
      const ad: StubAdapter = new StubAdapter();
      ad.responses.set(
        `GET ${BASE}/api/v1/admin/words?page=1&size=10`,
        fakeOk(
          '{"items":[{"id":"fruit-apple","word":"apple","meaning_zh":"苹果","category":"fruit","difficulty":1,"created_at":"2026-05-01T00:00:00Z","updated_at":"2026-05-01T00:00:00Z"}],"total":1,"page":1,"size":10}',
        ),
      );
      const c: AdminApiClient = new AdminApiClient(ad, BASE);
      c.setBearerToken('tok-123');
      const page: AdminWordsPage = await c.listWords(1, 10);
      expect(page.items.length).assertEqual(1);
      expect(page.items[0].id).assertEqual('fruit-apple');
      expect(page.items[0].word).assertEqual('apple');
      expect(page.items[0].meaningZh).assertEqual('苹果');
      expect(page.total).assertEqual(1);
      const auth: string | undefined = ad.lastHeaders['Authorization'];
      expect(auth !== undefined).assertTrue();
      if (auth !== undefined) {
        expect(auth).assertEqual('Bearer tok-123');
      }
    });

    it('clearBearerTokenStripsAuthorizationHeader', 0, async () => {
      const ad: StubAdapter = new StubAdapter();
      ad.responses.set(
        `GET ${BASE}/api/v1/admin/words?page=1&size=10`,
        fakeOk('{"items":[],"total":0,"page":1,"size":10}'),
      );
      const c: AdminApiClient = new AdminApiClient(ad, BASE);
      c.setBearerToken('tok-123');
      c.clearBearerToken();
      await c.listWords(1, 10);
      expect(ad.lastHeaders['Authorization']).assertEqual(undefined);
    });
  });

  describe('AdminApiClient.getStats', () => {
    it('parsesAllScalarFields', 0, async () => {
      const ad: StubAdapter = new StubAdapter();
      ad.responses.set(
        `GET ${BASE}/api/v1/admin/stats`,
        fakeOk(
          '{"user_count":2,"word_count":50,"category_count":5,"pack_count":3,"latest_version":3,"last_published_at":"2026-05-01T00:00:00Z","llm_draft_pending":1,"lesson_import_draft_pending":0}',
        ),
      );
      const c: AdminApiClient = new AdminApiClient(ad, BASE);
      c.setBearerToken('tok');
      const s: AdminStats = await c.getStats();
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
      const c: AdminApiClient = new AdminApiClient(ad, BASE);
      c.setBearerToken('tok');
      const s: AdminStats = await c.getStats();
      expect(s.latestVersion).assertEqual(undefined);
      expect(s.lastPublishedAt).assertEqual(undefined);
    });
  });

  describe('AdminApiClient.listPacks + publishPack', () => {
    it('listPacksParsesItems', 0, async () => {
      const ad: StubAdapter = new StubAdapter();
      ad.responses.set(
        `GET ${BASE}/api/v1/admin/packs?page=1&size=20`,
        fakeOk(
          '{"items":[{"version":3,"schema_version":2,"published_at":"2026-05-01T00:00:00Z","published_by":"admin","word_count":50,"notes":"manual"}],"total":1,"page":1,"size":20}',
        ),
      );
      const c: AdminApiClient = new AdminApiClient(ad, BASE);
      c.setBearerToken('tok');
      const out: AdminPackListPage = await c.listPacks(1, 20);
      expect(out.items.length).assertEqual(1);
      expect(out.items[0].version).assertEqual(3);
      expect(out.items[0].publishedBy).assertEqual('admin');
    });

    it('publishPackParses201Response', 0, async () => {
      const ad: StubAdapter = new StubAdapter();
      const r: AdminFetchResult = new AdminFetchResult();
      r.status = 201;
      r.body =
        '{"version":4,"schema_version":2,"word_count":50,"published_at":"2026-05-01T00:00:00Z","published_by":"admin","notes":"manual"}';
      ad.responses.set(`POST ${BASE}/api/v1/admin/packs/publish`, r);
      const c: AdminApiClient = new AdminApiClient(ad, BASE);
      c.setBearerToken('tok');
      const pack: AdminPackPublished = await c.publishPack('manual');
      expect(pack.version).assertEqual(4);
      expect(pack.schemaVersion).assertEqual(2);
      expect(pack.wordCount).assertEqual(50);
      expect(pack.publishedBy).assertEqual('admin');
      expect(ad.lastBody.indexOf('manual') >= 0).assertTrue();
    });

    it('publishPackOmitsNotesWhenUndefined', 0, async () => {
      const ad: StubAdapter = new StubAdapter();
      const r: AdminFetchResult = new AdminFetchResult();
      r.status = 201;
      r.body =
        '{"version":5,"schema_version":2,"word_count":50,"published_at":"2026-05-01T00:00:00Z","published_by":"admin"}';
      ad.responses.set(`POST ${BASE}/api/v1/admin/packs/publish`, r);
      const c: AdminApiClient = new AdminApiClient(ad, BASE);
      c.setBearerToken('tok');
      const pack: AdminPackPublished = await c.publishPack();
      expect(pack.version).assertEqual(5);
      expect(pack.notes).assertEqual(undefined);
    });
  });
}
