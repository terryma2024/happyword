import { describe, it, expect } from '@ohos/hypium';
import {
  RemoteWordPackService,
  HttpRequester,
  RemoteFetchResult,
} from '../main/ets/services/RemoteWordPackService';

class StubRequester implements HttpRequester {
  status: number = 200;
  body: string = '';
  capturedUrl: string = '';
  capturedHeader: string | undefined;
  shouldThrow: boolean = false;
  async fetch(
    url: string,
    ifNoneMatch: string | undefined,
    _timeoutMs: number,
  ): Promise<RemoteFetchResult> {
    this.capturedUrl = url;
    this.capturedHeader = ifNoneMatch;
    if (this.shouldThrow) {
      throw new Error('network down');
    }
    const r: RemoteFetchResult = new RemoteFetchResult();
    r.status = this.status;
    r.body = this.body;
    r.etag = '';
    return r;
  }
}

export default function remoteWordPackServiceTest() {
  describe('RemoteWordPackService', () => {
    it('returnsBodyOn200', 0, async () => {
      const svc: RemoteWordPackService = new RemoteWordPackService();
      const stub: StubRequester = new StubRequester();
      stub.status = 200;
      stub.body = '{"words":[]}';
      svc.injectHttpRequesterForTest(stub);

      const out: RemoteFetchResult = await svc.fetchLatest(
        'https://x/api/v1/packs/latest.json',
        undefined,
      );
      expect(out.status).assertEqual(200);
      expect(out.body).assertEqual('{"words":[]}');
    });

    it('passesIfNoneMatchHeaderWhenEtagProvided', 0, async () => {
      const svc: RemoteWordPackService = new RemoteWordPackService();
      const stub: StubRequester = new StubRequester();
      svc.injectHttpRequesterForTest(stub);
      await svc.fetchLatest('https://x/api/v1/packs/latest.json', '"42"');
      expect(stub.capturedHeader ?? '').assertEqual('"42"');
    });

    it('returnsZeroStatusOnNetworkError', 0, async () => {
      const svc: RemoteWordPackService = new RemoteWordPackService();
      const stub: StubRequester = new StubRequester();
      stub.shouldThrow = true;
      svc.injectHttpRequesterForTest(stub);
      const out: RemoteFetchResult = await svc.fetchLatest(
        'https://x/api/v1/packs/latest.json',
        undefined,
      );
      expect(out.status).assertEqual(0);
    });

    it('returnsZeroStatusWhenUrlEmpty', 0, async () => {
      const svc: RemoteWordPackService = new RemoteWordPackService();
      const stub: StubRequester = new StubRequester();
      svc.injectHttpRequesterForTest(stub);
      const out: RemoteFetchResult = await svc.fetchLatest('', undefined);
      expect(out.status).assertEqual(0);
      expect(stub.capturedUrl).assertEqual('');
    });
  });
}
