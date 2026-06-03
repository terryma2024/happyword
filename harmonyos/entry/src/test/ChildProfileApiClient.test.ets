import { describe, it, expect } from '@ohos/hypium';
import {
  ChildProfileApiClient,
  ChildProfileHttpError,
  UpdatedChildProfile,
} from '../main/ets/services/ChildProfileApiClient';
import { ParentFetchAdapter, ParentFetchResult } from '../main/ets/services/ParentApiClient';

const BASE: string = 'https://happyword.com.cn';
const FAM: string = 'fam-12345678';

class CapturedRequest {
  url: string = '';
  body: string = '';
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
  async post(_url: string, _h: Record<string, string>, _body: string): Promise<ParentFetchResult> {
    return this.serve();
  }
  async put(url: string, headers: Record<string, string>, body: string): Promise<ParentFetchResult> {
    if (this.failNetwork) {
      throw new Error('network');
    }
    const c: CapturedRequest = new CapturedRequest();
    c.url = url;
    c.body = body;
    c.auth = headers['Authorization'] ?? '';
    this.requests.push(c);
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

export default function childProfileApiClientTest(): void {
  describe('ChildProfileApiClient.updateProfile', () => {
    it('parsesSuccessAndAttachesBearer', 0, async () => {
      const ad: StubAdapter = new StubAdapter();
      ad.enqueue(
        200,
        '{"profile_id":"child-deadbeef","family_id":"fam-12345678","nickname":"小明","avatar_emoji":"🦄","updated_at":"2026-05-08T10:00:00Z"}',
      );
      const c: ChildProfileApiClient = new ChildProfileApiClient(ad, BASE);
      const out: UpdatedChildProfile =
        await c.updateProfile('jwt.body.sig', `  ${FAM}  `, '  小明  ', '🦄');
      expect(out.profileId).assertEqual('child-deadbeef');
      expect(out.nickname).assertEqual('小明');
      expect(out.familyId).assertEqual('fam-12345678');
      expect(ad.requests[0].url).assertEqual(`${BASE}/api/v1/family/${FAM}/profile`);
      expect(ad.requests[0].auth).assertEqual('Bearer jwt.body.sig');
      // Body is sent verbatim; service strips on the server side.
      expect(ad.requests[0].body.indexOf('  小明  ')).assertLargerOrEqual(0);
      expect(ad.requests[0].body.indexOf('avatar_emoji')).assertLargerOrEqual(0);
      expect(ad.requests[0].body.indexOf('🦄')).assertLargerOrEqual(0);
    });

    it('throwsInvalidNicknameOn400', 0, async () => {
      const ad: StubAdapter = new StubAdapter();
      ad.enqueue(
        400,
        '{"detail":{"error":{"code":"INVALID_NICKNAME","message":"empty"}}}',
      );
      const c: ChildProfileApiClient = new ChildProfileApiClient(ad, BASE);
      let caught: ChildProfileHttpError | null = null;
      try {
        await c.updateProfile('jwt.body.sig', FAM, '   ', '🦄');
      } catch (err) {
        caught = err as ChildProfileHttpError;
      }
      expect(caught !== null).assertEqual(true);
      expect(caught!.code).assertEqual('INVALID_NICKNAME');
      expect(caught!.status).assertEqual(400);
    });

    it('throwsBindingRevokedOn404', 0, async () => {
      const ad: StubAdapter = new StubAdapter();
      ad.enqueue(
        404,
        '{"detail":{"error":{"code":"BINDING_REVOKED","message":"revoked"}}}',
      );
      const c: ChildProfileApiClient = new ChildProfileApiClient(ad, BASE);
      let caught: ChildProfileHttpError | null = null;
      try {
        await c.updateProfile('jwt.body.sig', FAM, '小明', '🦄');
      } catch (err) {
        caught = err as ChildProfileHttpError;
      }
      expect(caught !== null).assertEqual(true);
      expect(caught!.code).assertEqual('BINDING_REVOKED');
      expect(caught!.status).assertEqual(404);
    });

    it('throwsNetworkOnTransportFailure', 0, async () => {
      const ad: StubAdapter = new StubAdapter();
      ad.failNetwork = true;
      const c: ChildProfileApiClient = new ChildProfileApiClient(ad, BASE);
      let caught: ChildProfileHttpError | null = null;
      try {
        await c.updateProfile('jwt.body.sig', FAM, '小明', '🦄');
      } catch (err) {
        caught = err as ChildProfileHttpError;
      }
      expect(caught !== null).assertEqual(true);
      expect(caught!.code).assertEqual('NETWORK');
    });

    it('throwsNotBoundWhenTokenEmpty', 0, async () => {
      const ad: StubAdapter = new StubAdapter();
      const c: ChildProfileApiClient = new ChildProfileApiClient(ad, BASE);
      let caught: ChildProfileHttpError | null = null;
      try {
        await c.updateProfile('', FAM, '小明', '🦄');
      } catch (err) {
        caught = err as ChildProfileHttpError;
      }
      expect(caught !== null).assertEqual(true);
      expect(caught!.code).assertEqual('NOT_BOUND');
      // Did not even reach the adapter.
      expect(ad.requests.length).assertEqual(0);
    });

    it('throwsUnknownOnMalformedJson', 0, async () => {
      const ad: StubAdapter = new StubAdapter();
      ad.enqueue(200, 'not-json');
      const c: ChildProfileApiClient = new ChildProfileApiClient(ad, BASE);
      let caught: ChildProfileHttpError | null = null;
      try {
        await c.updateProfile('jwt.body.sig', FAM, '小明', '🦄');
      } catch (err) {
        caught = err as ChildProfileHttpError;
      }
      expect(caught !== null).assertEqual(true);
      expect(caught!.code).assertEqual('UNKNOWN');
    });
  });
}
