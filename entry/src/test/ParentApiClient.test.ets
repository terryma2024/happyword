import { describe, it, expect } from '@ohos/hypium';
import { http } from '@kit.NetworkKit';
import {
  IHttpRequester,
  LessonApproveSummaryDto,
  LessonDraftDto,
  LessonDraftListPage,
  LessonExtractedDto,
  LessonExtractedWord,
  LessonImportError,
  ParentApiClient,
  ParentAuthError,
  ParentFetchAdapter,
  ParentFetchResult,
  ParentHttpError,
  ParentPackListPage,
  ParentPackPublished,
  ParentStats,
  ParentWordsPage,
  PickedImage,
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

/** Test-only `http.HttpResponse` builder. ArkTS forbids untyped object
 *  literals, so we materialize a fake response through a concrete class
 *  (which satisfies the structural fields the importer touches) and cast
 *  through `Object` to fit the SDK's interface. */
class FakeHttpResponse {
  responseCode: number = 0;
  result: string = '';
  resultType: http.HttpDataType = http.HttpDataType.STRING;
  header: Record<string, string> = {};
  cookies: string = '';
}

function fakeHttp(status: number, body: string): http.HttpResponse {
  const r: FakeHttpResponse = new FakeHttpResponse();
  r.responseCode = status;
  r.result = body;
  return r as Object as http.HttpResponse;
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

  // ---------------------------------------------------------------------------
  // V0.5.8 lesson-import endpoints.
  // ---------------------------------------------------------------------------

  describe('ParentApiClient.getLessonDraft', () => {
    it('parsesPendingDraft', 0, async () => {
      const ad: StubAdapter = new StubAdapter();
      ad.responses.set(
        `GET ${BASE}/api/v1/admin/lesson-drafts/draft-1`,
        fakeOk(
          '{"id":"draft-1","source_image_url":"https://blob/lesson.jpg","extracted":{"category_id":"unit-1","label_en":"Unit 1","label_zh":"第一单元","story_zh":null,"words":[{"word":"apple","meaningZh":"苹果","difficulty":1}]},"edited_extracted":null,"status":"pending","created_at":"2026-05-01T00:00:00Z","reviewed_at":null,"reviewer":null,"model":"gpt-4o","prompt_version":1,"approval_summary":null}',
        ),
      );
      const c: ParentApiClient = new ParentApiClient(ad, BASE);
      const draft: LessonDraftDto = await c.getLessonDraft('draft-1');
      expect(draft.id).assertEqual('draft-1');
      expect(draft.status).assertEqual('pending');
      expect(draft.extracted.label_zh).assertEqual('第一单元');
      expect(draft.extracted.words.length).assertEqual(1);
      expect(draft.extracted.words[0].word).assertEqual('apple');
      expect(draft.extracted.words[0].meaningZh).assertEqual('苹果');
    });
  });

  describe('ParentApiClient.patchLessonDraft', () => {
    it('sendsEditedExtractedAsJsonBody', 0, async () => {
      const ad: StubAdapter = new StubAdapter();
      ad.responses.set(
        `PATCH ${BASE}/api/v1/admin/lesson-drafts/draft-1`,
        fakeOk(
          '{"id":"draft-1","source_image_url":"u","extracted":{"category_id":"c","label_en":"a","label_zh":"b","story_zh":null,"words":[]},"edited_extracted":{"category_id":"c","label_en":"a","label_zh":"b","story_zh":null,"words":[{"word":"banana","meaningZh":"香蕉","difficulty":2}]},"status":"pending","created_at":"2026-05-01T00:00:00Z","reviewed_at":null,"reviewer":null,"model":"gpt-4o","prompt_version":1,"approval_summary":null}',
        ),
      );
      const c: ParentApiClient = new ParentApiClient(ad, BASE);
      const edited: LessonExtractedDto = new LessonExtractedDto();
      edited.category_id = 'c';
      edited.label_en = 'a';
      edited.label_zh = 'b';
      const w: LessonExtractedWord = new LessonExtractedWord();
      w.word = 'banana';
      w.meaningZh = '香蕉';
      w.difficulty = 2;
      edited.words.push(w);
      const out: LessonDraftDto = await c.patchLessonDraft('draft-1', edited);
      expect(ad.lastMethod).assertEqual('PATCH');
      expect(ad.lastBody.indexOf('"edited_extracted"') >= 0).assertTrue();
      expect(ad.lastBody.indexOf('banana') >= 0).assertTrue();
      expect(out.edited_extracted !== undefined).assertTrue();
      if (out.edited_extracted !== undefined) {
        expect(out.edited_extracted.words[0].word).assertEqual('banana');
      }
    });
  });

  describe('ParentApiClient.approveLessonDraft', () => {
    it('parsesApprovalSummary', 0, async () => {
      const ad: StubAdapter = new StubAdapter();
      const r: ParentFetchResult = new ParentFetchResult();
      r.status = 200;
      r.body =
        '{"created_category":{"id":"unit-1","label_en":"Unit 1","label_zh":"第一单元","story_zh":null,"source_image_url":"u","source":"lesson-import","created_at":"2026-05-01T00:00:00Z","updated_at":"2026-05-01T00:00:00Z"},"created_words":[{"id":"unit-1-apple"}],"skipped_words":[]}';
      ad.responses.set(`POST ${BASE}/api/v1/admin/lesson-drafts/draft-1/approve`, r);
      const c: ParentApiClient = new ParentApiClient(ad, BASE);
      const out: LessonApproveSummaryDto = await c.approveLessonDraft('draft-1');
      expect(out.created_category.id).assertEqual('unit-1');
      expect(out.created_words.length).assertEqual(1);
      expect(out.skipped_words.length).assertEqual(0);
    });
  });

  describe('ParentApiClient.rejectLessonDraft', () => {
    it('parsesRejectedDraft', 0, async () => {
      const ad: StubAdapter = new StubAdapter();
      ad.responses.set(
        `POST ${BASE}/api/v1/admin/lesson-drafts/draft-1/reject`,
        fakeOk(
          '{"id":"draft-1","source_image_url":"u","extracted":{"category_id":"c","label_en":"a","label_zh":"b","story_zh":null,"words":[]},"edited_extracted":null,"status":"rejected","created_at":"2026-05-01T00:00:00Z","reviewed_at":"2026-05-01T01:00:00Z","reviewer":"parent","model":"gpt-4o","prompt_version":1,"approval_summary":null}',
        ),
      );
      const c: ParentApiClient = new ParentApiClient(ad, BASE);
      const out: LessonDraftDto = await c.rejectLessonDraft('draft-1');
      expect(out.status).assertEqual('rejected');
      expect(out.reviewer).assertEqual('parent');
    });
  });

  describe('ParentApiClient.listPendingLessonDrafts', () => {
    it('parsesPendingPage', 0, async () => {
      const ad: StubAdapter = new StubAdapter();
      ad.responses.set(
        `GET ${BASE}/api/v1/admin/lesson-drafts?status=pending&page=1&size=10`,
        fakeOk(
          '{"items":[{"id":"draft-1","source_image_url":"u","extracted":{"category_id":"c","label_en":"a","label_zh":"b","story_zh":null,"words":[]},"edited_extracted":null,"status":"pending","created_at":"2026-05-01T00:00:00Z","reviewed_at":null,"reviewer":null,"model":"gpt-4o","prompt_version":1,"approval_summary":null}],"total":1,"page":1,"size":10}',
        ),
      );
      const c: ParentApiClient = new ParentApiClient(ad, BASE);
      const page: LessonDraftListPage = await c.listPendingLessonDrafts(1, 10);
      expect(page.items.length).assertEqual(1);
      expect(page.items[0].id).assertEqual('draft-1');
      expect(page.total).assertEqual(1);
    });
  });

  describe('ParentApiClient.importLesson', () => {
    it('rejectsImagesAboveTheMaxSize', 0, async () => {
      const c: ParentApiClient = new ParentApiClient(new StubAdapter(), BASE);
      const img: PickedImage = new PickedImage();
      img.bytes = new ArrayBuffer(1);
      img.mime = 'image/jpeg';
      img.filename = 'huge.jpg';
      img.sizeBytes = 9 * 1024 * 1024;
      let caught: LessonImportError | undefined = undefined;
      try {
        await c.importLesson(img);
      } catch (e) {
        if (e instanceof LessonImportError) {
          caught = e;
        }
      }
      expect(caught !== undefined).assertTrue();
      if (caught !== undefined) {
        expect(caught.code).assertEqual('TOO_LARGE');
      }
    });

    it('rejectsUnsupportedMimeTypes', 0, async () => {
      const c: ParentApiClient = new ParentApiClient(new StubAdapter(), BASE);
      const img: PickedImage = new PickedImage();
      img.bytes = new ArrayBuffer(1);
      img.mime = 'image/heic';
      img.filename = 'x.heic';
      img.sizeBytes = 1;
      let caught: LessonImportError | undefined = undefined;
      try {
        await c.importLesson(img);
      } catch (e) {
        if (e instanceof LessonImportError) {
          caught = e;
        }
      }
      expect(caught !== undefined).assertTrue();
      if (caught !== undefined) {
        expect(caught.code).assertEqual('BAD_MIME');
      }
    });

    it('postsMultipartAndParsesDraft', 0, async () => {
      class Stub201 implements IHttpRequester {
        lastUrl: string = '';
        lastOpts: object | null = null;
        async request(url: string, opts: object): Promise<http.HttpResponse> {
          this.lastUrl = url;
          this.lastOpts = opts;
          return fakeHttp(
            201,
            '{"id":"draft-9","source_image_url":"https://blob/x.jpg","extracted":{"category_id":"unit-9","label_en":"Unit 9","label_zh":"第九单元","story_zh":null,"words":[{"word":"cat","meaningZh":"猫","difficulty":1}]},"edited_extracted":null,"status":"pending","created_at":"2026-05-01T00:00:00Z","reviewed_at":null,"reviewer":null,"model":"gpt-4o","prompt_version":1,"approval_summary":null}',
          );
        }
      }
      const stub: Stub201 = new Stub201();
      const c: ParentApiClient = new ParentApiClient(new StubAdapter(), BASE);
      c.setHttpRequester(stub);

      const img: PickedImage = new PickedImage();
      img.bytes = (() => {
        const b: ArrayBuffer = new ArrayBuffer(4);
        const v: Uint8Array = new Uint8Array(b);
        v[0] = 0xff;
        v[1] = 0xd8;
        v[2] = 0xff;
        v[3] = 0xe0;
        return b;
      })();
      img.mime = 'image/jpeg';
      img.filename = 'lesson.jpg';
      img.sizeBytes = 4;

      const out: LessonDraftDto = await c.importLesson(img);
      expect(out.id).assertEqual('draft-9');
      expect(out.extracted.words[0].word).assertEqual('cat');
      expect(stub.lastUrl).assertEqual(`${BASE}/api/v1/admin/lessons/import`);
    });

    it('mapsHttpFailuresToLessonImportError', 0, async () => {
      class Stub413 implements IHttpRequester {
        async request(_url: string, _opts: object): Promise<http.HttpResponse> {
          return fakeHttp(413, '{"detail":{"error":{"code":"PAYLOAD_TOO_LARGE"}}}');
        }
      }
      const c: ParentApiClient = new ParentApiClient(new StubAdapter(), BASE);
      c.setHttpRequester(new Stub413());

      const img: PickedImage = new PickedImage();
      img.bytes = new ArrayBuffer(1);
      img.mime = 'image/jpeg';
      img.filename = 'x.jpg';
      img.sizeBytes = 1;

      let caught: LessonImportError | undefined = undefined;
      try {
        await c.importLesson(img);
      } catch (e) {
        if (e instanceof LessonImportError) {
          caught = e;
        }
      }
      expect(caught !== undefined).assertTrue();
      if (caught !== undefined) {
        expect(caught.code).assertEqual('HTTP');
        expect(caught.status).assertEqual(413);
      }
    });

    it('mapsTransportFailuresToLessonImportError', 0, async () => {
      class StubBoom implements IHttpRequester {
        async request(_url: string, _opts: object): Promise<http.HttpResponse> {
          throw new Error('DNS resolution failed');
        }
      }
      const c: ParentApiClient = new ParentApiClient(new StubAdapter(), BASE);
      c.setHttpRequester(new StubBoom());

      const img: PickedImage = new PickedImage();
      img.bytes = new ArrayBuffer(1);
      img.mime = 'image/jpeg';
      img.filename = 'x.jpg';
      img.sizeBytes = 1;

      let caught: LessonImportError | undefined = undefined;
      try {
        await c.importLesson(img);
      } catch (e) {
        if (e instanceof LessonImportError) {
          caught = e;
        }
      }
      expect(caught !== undefined).assertTrue();
      if (caught !== undefined) {
        expect(caught.code).assertEqual('NETWORK');
      }
    });
  });
}
