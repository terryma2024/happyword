import { describe, it, expect } from '@ohos/hypium';
import { BindingApiClient } from '../main/ets/services/BindingApiClient';
import {
  BindingHttpError,
  BindingRedeemArgs,
  BindingRedeemResult,
} from '../main/ets/services/DeviceBindingService';
import { ParentFetchAdapter, ParentFetchResult } from '../main/ets/services/ParentApiClient';

class StubAdapter implements ParentFetchAdapter {
  responses: Map<string, ParentFetchResult> = new Map<string, ParentFetchResult>();
  lastUrl: string = '';
  lastBody: string = '';
  lastHeaders: Record<string, string> = {};

  async get(url: string, headers: Record<string, string>): Promise<ParentFetchResult> {
    return this.serve('GET', url, headers, '');
  }
  async post(url: string, headers: Record<string, string>, body: string): Promise<ParentFetchResult> {
    return this.serve('POST', url, headers, body);
  }
  async put(url: string, headers: Record<string, string>, body: string): Promise<ParentFetchResult> {
    return this.serve('PUT', url, headers, body);
  }
  async patch(url: string, headers: Record<string, string>, body: string): Promise<ParentFetchResult> {
    return this.serve('PATCH', url, headers, body);
  }
  async del(url: string, headers: Record<string, string>): Promise<ParentFetchResult> {
    return this.serve('DELETE', url, headers, '');
  }

  private serve(
    method: string,
    url: string,
    headers: Record<string, string>,
    body: string,
  ): ParentFetchResult {
    this.lastUrl = url;
    this.lastBody = body;
    this.lastHeaders = headers;
    const r: ParentFetchResult | undefined = this.responses.get(`${method} ${url}`);
    if (r === undefined) {
      const fallback: ParentFetchResult = new ParentFetchResult();
      fallback.status = 500;
      fallback.body = '{"detail":{"error":{"code":"NO_STUB"}}}';
      return fallback;
    }
    return r;
  }
}

const BASE: string = 'https://happyword.vercel.app';

function fake(status: number, body: string): ParentFetchResult {
  const r: ParentFetchResult = new ParentFetchResult();
  r.status = status;
  r.body = body;
  return r;
}

export default function bindingApiClientTest(): void {
  describe('BindingApiClient.redeem', () => {
    it('parsesSuccessAndPropagatesAllFields', 0, async () => {
      const ad: StubAdapter = new StubAdapter();
      ad.responses.set(
        `POST ${BASE}/api/v1/pair/redeem`,
        fake(
          200,
          '{"binding_id":"bind-aabbccdd","family_id":"fam-12345678","child_profile_id":"child-deadbeef","nickname":"宝贝","avatar_emoji":"🦄","device_token":"jwt.body.sig"}',
        ),
      );
      const c: BindingApiClient = new BindingApiClient(ad, BASE);
      const args: BindingRedeemArgs = new BindingRedeemArgs();
      args.token = 'abc123def456';
      args.deviceId = 'dev-aaaa-bbbb';
      const out: BindingRedeemResult = await c.redeem(args);
      expect(out.bindingId).assertEqual('bind-aabbccdd');
      expect(out.familyId).assertEqual('fam-12345678');
      expect(out.deviceToken).assertEqual('jwt.body.sig');
      expect(ad.lastBody.indexOf('"token":"abc123def456"')).assertLargerOrEqual(0);
      expect(ad.lastBody.indexOf('"device_id":"dev-aaaa-bbbb"')).assertLargerOrEqual(0);
    });

    it('mapsTokenExpiredErrorEnvelope', 0, async () => {
      const ad: StubAdapter = new StubAdapter();
      ad.responses.set(
        `POST ${BASE}/api/v1/pair/redeem`,
        fake(410, '{"detail":{"error":{"code":"TOKEN_EXPIRED","message":"gone"}}}'),
      );
      const c: BindingApiClient = new BindingApiClient(ad, BASE);
      const args: BindingRedeemArgs = new BindingRedeemArgs();
      args.token = 'tok';
      args.deviceId = 'dev-1234';
      let caught: BindingHttpError | null = null;
      try {
        await c.redeem(args);
      } catch (err) {
        caught = err as BindingHttpError;
      }
      expect(caught !== null).assertEqual(true);
      expect((caught as BindingHttpError).code).assertEqual('TOKEN_EXPIRED');
      expect((caught as BindingHttpError).status).assertEqual(410);
    });

    it('mapsAlreadyRedeemedConflict', 0, async () => {
      const ad: StubAdapter = new StubAdapter();
      ad.responses.set(
        `POST ${BASE}/api/v1/pair/redeem`,
        fake(409, '{"detail":{"error":{"code":"TOKEN_REDEEMED"}}}'),
      );
      const c: BindingApiClient = new BindingApiClient(ad, BASE);
      const args: BindingRedeemArgs = new BindingRedeemArgs();
      args.token = 'tok';
      args.deviceId = 'dev-1234';
      let caught: BindingHttpError | null = null;
      try {
        await c.redeem(args);
      } catch (err) {
        caught = err as BindingHttpError;
      }
      expect(caught !== null).assertEqual(true);
      expect((caught as BindingHttpError).code).assertEqual('TOKEN_REDEEMED');
    });

    it('shortCodeIsForwardedInBody', 0, async () => {
      const ad: StubAdapter = new StubAdapter();
      ad.responses.set(
        `POST ${BASE}/api/v1/pair/redeem`,
        fake(
          200,
          '{"binding_id":"bind-x","family_id":"fam-x","child_profile_id":"child-x","nickname":"x","avatar_emoji":"x","device_token":"x.y.z"}',
        ),
      );
      const c: BindingApiClient = new BindingApiClient(ad, BASE);
      const args: BindingRedeemArgs = new BindingRedeemArgs();
      args.shortCode = '123456';
      args.deviceId = 'dev-shortcode';
      await c.redeem(args);
      expect(ad.lastBody.indexOf('"short_code":"123456"')).assertLargerOrEqual(0);
      expect(ad.lastBody.indexOf('"token"')).assertEqual(-1);
    });
  });
}
