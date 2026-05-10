import { CloudCredentials, CloudCredentialsSnapshot } from './CloudCredentials';
import { ParentFetchAdapter, ParentFetchResult } from './ParentApiClient';

/**
 * V0.6.7 — thin client for `POST /api/v1/child/unbind`.
 *
 * Behaviour:
 *  - Reads the device token from CloudCredentials.
 *  - POSTs the unbind endpoint with the device JWT.
 *  - On success (200) clears the credential bag so subsequent calls find
 *    the device unbound.
 *  - Network failure / non-2xx leaves credentials intact (the server
 *    binding may have been revoked from the parent web; the client will
 *    learn that on the next /child/* call returning 404 BINDING_REVOKED).
 */

const HEADER_AUTH: string = 'Authorization';
const HEADER_ACCEPT: string = 'Accept';
const CONTENT_JSON: string = 'application/json';

export class DeviceUnbindOutcome {
  ok: boolean = false;
  status: number = 0;
  cleared: boolean = false;
}

export class DeviceUnbindClient {
  private readonly creds: CloudCredentials;
  private readonly adapter: ParentFetchAdapter;
  private readonly baseUrl: string;

  constructor(creds: CloudCredentials, adapter: ParentFetchAdapter, baseUrl: string) {
    this.creds = creds;
    this.adapter = adapter;
    this.baseUrl = DeviceUnbindClient.trim(baseUrl);
  }

  async unbind(): Promise<DeviceUnbindOutcome> {
    const out: DeviceUnbindOutcome = new DeviceUnbindOutcome();
    const snap: CloudCredentialsSnapshot = await this.creds.load();
    if (!snap.isBound() || snap.deviceToken.length === 0) {
      // Nothing to unbind on the server; clear local state defensively.
      await this.creds.clearBinding();
      out.cleared = true;
      out.ok = true;
      return out;
    }
    const url: string = `${this.baseUrl}/api/v1/child/unbind`;
    const headers: Record<string, string> = {};
    headers[HEADER_ACCEPT] = CONTENT_JSON;
    headers[HEADER_AUTH] = `Bearer ${snap.deviceToken}`;
    try {
      const res: ParentFetchResult = await this.adapter.post(url, headers, '{}');
      out.status = res.status;
      // 404 means the binding was already revoked — still wipe credentials.
      if (res.status === 200 || res.status === 404) {
        await this.creds.clearBinding();
        out.cleared = true;
        out.ok = true;
      }
    } catch (_err) {
      out.ok = false;
    }
    return out;
  }

  private static trim(url: string): string {
    if (url.length === 0) {
      return url;
    }
    return url[url.length - 1] === '/' ? url.substring(0, url.length - 1) : url;
  }
}
