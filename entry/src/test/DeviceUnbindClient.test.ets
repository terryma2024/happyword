import { describe, it, expect } from '@ohos/hypium';
import {
  DeviceUnbindClient,
  DeviceUnbindOutcome,
} from '../main/ets/services/DeviceUnbindClient';
import { CloudCredentials, CloudCredentialsSnapshot } from '../main/ets/services/CloudCredentials';
import { ParentFetchAdapter, ParentFetchResult } from '../main/ets/services/ParentApiClient';
import { StringPreferencesLike } from '../main/ets/services/WrongAnswerStore';

const BASE: string = 'https://happyword.vercel.app';

class MemPrefs implements StringPreferencesLike {
  store: Map<string, string> = new Map<string, string>();
  async getString(key: string): Promise<string> {
    return this.store.get(key) ?? '';
  }
  async putString(key: string, value: string): Promise<void> {
    this.store.set(key, value);
  }
  async flush(): Promise<void> {}
}

class CapturedRequest {
  url: string = '';
  auth: string = '';
}

class StubAdapter implements ParentFetchAdapter {
  responses: ParentFetchResult[] = [];
  requests: CapturedRequest[] = [];
  failNetwork: boolean = false;

  enqueue(status: number, body: string): void {
    const r: ParentFetchResult = new ParentFetchResult();
    r.status = status;
    r.body = body;
    this.responses.push(r);
  }

  async get(_url: string, _h: Record<string, string>): Promise<ParentFetchResult> {
    return this.serve();
  }

  async post(url: string, headers: Record<string, string>, _body: string): Promise<ParentFetchResult> {
    if (this.failNetwork) {
      throw new Error('network');
    }
    const c: CapturedRequest = new CapturedRequest();
    c.url = url;
    c.auth = headers['Authorization'] ?? '';
    this.requests.push(c);
    return this.serve();
  }

  async put(_url: string, _h: Record<string, string>, _b: string): Promise<ParentFetchResult> {
    return this.serve();
  }
  async patch(_url: string, _h: Record<string, string>, _b: string): Promise<ParentFetchResult> {
    return this.serve();
  }
  async del(_url: string, _h: Record<string, string>): Promise<ParentFetchResult> {
    return this.serve();
  }

  private serve(): ParentFetchResult {
    const next: ParentFetchResult | undefined = this.responses.shift();
    if (next === undefined) {
      const fb: ParentFetchResult = new ParentFetchResult();
      fb.status = 500;
      fb.body = '{}';
      return fb;
    }
    return next;
  }
}

async function makeBoundCreds(): Promise<CloudCredentials> {
  const cc: CloudCredentials = new CloudCredentials();
  cc.injectPreferences(new MemPrefs());
  const snap: CloudCredentialsSnapshot = new CloudCredentialsSnapshot();
  snap.deviceToken = 'jwt.body.sig';
  snap.bindingId = 'bind-aabbccdd';
  snap.familyId = 'fam-12345678';
  snap.childProfileId = 'child-deadbeef';
  snap.pairedAtMs = 1746068000000;
  snap.deviceIdSource = 'asset_store';
  await cc.saveBinding(snap);
  return cc;
}

async function makeUnboundCreds(): Promise<CloudCredentials> {
  const cc: CloudCredentials = new CloudCredentials();
  cc.injectPreferences(new MemPrefs());
  return cc;
}

export default function deviceUnbindClientTest(): void {
  describe('DeviceUnbindClient', () => {
    it('clearsCredentialsAndReportsOkOn200', 0, async () => {
      const adapter: StubAdapter = new StubAdapter();
      adapter.enqueue(200, '{"ok":true}');
      const cc: CloudCredentials = await makeBoundCreds();
      const client: DeviceUnbindClient = new DeviceUnbindClient(cc, adapter, BASE);
      const out: DeviceUnbindOutcome = await client.unbind();
      expect(out.ok).assertEqual(true);
      expect(out.cleared).assertEqual(true);
      expect(out.status).assertEqual(200);
      expect(adapter.requests[0].url).assertEqual(`${BASE}/api/v1/child/unbind`);
      expect(adapter.requests[0].auth).assertEqual('Bearer jwt.body.sig');
      const after: CloudCredentialsSnapshot = await cc.load();
      expect(after.isBound()).assertEqual(false);
    });

    it('clearsCredentialsOn404BindingAlreadyRevoked', 0, async () => {
      const adapter: StubAdapter = new StubAdapter();
      adapter.enqueue(404, '{"detail":{"error":{"code":"BINDING_REVOKED"}}}');
      const cc: CloudCredentials = await makeBoundCreds();
      const client: DeviceUnbindClient = new DeviceUnbindClient(cc, adapter, BASE);
      const out: DeviceUnbindOutcome = await client.unbind();
      expect(out.ok).assertEqual(true);
      expect(out.cleared).assertEqual(true);
      const after: CloudCredentialsSnapshot = await cc.load();
      expect(after.isBound()).assertEqual(false);
    });

    it('keepsCredentialsOn500', 0, async () => {
      const adapter: StubAdapter = new StubAdapter();
      adapter.enqueue(500, '{}');
      const cc: CloudCredentials = await makeBoundCreds();
      const client: DeviceUnbindClient = new DeviceUnbindClient(cc, adapter, BASE);
      const out: DeviceUnbindOutcome = await client.unbind();
      expect(out.ok).assertEqual(false);
      expect(out.cleared).assertEqual(false);
      expect(out.status).assertEqual(500);
      const after: CloudCredentialsSnapshot = await cc.load();
      expect(after.isBound()).assertEqual(true);
    });

    it('keepsCredentialsOnNetworkError', 0, async () => {
      const adapter: StubAdapter = new StubAdapter();
      adapter.failNetwork = true;
      const cc: CloudCredentials = await makeBoundCreds();
      const client: DeviceUnbindClient = new DeviceUnbindClient(cc, adapter, BASE);
      const out: DeviceUnbindOutcome = await client.unbind();
      expect(out.ok).assertEqual(false);
      expect(out.cleared).assertEqual(false);
      const after: CloudCredentialsSnapshot = await cc.load();
      expect(after.isBound()).assertEqual(true);
    });

    it('returnsOkAndClearsLocalWhenAlreadyUnbound', 0, async () => {
      const adapter: StubAdapter = new StubAdapter();
      const cc: CloudCredentials = await makeUnboundCreds();
      const client: DeviceUnbindClient = new DeviceUnbindClient(cc, adapter, BASE);
      const out: DeviceUnbindOutcome = await client.unbind();
      expect(out.ok).assertEqual(true);
      expect(out.cleared).assertEqual(true);
      expect(adapter.requests.length).assertEqual(0);
    });
  });
}
