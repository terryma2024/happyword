import { describe, it, expect } from '@ohos/hypium';
import { WordPackCache, WordPackCacheRecord } from '../main/ets/services/WordPackCache';
import {
  RemoteWordPackService,
  RemoteFetchResult,
  HttpRequester,
} from '../main/ets/services/RemoteWordPackService';
import {
  WordPackSyncService,
  SyncOutcome,
  SyncStatus,
} from '../main/ets/services/WordPackSyncService';
import { StringPreferencesLike } from '../main/ets/services/WrongAnswerStore';

class MapPrefs implements StringPreferencesLike {
  readonly store: Map<string, string> = new Map<string, string>();
  async getString(key: string): Promise<string> {
    return this.store.get(key) ?? '';
  }
  async putString(key: string, value: string): Promise<void> {
    this.store.set(key, value);
  }
  async flush(): Promise<void> {}
}

class StubRequester implements HttpRequester {
  status: number = 200;
  body: string = '';
  etag: string = '';
  lastIfNoneMatch: string | undefined = undefined;
  callCount: number = 0;
  async fetch(
    _url: string,
    ifNoneMatch: string | undefined,
    _t: number,
  ): Promise<RemoteFetchResult> {
    this.callCount += 1;
    this.lastIfNoneMatch = ifNoneMatch;
    const r: RemoteFetchResult = new RemoteFetchResult();
    r.status = this.status;
    r.body = this.body;
    r.etag = this.etag;
    return r;
  }
}

const PACK_THREE: string =
  '{"version":3,"schema_version":2,"published_at":"2026-05-01T00:00:00Z","words":[' +
  '{"id":"fruit-apple","word":"apple","meaningZh":"苹果","category":"fruit","difficulty":1},' +
  '{"id":"fruit-banana","word":"banana","meaningZh":"香蕉","category":"fruit","difficulty":1},' +
  '{"id":"fruit-pear","word":"pear","meaningZh":"梨","category":"fruit","difficulty":1}' +
  ']}';

const ONE_WORD_PACK: string =
  '{"version":1,"schema_version":1,"words":[' +
  '{"id":"fruit-apple","word":"apple","meaningZh":"苹果","category":"fruit","difficulty":1}' +
  ']}';

class SvcBundle {
  svc: WordPackSyncService = new WordPackSyncService(
    new RemoteWordPackService(),
    new WordPackCache(),
    'https://x',
  );
  cache: WordPackCache = new WordPackCache();
  stub: StubRequester = new StubRequester();
}

function makeBundle(): SvcBundle {
  const cache: WordPackCache = new WordPackCache();
  cache.injectPreferencesForTest(new MapPrefs());
  const remote: RemoteWordPackService = new RemoteWordPackService();
  const stub: StubRequester = new StubRequester();
  remote.injectHttpRequesterForTest(stub);
  const svc: WordPackSyncService = new WordPackSyncService(
    remote,
    cache,
    'https://x/api/v1/packs/latest.json',
  );
  const out: SvcBundle = new SvcBundle();
  out.svc = svc;
  out.cache = cache;
  out.stub = stub;
  return out;
}

export default function wordPackSyncServiceTest() {
  describe('WordPackSyncService', () => {
    it('writesEnvelopeOn200', 0, async () => {
      const b: SvcBundle = makeBundle();
      b.stub.status = 200;
      b.stub.body = PACK_THREE;
      b.stub.etag = '"3"';
      const out: SyncOutcome = await b.svc.syncOnce();
      expect(out.status).assertEqual(SyncStatus.Updated);
      expect(out.cachedVersion).assertEqual(3);
      expect(out.cachedSchemaVersion).assertEqual(2);
      const rec: WordPackCacheRecord | undefined = await b.cache.readRecord();
      expect(rec !== undefined).assertTrue();
      if (rec !== undefined) {
        expect(rec.body).assertEqual(PACK_THREE);
        expect(rec.etag).assertEqual('"3"');
        expect(rec.schemaVersion).assertEqual(2);
      }
    });

    it('sendsIfNoneMatchWhenEnvelopePresent', 0, async () => {
      const b: SvcBundle = makeBundle();
      await b.cache.writeRecord(PACK_THREE, '"3"', 2);
      b.stub.status = 304;
      const out: SyncOutcome = await b.svc.syncOnce();
      expect(b.stub.lastIfNoneMatch).assertEqual('"3"');
      expect(out.status).assertEqual(SyncStatus.UpToDate);
      expect(out.cachedVersion).assertEqual(3);
    });

    it('keepsCacheOnNetworkError', 0, async () => {
      const b: SvcBundle = makeBundle();
      await b.cache.writeRecord(PACK_THREE, '"3"', 2);
      b.stub.status = 0;
      const out: SyncOutcome = await b.svc.syncOnce();
      expect(out.status).assertEqual(SyncStatus.NetworkError);
      const rec: WordPackCacheRecord | undefined = await b.cache.readRecord();
      expect(rec !== undefined).assertTrue();
      if (rec !== undefined) {
        expect(rec.body).assertEqual(PACK_THREE);
      }
    });

    it('reportsHttpErrorAndKeepsCache', 0, async () => {
      const b: SvcBundle = makeBundle();
      await b.cache.writeRecord(PACK_THREE, '"3"', 2);
      b.stub.status = 500;
      b.stub.body = '{"detail":"oops"}';
      const out: SyncOutcome = await b.svc.syncOnce();
      expect(out.status).assertEqual(SyncStatus.HttpError);
      expect(out.httpStatus).assertEqual(500);
      const rec: WordPackCacheRecord | undefined = await b.cache.readRecord();
      expect(rec !== undefined).assertTrue();
      if (rec !== undefined) {
        expect(rec.body).assertEqual(PACK_THREE);
      }
    });

    it('rejects200WithFewerThanThreeWords', 0, async () => {
      // Defence in depth: even if the server hands us a 1-word pack
      // again, the sync must refuse it. Otherwise next bootstrap path
      // would still fall through to rawfile, but the cache slot would
      // be polluted.
      const b: SvcBundle = makeBundle();
      b.stub.status = 200;
      b.stub.body = ONE_WORD_PACK;
      b.stub.etag = '"1"';
      const out: SyncOutcome = await b.svc.syncOnce();
      expect(out.status).assertEqual(SyncStatus.RejectedTooSmall);
      const rec: WordPackCacheRecord | undefined = await b.cache.readRecord();
      expect(rec === undefined).assertTrue();
    });

    it('omitsIfNoneMatchOnFreshCache', 0, async () => {
      const b: SvcBundle = makeBundle();
      b.stub.status = 200;
      b.stub.body = PACK_THREE;
      b.stub.etag = '"5"';
      await b.svc.syncOnce();
      expect(b.stub.lastIfNoneMatch).assertEqual(undefined);
    });
  });
}
