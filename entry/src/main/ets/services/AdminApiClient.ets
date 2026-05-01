import { http } from '@kit.NetworkKit';
import { BusinessError } from '@ohos.base';

/**
 * AdminApiClient — V0.5.F MVP. The full v0.5 client follow-up plan
 * sketches a 6-page admin shell wrapping the entire server admin
 * surface (words CRUD, drafts, lesson import, asset upload, packs,
 * stats). To keep this commit reviewable and reduce on-device risk,
 * we ship the highest-value endpoints (login, listWords, getStats,
 * listPacks, publishPack) plus the supporting auth + http plumbing,
 * and defer the rest to follow-up commits. Word CRUD, draft generation
 * and asset upload remain CLI-only via the existing server scripts
 * (`server/scripts/seed_from_rawfile.py`, `publish_pack.py`,
 * `backup_pack.py`).
 *
 * The client is split into a thin `AdminFetchAdapter` interface (so
 * tests inject a stub) and the real implementation that wraps
 * `@kit.NetworkKit`'s `http.HttpRequest`. Errors are mapped to
 * `AdminAuthError` (401) and `AdminHttpError` (other non-2xx); the
 * caller is responsible for redirecting to login on AdminAuthError.
 */

const HEADER_AUTHORIZATION: string = 'Authorization';
const HEADER_CONTENT_TYPE: string = 'Content-Type';
const HEADER_ACCEPT: string = 'Accept';
const CONTENT_JSON: string = 'application/json';
const TIMEOUT_MS: number = 8000;

export class AdminAuthError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'AdminAuthError';
  }
}

export class AdminHttpError extends Error {
  status: number = 0;
  body: string = '';
  constructor(message: string, status: number, body: string) {
    super(message);
    this.name = 'AdminHttpError';
    this.status = status;
    this.body = body;
  }
}

export class AdminFetchResult {
  status: number = 0;
  body: string = '';
}

export interface AdminFetchAdapter {
  get(url: string, headers: Record<string, string>): Promise<AdminFetchResult>;
  post(url: string, headers: Record<string, string>, body: string): Promise<AdminFetchResult>;
  put(url: string, headers: Record<string, string>, body: string): Promise<AdminFetchResult>;
  del(url: string, headers: Record<string, string>): Promise<AdminFetchResult>;
}

export class AdminWordRow {
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

export class AdminWordsPage {
  items: AdminWordRow[] = [];
  total: number = 0;
  page: number = 0;
  size: number = 0;
}

export class AdminPackListItem {
  version: number = 0;
  schemaVersion: number = 0;
  publishedAt: string = '';
  publishedBy: string = '';
  wordCount: number = 0;
  notes?: string;
}

export class AdminPackListPage {
  items: AdminPackListItem[] = [];
  total: number = 0;
  page: number = 0;
  size: number = 0;
}

export class AdminPackPublished {
  version: number = 0;
  schemaVersion: number = 0;
  wordCount: number = 0;
  publishedAt: string = '';
  publishedBy: string = '';
  notes?: string;
}

export class AdminStats {
  userCount: number = 0;
  wordCount: number = 0;
  categoryCount: number = 0;
  packCount: number = 0;
  latestVersion?: number;
  lastPublishedAt?: string;
  llmDraftPending: number = 0;
  lessonImportDraftPending: number = 0;
}

interface RawLoginResponse {
  access_token?: string;
  token_type?: string;
  expires_in?: number;
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

export class AdminApiClient {
  private readonly adapter: AdminFetchAdapter;
  private readonly baseUrl: string;
  private bearerToken: string = '';

  constructor(adapter: AdminFetchAdapter, baseUrl: string) {
    this.adapter = adapter;
    this.baseUrl = AdminApiClient.trimTrailingSlash(baseUrl);
  }

  static withRealHttp(baseUrl: string): AdminApiClient {
    return new AdminApiClient(new RealAdminFetchAdapter(), baseUrl);
  }

  setBearerToken(token: string): void {
    this.bearerToken = token;
  }

  clearBearerToken(): void {
    this.bearerToken = '';
  }

  hasBearerToken(): boolean {
    return this.bearerToken.length > 0;
  }

  async login(username: string, password: string): Promise<string> {
    const url: string = `${this.baseUrl}/api/v1/auth/login`;
    const body: string = JSON.stringify({ username, password });
    const headers: Record<string, string> = AdminApiClient.jsonHeaders();
    const res: AdminFetchResult = await this.adapter.post(url, headers, body);
    AdminApiClient.assertOk(res, 'login');
    let parsed: RawLoginResponse;
    try {
      parsed = JSON.parse(res.body) as RawLoginResponse;
    } catch (_err) {
      throw new AdminHttpError('login: malformed response body', res.status, res.body);
    }
    const token: string | undefined = parsed.access_token;
    if (token === undefined || token.length === 0) {
      throw new AdminHttpError('login: missing access_token', res.status, res.body);
    }
    this.bearerToken = token;
    return token;
  }

  async listWords(page: number, size: number): Promise<AdminWordsPage> {
    const url: string = `${this.baseUrl}/api/v1/admin/words?page=${page}&size=${size}`;
    const res: AdminFetchResult = await this.adapter.get(url, this.authHeaders());
    AdminApiClient.assertOk(res, 'listWords');
    let parsed: RawWordsPage;
    try {
      parsed = JSON.parse(res.body) as RawWordsPage;
    } catch (_err) {
      throw new AdminHttpError('listWords: malformed response body', res.status, res.body);
    }
    const out: AdminWordsPage = new AdminWordsPage();
    out.total = typeof parsed.total === 'number' ? parsed.total : 0;
    out.page = typeof parsed.page === 'number' ? parsed.page : page;
    out.size = typeof parsed.size === 'number' ? parsed.size : size;
    if (Array.isArray(parsed.items)) {
      for (let i = 0; i < parsed.items.length; i++) {
        out.items.push(AdminApiClient.hydrateWord(parsed.items[i]));
      }
    }
    return out;
  }

  async getStats(): Promise<AdminStats> {
    const url: string = `${this.baseUrl}/api/v1/admin/stats`;
    const res: AdminFetchResult = await this.adapter.get(url, this.authHeaders());
    AdminApiClient.assertOk(res, 'getStats');
    let parsed: RawStatsOut;
    try {
      parsed = JSON.parse(res.body) as RawStatsOut;
    } catch (_err) {
      throw new AdminHttpError('getStats: malformed response body', res.status, res.body);
    }
    const out: AdminStats = new AdminStats();
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

  async listPacks(page: number, size: number): Promise<AdminPackListPage> {
    const url: string = `${this.baseUrl}/api/v1/admin/packs?page=${page}&size=${size}`;
    const res: AdminFetchResult = await this.adapter.get(url, this.authHeaders());
    AdminApiClient.assertOk(res, 'listPacks');
    let parsed: RawPackListPage;
    try {
      parsed = JSON.parse(res.body) as RawPackListPage;
    } catch (_err) {
      throw new AdminHttpError('listPacks: malformed response body', res.status, res.body);
    }
    const out: AdminPackListPage = new AdminPackListPage();
    out.total = typeof parsed.total === 'number' ? parsed.total : 0;
    out.page = typeof parsed.page === 'number' ? parsed.page : page;
    out.size = typeof parsed.size === 'number' ? parsed.size : size;
    if (Array.isArray(parsed.items)) {
      for (let i = 0; i < parsed.items.length; i++) {
        out.items.push(AdminApiClient.hydratePackItem(parsed.items[i]));
      }
    }
    return out;
  }

  async publishPack(notes?: string): Promise<AdminPackPublished> {
    const url: string = `${this.baseUrl}/api/v1/admin/packs/publish`;
    const headers: Record<string, string> = this.authJsonHeaders();
    const payload: Record<string, string | null> = {};
    if (notes !== undefined && notes.length > 0) {
      payload['notes'] = notes;
    }
    const body: string = JSON.stringify(payload);
    const res: AdminFetchResult = await this.adapter.post(url, headers, body);
    AdminApiClient.assertOk(res, 'publishPack');
    let parsed: RawPublishOut;
    try {
      parsed = JSON.parse(res.body) as RawPublishOut;
    } catch (_err) {
      throw new AdminHttpError('publishPack: malformed response body', res.status, res.body);
    }
    const out: AdminPackPublished = new AdminPackPublished();
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

  private authHeaders(): Record<string, string> {
    const h: Record<string, string> = AdminApiClient.acceptJsonHeaders();
    if (this.bearerToken.length > 0) {
      h[HEADER_AUTHORIZATION] = `Bearer ${this.bearerToken}`;
    }
    return h;
  }

  private authJsonHeaders(): Record<string, string> {
    const h: Record<string, string> = AdminApiClient.jsonHeaders();
    if (this.bearerToken.length > 0) {
      h[HEADER_AUTHORIZATION] = `Bearer ${this.bearerToken}`;
    }
    return h;
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

  private static assertOk(res: AdminFetchResult, op: string): void {
    if (res.status === 200 || res.status === 201 || res.status === 204) {
      return;
    }
    if (res.status === 401 || res.status === 403) {
      throw new AdminAuthError(`${op}: HTTP ${res.status}`);
    }
    throw new AdminHttpError(`${op}: HTTP ${res.status}`, res.status, res.body);
  }

  private static hydrateWord(raw: RawWordRow): AdminWordRow {
    const w: AdminWordRow = new AdminWordRow();
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

  private static hydratePackItem(raw: RawPackItem): AdminPackListItem {
    const p: AdminPackListItem = new AdminPackListItem();
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

class RealAdminFetchAdapter implements AdminFetchAdapter {
  async get(url: string, headers: Record<string, string>): Promise<AdminFetchResult> {
    return RealAdminFetchAdapter.send(url, http.RequestMethod.GET, headers, '');
  }

  async post(url: string, headers: Record<string, string>, body: string): Promise<AdminFetchResult> {
    return RealAdminFetchAdapter.send(url, http.RequestMethod.POST, headers, body);
  }

  async put(url: string, headers: Record<string, string>, body: string): Promise<AdminFetchResult> {
    return RealAdminFetchAdapter.send(url, http.RequestMethod.PUT, headers, body);
  }

  async del(url: string, headers: Record<string, string>): Promise<AdminFetchResult> {
    return RealAdminFetchAdapter.send(url, http.RequestMethod.DELETE, headers, '');
  }

  private static async send(
    url: string,
    method: http.RequestMethod,
    headers: Record<string, string>,
    body: string,
  ): Promise<AdminFetchResult> {
    const out: AdminFetchResult = new AdminFetchResult();
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
      console.error(`AdminApiClient.send failed for ${url}: ${JSON.stringify(be)}`);
      out.status = 0;
      out.body = '';
    } finally {
      req.destroy();
    }
    return out;
  }
}
