import { http } from '@kit.NetworkKit';
import { BusinessError } from '@ohos.base';

import { ParentFetchResult } from './ParentApiClient';
import { FamilyPackFetchAdapter } from './FamilyPackService';
import { GlobalPackFetchAdapter } from './GlobalPackService';

/**
 * V0.6.5.1 — single concrete network adapter shared by GlobalPackService
 * and FamilyPackService. Wraps `@kit.NetworkKit` with two extras the
 * pack services need on top of `ParentFetchAdapter`:
 *
 *   - `head(url, headers)` for cheap ETag probes.
 *   - `lastResponseHeader(name)` so the service can read the `ETag`
 *     header out of the most recent response without piping it through
 *     ParentFetchResult (which only carries body + status).
 *
 * The adapter is single-call-at-a-time; concurrent requests against
 * the same instance would race on the captured-headers slot. Since
 * each service constructs its own instance and serialises its own
 * fetches, that is fine in practice.
 */

const TIMEOUT_MS: number = 8000;

export class PackNetworkFetchAdapter implements FamilyPackFetchAdapter, GlobalPackFetchAdapter {
  private capturedHeaders: Record<string, string> = {};

  async get(url: string, headers: Record<string, string>): Promise<ParentFetchResult> {
    return this.send(url, http.RequestMethod.GET, headers, '');
  }

  async post(url: string, headers: Record<string, string>, body: string): Promise<ParentFetchResult> {
    return this.send(url, http.RequestMethod.POST, headers, body);
  }

  async put(url: string, headers: Record<string, string>, body: string): Promise<ParentFetchResult> {
    return this.send(url, http.RequestMethod.PUT, headers, body);
  }

  async patch(url: string, headers: Record<string, string>, body: string): Promise<ParentFetchResult> {
    return this.send(url, 'PATCH' as http.RequestMethod, headers, body);
  }

  async del(url: string, headers: Record<string, string>): Promise<ParentFetchResult> {
    return this.send(url, http.RequestMethod.DELETE, headers, '');
  }

  async head(url: string, headers: Record<string, string>): Promise<ParentFetchResult> {
    return this.send(url, http.RequestMethod.HEAD, headers, '');
  }

  lastResponseHeader(name: string): string {
    const direct: string | undefined = this.capturedHeaders[name];
    if (direct !== undefined) return direct;
    const lower: string | undefined = this.capturedHeaders[name.toLowerCase()];
    if (lower !== undefined) return lower;
    return '';
  }

  private async send(
    url: string,
    method: http.RequestMethod,
    headers: Record<string, string>,
    body: string,
  ): Promise<ParentFetchResult> {
    const out: ParentFetchResult = new ParentFetchResult();
    this.capturedHeaders = {};
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
      // Capture response headers for lastResponseHeader probes. The
      // header field is typed `Object` on older API levels and
      // `Record<string, string>` on newer ones; cast through unknown
      // so the cast is acceptable in ArkTS strict mode.
      const rawHeaders: Object | undefined = resp.header;
      if (rawHeaders !== undefined && rawHeaders !== null) {
        const asRec: Record<string, string> = rawHeaders as Record<string, string>;
        const keys: string[] = Object.keys(asRec);
        for (let i = 0; i < keys.length; i++) {
          const k: string = keys[i];
          const v: string = String(asRec[k]);
          this.capturedHeaders[k] = v;
        }
      }
    } catch (err) {
      const be: BusinessError = err as BusinessError;
      console.error(`PackNetworkFetchAdapter.send failed for ${url}: ${JSON.stringify(be)}`);
      out.status = 0;
      out.body = '';
    } finally {
      req.destroy();
    }
    return out;
  }
}
