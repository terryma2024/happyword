import { http } from '@kit.NetworkKit';
import { BusinessError } from '@ohos.base';
import { buildSingleImageMultipart, MultipartResult } from './MultipartBuilder';

/**
 * ParentApiClient — V0.5.8.
 *
 * The V0.5.8 parent admin console is open (no login UI) so this client
 * sends plain JSON / multipart requests without an Authorization
 * header. Per-family auth returns in V0.6, at which point we'll add a
 * bearer token field back behind a small adapter.
 *
 * The client is split into a thin `ParentFetchAdapter` interface (so
 * tests inject a stub) and the real implementation that wraps
 * `@kit.NetworkKit`'s `http.HttpRequest`. Errors are mapped to
 * `ParentAuthError` (401/403, retained as-is so we can distinguish
 * future re-introduced auth failures from generic server errors) and
 * `ParentHttpError` (other non-2xx).
 *
 * See `docs/superpowers/specs/2026-05-01-v0.5.8-parent-admin-revamp-design.md`.
 */

const HEADER_CONTENT_TYPE: string = 'Content-Type';
const HEADER_ACCEPT: string = 'Accept';
const CONTENT_JSON: string = 'application/json';
const TIMEOUT_MS: number = 8000;

export class ParentAuthError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'ParentAuthError';
  }
}

export class ParentHttpError extends Error {
  status: number = 0;
  body: string = '';
  constructor(message: string, status: number, body: string) {
    super(message);
    this.name = 'ParentHttpError';
    this.status = status;
    this.body = body;
  }
}

export class ParentFetchResult {
  status: number = 0;
  body: string = '';
}

export interface ParentFetchAdapter {
  get(url: string, headers: Record<string, string>): Promise<ParentFetchResult>;
  post(url: string, headers: Record<string, string>, body: string): Promise<ParentFetchResult>;
  put(url: string, headers: Record<string, string>, body: string): Promise<ParentFetchResult>;
  patch(url: string, headers: Record<string, string>, body: string): Promise<ParentFetchResult>;
  del(url: string, headers: Record<string, string>): Promise<ParentFetchResult>;
}

export class ParentWordRow {
  id: string = '';
  word: string = '';
  meaningZh: string = '';
  category: string = '';
  difficulty: number = 1;
  illustrationUrl?: string;
  audioUrl?: string;
  createdAt: string = '';
  updatedAt: string = '';
}

export class ParentWordsPage {
  items: ParentWordRow[] = [];
  total: number = 0;
  page: number = 0;
  size: number = 0;
}

export class ParentPackListItem {
  version: number = 0;
  schemaVersion: number = 0;
  publishedAt: string = '';
  publishedBy: string = '';
  wordCount: number = 0;
  notes?: string;
}

export class ParentPackListPage {
  items: ParentPackListItem[] = [];
  total: number = 0;
  page: number = 0;
  size: number = 0;
}

export class ParentPackPublished {
  version: number = 0;
  schemaVersion: number = 0;
  wordCount: number = 0;
  publishedAt: string = '';
  publishedBy: string = '';
  notes?: string;
}

export class ParentStats {
  userCount: number = 0;
  wordCount: number = 0;
  categoryCount: number = 0;
  packCount: number = 0;
  latestVersion?: number;
  lastPublishedAt?: string;
  llmDraftPending: number = 0;
  lessonImportDraftPending: number = 0;
}

interface RawWordRow {
  id?: string;
  word?: string;
  meaning_zh?: string;
  category?: string;
  difficulty?: number;
  illustration_url?: string | null;
  audio_url?: string | null;
  created_at?: string;
  updated_at?: string;
}

interface RawWordsPage {
  items?: RawWordRow[];
  total?: number;
  page?: number;
  size?: number;
}

interface RawPackItem {
  version?: number;
  schema_version?: number;
  published_at?: string;
  published_by?: string;
  word_count?: number;
  notes?: string | null;
}

interface RawPackListPage {
  items?: RawPackItem[];
  total?: number;
  page?: number;
  size?: number;
}

interface RawPublishOut {
  version?: number;
  schema_version?: number;
  word_count?: number;
  published_at?: string;
  published_by?: string;
  notes?: string | null;
}

interface RawStatsOut {
  user_count?: number;
  word_count?: number;
  category_count?: number;
  pack_count?: number;
  latest_version?: number | null;
  last_published_at?: string | null;
  llm_draft_pending?: number;
  lesson_import_draft_pending?: number;
}

// ---------------------------------------------------------------------------
// V0.5.8: textbook lesson photo upload + LLM-driven word extraction.
// Mirrors server schemas in `server/app/schemas/admin_lesson.py` exactly.
//   - LessonExtractedWord: word + meaningZh + difficulty (1..5)
//   - LessonExtractedDto  ↔ LessonExtractedOut
//   - LessonDraftDto      ↔ LessonDraftOut
//   - LessonApproveSummaryDto ↔ LessonApproveOut (created_category/words/skipped)
// ---------------------------------------------------------------------------

export class LessonExtractedWord {
  word: string = '';
  meaningZh: string = '';
  difficulty: number = 1;
}

export class LessonExtractedDto {
  category_id: string = '';
  label_en: string = '';
  label_zh: string = '';
  story_zh?: string;
  words: LessonExtractedWord[] = [];
}

export class LessonCategorySummary {
  id: string = '';
  label_en: string = '';
  label_zh: string = '';
  story_zh?: string;
  source: string = '';
  source_image_url?: string;
  created_at: string = '';
  updated_at: string = '';
}

export class LessonApproveSummaryDto {
  created_category: LessonCategorySummary = new LessonCategorySummary();
  created_words: object[] = [];
  skipped_words: object[] = [];
}

export class LessonDraftDto {
  id: string = '';
  source_image_url: string = '';
  extracted: LessonExtractedDto = new LessonExtractedDto();
  edited_extracted?: LessonExtractedDto;
  status: string = 'pending';
  reviewer?: string;
  model: string = '';
  prompt_version: number = 1;
  created_at: string = '';
  reviewed_at?: string;
  approval_summary?: LessonApproveSummaryDto;
}

export class LessonDraftListPage {
  items: LessonDraftDto[] = [];
  total: number = 0;
  page: number = 0;
  size: number = 0;
}

interface RawLessonDraftListPage {
  items?: object[];
  total?: number;
  page?: number;
  size?: number;
}

/** A single photo selected from the gallery or camera, plus enough
 *  metadata for the server to validate and store it. */
export class PickedImage {
  bytes: ArrayBuffer = new ArrayBuffer(0);
  mime: string = '';      // 'image/jpeg' | 'image/png' | 'image/webp'
  filename: string = '';  // best-effort, e.g. 'lesson.jpg'
  sizeBytes: number = 0;
}

/** Failure mode for `importLesson`. `code` is one of:
 *  - TOO_LARGE: pre-flight, payload > IMPORT_MAX_BYTES
 *  - BAD_MIME:  pre-flight, mime not in ALLOWED_MIMES
 *  - NETWORK:   transport threw (timeout, DNS, etc.)
 *  - HTTP:      server returned non-2xx; `status` carries the code
 */
export class LessonImportError extends Error {
  code: string = '';
  status: number = 0;
  constructor(code: string, message: string, status: number) {
    super(message);
    this.name = 'LessonImportError';
    this.code = code;
    this.status = status;
  }
}

const IMPORT_MAX_BYTES: number = 8 * 1024 * 1024;
const IMPORT_TIMEOUT_MS: number = 60_000;
const ALLOWED_MIMES: string[] = ['image/jpeg', 'image/png', 'image/webp'];

/** Injection seam for the binary multipart upload — stubbed in tests
 *  so we don't touch @kit.NetworkKit's http.HttpRequest from CI. */
export interface IHttpRequester {
  request(url: string, opts: object): Promise<http.HttpResponse>;
}

export class RealHttpRequester implements IHttpRequester {
  async request(url: string, opts: object): Promise<http.HttpResponse> {
    const req: http.HttpRequest = http.createHttp();
    try {
      // `req.request` declares `throws BusinessError`; ArkTS requires us
      // to wrap the call so the compiler sees an explicit Promise rejection
      // instead of an unhandled synchronous throw escaping `request`.
      try {
        return await req.request(url, opts as http.HttpRequestOptions);
      } catch (e) {
        throw e as Error;
      }
    } finally {
      req.destroy();
    }
  }
}

export class ParentApiClient {
  private readonly adapter: ParentFetchAdapter;
  private readonly baseUrl: string;
  private httpRequester: IHttpRequester = new RealHttpRequester();

  constructor(adapter: ParentFetchAdapter, baseUrl: string) {
    this.adapter = adapter;
    this.baseUrl = ParentApiClient.trimTrailingSlash(baseUrl);
  }

  static withRealHttp(baseUrl: string): ParentApiClient {
    return new ParentApiClient(new RealParentFetchAdapter(), baseUrl);
  }

  /** Override the binary http path; tests inject a stub. */
  setHttpRequester(r: IHttpRequester): void {
    this.httpRequester = r;
  }

  async listWords(page: number, size: number): Promise<ParentWordsPage> {
    const url: string = `${this.baseUrl}/api/v1/admin/words?page=${page}&size=${size}`;
    const res: ParentFetchResult = await this.adapter.get(url, ParentApiClient.acceptJsonHeaders());
    ParentApiClient.assertOk(res, 'listWords');
    let parsed: RawWordsPage;
    try {
      parsed = JSON.parse(res.body) as RawWordsPage;
    } catch (_err) {
      throw new ParentHttpError('listWords: malformed response body', res.status, res.body);
    }
    const out: ParentWordsPage = new ParentWordsPage();
    out.total = typeof parsed.total === 'number' ? parsed.total : 0;
    out.page = typeof parsed.page === 'number' ? parsed.page : page;
    out.size = typeof parsed.size === 'number' ? parsed.size : size;
    if (Array.isArray(parsed.items)) {
      for (let i = 0; i < parsed.items.length; i++) {
        out.items.push(ParentApiClient.hydrateWord(parsed.items[i]));
      }
    }
    return out;
  }

  async getStats(): Promise<ParentStats> {
    const url: string = `${this.baseUrl}/api/v1/admin/stats`;
    const res: ParentFetchResult = await this.adapter.get(url, ParentApiClient.acceptJsonHeaders());
    ParentApiClient.assertOk(res, 'getStats');
    let parsed: RawStatsOut;
    try {
      parsed = JSON.parse(res.body) as RawStatsOut;
    } catch (_err) {
      throw new ParentHttpError('getStats: malformed response body', res.status, res.body);
    }
    const out: ParentStats = new ParentStats();
    out.userCount = typeof parsed.user_count === 'number' ? parsed.user_count : 0;
    out.wordCount = typeof parsed.word_count === 'number' ? parsed.word_count : 0;
    out.categoryCount = typeof parsed.category_count === 'number' ? parsed.category_count : 0;
    out.packCount = typeof parsed.pack_count === 'number' ? parsed.pack_count : 0;
    if (typeof parsed.latest_version === 'number') {
      out.latestVersion = parsed.latest_version;
    }
    if (typeof parsed.last_published_at === 'string' && parsed.last_published_at.length > 0) {
      out.lastPublishedAt = parsed.last_published_at;
    }
    out.llmDraftPending = typeof parsed.llm_draft_pending === 'number' ? parsed.llm_draft_pending : 0;
    out.lessonImportDraftPending =
      typeof parsed.lesson_import_draft_pending === 'number' ? parsed.lesson_import_draft_pending : 0;
    return out;
  }

  async listPacks(page: number, size: number): Promise<ParentPackListPage> {
    const url: string = `${this.baseUrl}/api/v1/admin/packs?page=${page}&size=${size}`;
    const res: ParentFetchResult = await this.adapter.get(url, ParentApiClient.acceptJsonHeaders());
    ParentApiClient.assertOk(res, 'listPacks');
    let parsed: RawPackListPage;
    try {
      parsed = JSON.parse(res.body) as RawPackListPage;
    } catch (_err) {
      throw new ParentHttpError('listPacks: malformed response body', res.status, res.body);
    }
    const out: ParentPackListPage = new ParentPackListPage();
    out.total = typeof parsed.total === 'number' ? parsed.total : 0;
    out.page = typeof parsed.page === 'number' ? parsed.page : page;
    out.size = typeof parsed.size === 'number' ? parsed.size : size;
    if (Array.isArray(parsed.items)) {
      for (let i = 0; i < parsed.items.length; i++) {
        out.items.push(ParentApiClient.hydratePackItem(parsed.items[i]));
      }
    }
    return out;
  }

  async publishPack(notes?: string): Promise<ParentPackPublished> {
    const url: string = `${this.baseUrl}/api/v1/admin/packs/publish`;
    const headers: Record<string, string> = ParentApiClient.jsonHeaders();
    const payload: Record<string, string | null> = {};
    if (notes !== undefined && notes.length > 0) {
      payload['notes'] = notes;
    }
    const body: string = JSON.stringify(payload);
    const res: ParentFetchResult = await this.adapter.post(url, headers, body);
    ParentApiClient.assertOk(res, 'publishPack');
    let parsed: RawPublishOut;
    try {
      parsed = JSON.parse(res.body) as RawPublishOut;
    } catch (_err) {
      throw new ParentHttpError('publishPack: malformed response body', res.status, res.body);
    }
    const out: ParentPackPublished = new ParentPackPublished();
    out.version = typeof parsed.version === 'number' ? parsed.version : 0;
    out.schemaVersion = typeof parsed.schema_version === 'number' ? parsed.schema_version : 0;
    out.wordCount = typeof parsed.word_count === 'number' ? parsed.word_count : 0;
    out.publishedAt = typeof parsed.published_at === 'string' ? parsed.published_at : '';
    out.publishedBy = typeof parsed.published_by === 'string' ? parsed.published_by : '';
    if (typeof parsed.notes === 'string' && parsed.notes.length > 0) {
      out.notes = parsed.notes;
    }
    return out;
  }

  // -------------------------------------------------------------------------
  // V0.5.8 lesson-import endpoints. Auth is omitted in V0.5.8 (open admin);
  // V0.6 will reattach a per-family bearer token.
  // -------------------------------------------------------------------------

  /** Upload a single textbook photo and let the server's vision model
   *  extract candidate words. The request is `multipart/form-data` with a
   *  single `image` part. Server returns a pending `LessonDraftDto`. */
  async importLesson(image: PickedImage): Promise<LessonDraftDto> {
    if (image.sizeBytes > IMPORT_MAX_BYTES) {
      throw new LessonImportError(
        'TOO_LARGE',
        `importLesson: image is ${image.sizeBytes} bytes, max ${IMPORT_MAX_BYTES}`,
        0,
      );
    }
    if (!ALLOWED_MIMES.includes(image.mime)) {
      throw new LessonImportError(
        'BAD_MIME',
        `importLesson: unsupported mime '${image.mime}'`,
        0,
      );
    }

    const url: string = `${this.baseUrl}/api/v1/admin/lessons/import`;
    const built: MultipartResult = buildSingleImageMultipart(
      'image',
      image.filename.length > 0 ? image.filename : 'lesson.jpg',
      image.mime,
      image.bytes,
    );
    const headers: Record<string, string> = {};
    headers[HEADER_CONTENT_TYPE] = `multipart/form-data; boundary=${built.boundary}`;
    headers[HEADER_ACCEPT] = CONTENT_JSON;

    let resp: http.HttpResponse;
    try {
      const opts: http.HttpRequestOptions = {
        method: http.RequestMethod.POST,
        header: headers,
        extraData: built.body,
        connectTimeout: IMPORT_TIMEOUT_MS,
        readTimeout: IMPORT_TIMEOUT_MS,
        expectDataType: http.HttpDataType.STRING,
      };
      resp = await this.httpRequester.request(url, opts);
    } catch (err) {
      const be: BusinessError = err as BusinessError;
      throw new LessonImportError(
        'NETWORK',
        `importLesson: transport failed (${JSON.stringify(be)})`,
        0,
      );
    }

    const status: number = resp.responseCode;
    const bodyStr: string = ParentApiClient.stringifyHttpBody(resp.result);
    if (status !== 200 && status !== 201) {
      throw new LessonImportError(
        'HTTP',
        `importLesson: HTTP ${status}: ${bodyStr}`,
        status,
      );
    }
    return ParentApiClient.parseLessonDraft(bodyStr, 'importLesson');
  }

  /** Fetch a single draft by id (used by the review page). */
  async getLessonDraft(draftId: string): Promise<LessonDraftDto> {
    const url: string = `${this.baseUrl}/api/v1/admin/lesson-drafts/${draftId}`;
    const res: ParentFetchResult = await this.adapter.get(url, ParentApiClient.acceptJsonHeaders());
    ParentApiClient.assertOk(res, 'getLessonDraft');
    return ParentApiClient.parseLessonDraft(res.body, 'getLessonDraft');
  }

  /** Persist the parent's edits before approval. Body shape is
   *  `{ "edited_extracted": {...} }` matching `LessonDraftPatchIn`. */
  async patchLessonDraft(draftId: string, edited: LessonExtractedDto): Promise<LessonDraftDto> {
    const url: string = `${this.baseUrl}/api/v1/admin/lesson-drafts/${draftId}`;
    const headers: Record<string, string> = ParentApiClient.jsonHeaders();
    const payload: Record<string, LessonExtractedDto> = { 'edited_extracted': edited };
    const body: string = JSON.stringify(payload);
    const res: ParentFetchResult = await this.adapter.patch(url, headers, body);
    ParentApiClient.assertOk(res, 'patchLessonDraft');
    return ParentApiClient.parseLessonDraft(res.body, 'patchLessonDraft');
  }

  /** Approve a pending draft. Server returns a summary describing the new
   *  category, the words it created, and any duplicates it skipped. */
  async approveLessonDraft(draftId: string): Promise<LessonApproveSummaryDto> {
    const url: string = `${this.baseUrl}/api/v1/admin/lesson-drafts/${draftId}/approve`;
    const headers: Record<string, string> = ParentApiClient.jsonHeaders();
    const res: ParentFetchResult = await this.adapter.post(url, headers, '{}');
    ParentApiClient.assertOk(res, 'approveLessonDraft');
    let raw: LessonApproveSummaryDto;
    try {
      raw = JSON.parse(res.body) as LessonApproveSummaryDto;
    } catch (_err) {
      throw new ParentHttpError('approveLessonDraft: malformed response body', res.status, res.body);
    }
    return raw;
  }

  /** Reject a pending draft. Server returns the (now-rejected) draft. */
  async rejectLessonDraft(draftId: string): Promise<LessonDraftDto> {
    const url: string = `${this.baseUrl}/api/v1/admin/lesson-drafts/${draftId}/reject`;
    const headers: Record<string, string> = ParentApiClient.jsonHeaders();
    const res: ParentFetchResult = await this.adapter.post(url, headers, '{}');
    ParentApiClient.assertOk(res, 'rejectLessonDraft');
    return ParentApiClient.parseLessonDraft(res.body, 'rejectLessonDraft');
  }

  /** List drafts filtered by status (default 'pending'). */
  async listPendingLessonDrafts(page: number, size: number): Promise<LessonDraftListPage> {
    const url: string =
      `${this.baseUrl}/api/v1/admin/lesson-drafts?status=pending&page=${page}&size=${size}`;
    const res: ParentFetchResult = await this.adapter.get(url, ParentApiClient.acceptJsonHeaders());
    ParentApiClient.assertOk(res, 'listPendingLessonDrafts');
    let parsed: RawLessonDraftListPage;
    try {
      parsed = JSON.parse(res.body) as RawLessonDraftListPage;
    } catch (_err) {
      throw new ParentHttpError('listPendingLessonDrafts: malformed response body', res.status, res.body);
    }
    const out: LessonDraftListPage = new LessonDraftListPage();
    out.total = typeof parsed.total === 'number' ? parsed.total : 0;
    out.page = typeof parsed.page === 'number' ? parsed.page : page;
    out.size = typeof parsed.size === 'number' ? parsed.size : size;
    if (Array.isArray(parsed.items)) {
      for (let i = 0; i < parsed.items.length; i++) {
        // Items are LessonDraftOut JSON objects — re-stringify a single
        // item and reuse the same parser used for single-draft endpoints.
        const item: object = parsed.items[i];
        out.items.push(ParentApiClient.parseLessonDraft(JSON.stringify(item), 'listPendingLessonDrafts'));
      }
    }
    return out;
  }

  private static stringifyHttpBody(result: string | Object | ArrayBuffer): string {
    if (typeof result === 'string') {
      return result;
    }
    if (result === undefined) {
      return '';
    }
    return JSON.stringify(result);
  }

  private static parseLessonDraft(bodyStr: string, op: string): LessonDraftDto {
    try {
      return JSON.parse(bodyStr) as LessonDraftDto;
    } catch (_err) {
      throw new ParentHttpError(`${op}: malformed response body`, 0, bodyStr);
    }
  }

  private static jsonHeaders(): Record<string, string> {
    const h: Record<string, string> = {};
    h[HEADER_CONTENT_TYPE] = CONTENT_JSON;
    h[HEADER_ACCEPT] = CONTENT_JSON;
    return h;
  }

  private static acceptJsonHeaders(): Record<string, string> {
    const h: Record<string, string> = {};
    h[HEADER_ACCEPT] = CONTENT_JSON;
    return h;
  }

  private static assertOk(res: ParentFetchResult, op: string): void {
    if (res.status === 200 || res.status === 201 || res.status === 204) {
      return;
    }
    if (res.status === 401 || res.status === 403) {
      throw new ParentAuthError(`${op}: HTTP ${res.status}`);
    }
    throw new ParentHttpError(`${op}: HTTP ${res.status}`, res.status, res.body);
  }

  private static hydrateWord(raw: RawWordRow): ParentWordRow {
    const w: ParentWordRow = new ParentWordRow();
    w.id = typeof raw.id === 'string' ? raw.id : '';
    w.word = typeof raw.word === 'string' ? raw.word : '';
    w.meaningZh = typeof raw.meaning_zh === 'string' ? raw.meaning_zh : '';
    w.category = typeof raw.category === 'string' ? raw.category : '';
    w.difficulty = typeof raw.difficulty === 'number' ? raw.difficulty : 1;
    if (typeof raw.illustration_url === 'string' && raw.illustration_url.length > 0) {
      w.illustrationUrl = raw.illustration_url;
    }
    if (typeof raw.audio_url === 'string' && raw.audio_url.length > 0) {
      w.audioUrl = raw.audio_url;
    }
    w.createdAt = typeof raw.created_at === 'string' ? raw.created_at : '';
    w.updatedAt = typeof raw.updated_at === 'string' ? raw.updated_at : '';
    return w;
  }

  private static hydratePackItem(raw: RawPackItem): ParentPackListItem {
    const p: ParentPackListItem = new ParentPackListItem();
    p.version = typeof raw.version === 'number' ? raw.version : 0;
    p.schemaVersion = typeof raw.schema_version === 'number' ? raw.schema_version : 0;
    p.publishedAt = typeof raw.published_at === 'string' ? raw.published_at : '';
    p.publishedBy = typeof raw.published_by === 'string' ? raw.published_by : '';
    p.wordCount = typeof raw.word_count === 'number' ? raw.word_count : 0;
    if (typeof raw.notes === 'string' && raw.notes.length > 0) {
      p.notes = raw.notes;
    }
    return p;
  }

  private static trimTrailingSlash(p: string): string {
    let end: number = p.length;
    while (end > 0 && p.charAt(end - 1) === '/') {
      end -= 1;
    }
    return p.substring(0, end);
  }
}

export class RealParentFetchAdapter implements ParentFetchAdapter {
  async get(url: string, headers: Record<string, string>): Promise<ParentFetchResult> {
    return RealParentFetchAdapter.send(url, http.RequestMethod.GET, headers, '');
  }

  async post(url: string, headers: Record<string, string>, body: string): Promise<ParentFetchResult> {
    return RealParentFetchAdapter.send(url, http.RequestMethod.POST, headers, body);
  }

  async put(url: string, headers: Record<string, string>, body: string): Promise<ParentFetchResult> {
    return RealParentFetchAdapter.send(url, http.RequestMethod.PUT, headers, body);
  }

  async patch(url: string, headers: Record<string, string>, body: string): Promise<ParentFetchResult> {
    // The Harmony NetworkKit `RequestMethod` enum (API 20) does not
    // include PATCH (only OPTIONS / GET / HEAD / POST / PUT / DELETE /
    // TRACE / CONNECT — see @ohos.net.http.d.ts). At runtime libcurl
    // forwards whatever method string we pass, so we cast a plain
    // "PATCH" literal to the enum type.
    return RealParentFetchAdapter.send(url, 'PATCH' as http.RequestMethod, headers, body);
  }

  async del(url: string, headers: Record<string, string>): Promise<ParentFetchResult> {
    return RealParentFetchAdapter.send(url, http.RequestMethod.DELETE, headers, '');
  }

  private static async send(
    url: string,
    method: http.RequestMethod,
    headers: Record<string, string>,
    body: string,
  ): Promise<ParentFetchResult> {
    const out: ParentFetchResult = new ParentFetchResult();
    const req: http.HttpRequest = http.createHttp();
    try {
      const resp: http.HttpResponse = await req.request(url, {
        method,
        header: headers,
        extraData: body.length > 0 ? body : undefined,
        connectTimeout: TIMEOUT_MS,
        readTimeout: TIMEOUT_MS,
        expectDataType: http.HttpDataType.STRING,
      });
      out.status = resp.responseCode;
      const result: string | Object | ArrayBuffer = resp.result;
      if (typeof result === 'string') {
        out.body = result;
      } else if (result !== undefined) {
        out.body = JSON.stringify(result);
      }
    } catch (err) {
      const be: BusinessError = err as BusinessError;
      console.error(`ParentApiClient.send failed for ${url}: ${JSON.stringify(be)}`);
      out.status = 0;
      out.body = '';
    } finally {
      req.destroy();
    }
    return out;
  }
}
