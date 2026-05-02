import { BindingHttpClientLike, BindingHttpError, BindingRedeemArgs, BindingRedeemResult } from './DeviceBindingService';
import { ParentFetchAdapter, ParentFetchResult } from './ParentApiClient';

/**
 * V0.6.2 — thin HTTP client for `/api/v1/pair/redeem`.
 *
 * Reuses the existing `ParentFetchAdapter` injection seam so production
 * traffic flows through the same HttpRequest path as the rest of the app
 * and tests can inject a stub.
 */
const HEADER_CONTENT_TYPE: string = 'Content-Type';
const HEADER_ACCEPT: string = 'Accept';
const CONTENT_JSON: string = 'application/json';

interface RawRedeemOut {
  binding_id?: string;
  family_id?: string;
  child_profile_id?: string;
  nickname?: string;
  avatar_emoji?: string;
  device_token?: string;
}

interface RawErrorEnvelope {
  detail?: RawErrorDetail;
}

interface RawErrorDetail {
  error?: RawErrorBody;
}

interface RawErrorBody {
  code?: string;
  message?: string;
}

export class BindingApiClient implements BindingHttpClientLike {
  private readonly adapter: ParentFetchAdapter;
  private readonly baseUrl: string;

  constructor(adapter: ParentFetchAdapter, baseUrl: string) {
    this.adapter = adapter;
    this.baseUrl = BindingApiClient.trimTrailingSlash(baseUrl);
  }

  async redeem(args: BindingRedeemArgs): Promise<BindingRedeemResult> {
    const url: string = `${this.baseUrl}/api/v1/pair/redeem`;
    const headers: Record<string, string> = {};
    headers[HEADER_CONTENT_TYPE] = CONTENT_JSON;
    headers[HEADER_ACCEPT] = CONTENT_JSON;

    const payload: Record<string, string> = { 'device_id': args.deviceId };
    if (args.token.length > 0) {
      payload['token'] = args.token;
    }
    if (args.shortCode.length > 0) {
      payload['short_code'] = args.shortCode;
    }
    const body: string = JSON.stringify(payload);

    let res: ParentFetchResult;
    try {
      res = await this.adapter.post(url, headers, body);
    } catch (_err) {
      throw new BindingHttpError('NETWORK', 'pair/redeem: transport failed', 0);
    }

    if (res.status !== 200 && res.status !== 201) {
      throw new BindingHttpError(
        BindingApiClient.parseErrorCode(res.body),
        `pair/redeem: HTTP ${res.status}`,
        res.status,
      );
    }
    let parsed: RawRedeemOut;
    try {
      parsed = JSON.parse(res.body) as RawRedeemOut;
    } catch (_err) {
      throw new BindingHttpError('UNKNOWN', 'pair/redeem: malformed response body', res.status);
    }
    const out: BindingRedeemResult = new BindingRedeemResult();
    out.bindingId = typeof parsed.binding_id === 'string' ? parsed.binding_id : '';
    out.familyId = typeof parsed.family_id === 'string' ? parsed.family_id : '';
    out.childProfileId = typeof parsed.child_profile_id === 'string' ? parsed.child_profile_id : '';
    out.nickname = typeof parsed.nickname === 'string' ? parsed.nickname : '';
    out.avatarEmoji = typeof parsed.avatar_emoji === 'string' ? parsed.avatar_emoji : '';
    out.deviceToken = typeof parsed.device_token === 'string' ? parsed.device_token : '';
    return out;
  }

  private static parseErrorCode(body: string): string {
    try {
      const env: RawErrorEnvelope = JSON.parse(body) as RawErrorEnvelope;
      const code: string | undefined = env.detail?.error?.code;
      if (typeof code === 'string' && code.length > 0) {
        return code;
      }
    } catch (_err) {
      // fall through
    }
    return 'UNKNOWN';
  }

  private static trimTrailingSlash(p: string): string {
    let end: number = p.length;
    while (end > 0 && p.charAt(end - 1) === '/') {
      end -= 1;
    }
    return p.substring(0, end);
  }
}
