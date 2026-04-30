import { http } from '@kit.NetworkKit';
import { BusinessError } from '@ohos.base';
import { REMOTE_FETCH_TIMEOUT_MS } from './RemoteWordPackConfig';

export class RemoteFetchResult {
  status: number = 0;
  body: string = '';
  etag: string = '';
}

export interface HttpRequester {
  fetch(
    url: string,
    ifNoneMatch: string | undefined,
    timeoutMs: number,
  ): Promise<RemoteFetchResult>;
}

class RealHttpRequester implements HttpRequester {
  async fetch(
    url: string,
    ifNoneMatch: string | undefined,
    timeoutMs: number,
  ): Promise<RemoteFetchResult> {
    const req: http.HttpRequest = http.createHttp();
    const headers: Record<string, string> = { 'Accept': 'application/json' };
    if (ifNoneMatch !== undefined && ifNoneMatch.length > 0) {
      headers['If-None-Match'] = ifNoneMatch;
    }
    try {
      const resp: http.HttpResponse = await req.request(url, {
        method: http.RequestMethod.GET,
        header: headers,
        connectTimeout: timeoutMs,
        readTimeout: timeoutMs,
      });
      const out: RemoteFetchResult = new RemoteFetchResult();
      out.status = resp.responseCode;
      out.body =
        typeof resp.result === 'string' ? resp.result : JSON.stringify(resp.result);
      const respHeader: Record<string, string> = (resp.header ?? {}) as Record<string, string>;
      out.etag = respHeader['etag'] ?? respHeader['ETag'] ?? '';
      return out;
    } finally {
      req.destroy();
    }
  }
}

/**
 * V0.5.1: thin HTTP wrapper around the public /packs/latest.json endpoint.
 *
 * Always returns a RemoteFetchResult, never throws — callers just check `status`.
 * Status 0 = "cannot use" (network error / timeout / disabled URL),
 * 200 = fresh body, 304 = cache still valid.
 */
export class RemoteWordPackService {
  private requester: HttpRequester = new RealHttpRequester();

  injectHttpRequesterForTest(r: HttpRequester): void {
    this.requester = r;
  }

  async fetchLatest(
    url: string,
    ifNoneMatch: string | undefined,
  ): Promise<RemoteFetchResult> {
    if (url.length === 0) {
      return new RemoteFetchResult();
    }
    try {
      return await this.requester.fetch(url, ifNoneMatch, REMOTE_FETCH_TIMEOUT_MS);
    } catch (err) {
      const be: BusinessError = err as BusinessError;
      console.error(`RemoteWordPackService.fetchLatest failed: ${JSON.stringify(be)}`);
      return new RemoteFetchResult();
    }
  }
}
