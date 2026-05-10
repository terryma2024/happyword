import { WordPackCache, WordPackCacheRecord } from './WordPackCache';
import { RemoteWordPackService, RemoteFetchResult } from './RemoteWordPackService';
import { latestPackUrl } from './RemoteWordPackConfig';

export enum SyncStatus {
  Updated = 'updated',
  UpToDate = 'up_to_date',
  NetworkError = 'network_error',
  HttpError = 'http_error',
  RejectedTooSmall = 'rejected_too_small',
}

/**
 * Result returned by `WordPackSyncService.syncOnce`. The UI maps
 * `status` to a toast and `cachedVersion`/`cachedSchemaVersion` to
 * the status-line under the sync button.
 */
export class SyncOutcome {
  status: SyncStatus = SyncStatus.NetworkError;
  cachedVersion: number = 0;
  cachedSchemaVersion: number = 0;
  httpStatus: number = 0;
}

const MIN_WORDS_PER_PACK: number = 3;

class PackHeader {
  version: number = 0;
  schemaVersion: number = 1;
  wordsLength: number = 0;
}

/**
 * V0.5 client follow-up: operator-triggered pack sync. The single
 * call site is the "同步词包" button on ConfigPage. There is no
 * background scheduler — the previous implementation auto-refreshed
 * on every cold start and ended up persisting whatever shape prod
 * happened to be in (including a 1-word pack that broke
 * QuestionGenerator).
 *
 * Cache contract:
 *   - 200 with >= MIN_WORDS_PER_PACK words → write envelope, return Updated.
 *   - 200 with too-small body → leave cache untouched, return RejectedTooSmall.
 *   - 304 → bump fetchedAt, return UpToDate (cache content unchanged).
 *   - 4xx/5xx → leave cache untouched, return HttpError.
 *   - status 0 (network error / disabled URL) → leave cache untouched,
 *     return NetworkError.
 */
export class WordPackSyncService {
  private readonly remote: RemoteWordPackService;
  private readonly cache: WordPackCache;
  private readonly url: string;

  constructor(remote: RemoteWordPackService, cache: WordPackCache, url?: string) {
    this.remote = remote;
    this.cache = cache;
    this.url = url !== undefined && url.length > 0 ? url : latestPackUrl();
  }

  async syncOnce(): Promise<SyncOutcome> {
    const out: SyncOutcome = new SyncOutcome();
    const existing: WordPackCacheRecord | undefined = await this.cache.readRecord();
    const ifNoneMatch: string | undefined =
      existing !== undefined && existing.etag.length > 0 ? existing.etag : undefined;

    const res: RemoteFetchResult = await this.remote.fetchLatest(this.url, ifNoneMatch);
    if (res.status === 0) {
      out.status = SyncStatus.NetworkError;
      WordPackSyncService.fillCachedVersionInfo(out, existing);
      return out;
    }
    if (res.status === 304) {
      await this.cache.touchFetchedAt();
      out.status = SyncStatus.UpToDate;
      WordPackSyncService.fillCachedVersionInfo(out, existing);
      return out;
    }
    if (res.status !== 200) {
      out.status = SyncStatus.HttpError;
      out.httpStatus = res.status;
      WordPackSyncService.fillCachedVersionInfo(out, existing);
      return out;
    }

    const parsed: PackHeader | undefined = WordPackSyncService.tryReadHeader(res.body);
    if (parsed === undefined || parsed.wordsLength < MIN_WORDS_PER_PACK) {
      out.status = SyncStatus.RejectedTooSmall;
      WordPackSyncService.fillCachedVersionInfo(out, existing);
      return out;
    }
    await this.cache.writeRecord(res.body, res.etag, parsed.schemaVersion);
    out.status = SyncStatus.Updated;
    out.cachedVersion = parsed.version;
    out.cachedSchemaVersion = parsed.schemaVersion;
    return out;
  }

  private static fillCachedVersionInfo(
    out: SyncOutcome,
    existing: WordPackCacheRecord | undefined,
  ): void {
    if (existing === undefined) {
      return;
    }
    const header: PackHeader | undefined = WordPackSyncService.tryReadHeader(existing.body);
    if (header !== undefined) {
      out.cachedVersion = header.version;
      out.cachedSchemaVersion = header.schemaVersion;
    }
  }

  private static tryReadHeader(body: string): PackHeader | undefined {
    let parsed: object;
    try {
      parsed = JSON.parse(body) as object;
    } catch (_err) {
      return undefined;
    }
    if (parsed === null || parsed === undefined) {
      return undefined;
    }
    const obj: Record<string, Object> = parsed as Record<string, Object>;
    const ver: Object | undefined = obj.version;
    const schemaVer: Object | undefined = obj.schema_version;
    const words: Object | undefined = obj.words;
    if (!Array.isArray(words)) {
      return undefined;
    }
    const header: PackHeader = new PackHeader();
    header.version = typeof ver === 'number' ? (ver as number) : 0;
    header.schemaVersion = typeof schemaVer === 'number' ? (schemaVer as number) : 1;
    header.wordsLength = (words as object[]).length;
    return header;
  }
}
