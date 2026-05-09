import { ParentFetchAdapter, ParentFetchResult } from './ParentApiClient';

/**
 * V0.6.8 — thin HTTP client for `PUT /api/v1/child/profile`, the
 * device-token-authenticated self-edit endpoint that lets the bound
 * device update the child's display nickname from
 * `BoundDeviceInfoPage`.
 *
 * Mirrors the slim shape of `BindingApiClient` and `DeviceUnbindClient`
 * (same `ParentFetchAdapter` injection seam) so production traffic
 * flows through the existing HttpRequest pipeline and tests can inject
 * a stub.
 *
 * Errors are surfaced as `ChildProfileHttpError` with the server-side
 * `code` (e.g. INVALID_NICKNAME, BINDING_REVOKED) parsed from the
 * standard FastAPI error envelope. Callers can map these to localized
 * messages.
 */

const HEADER_CONTENT_TYPE: string = 'Content-Type';
const HEADER_ACCEPT: string = 'Accept';
const HEADER_AUTH: string = 'Authorization';
const CONTENT_JSON: string = 'application/json';

export class ChildProfileHttpError extends Error {
  code: string = '';
  status: number = 0;

  constructor(code: string, message: string, status: number) {
    super(message);
    this.name = 'ChildProfileHttpError';
    this.code = code;
    this.status = status;
  }
}

export class UpdatedChildProfile {
  profileId: string = '';
  familyId: string = '';
  nickname: string = '';
  avatarEmoji: string = '';
  /** Server-side updated_at timestamp, ISO-8601. */
  updatedAt: string = '';
}

interface RawProfileOut {
  profile_id?: string;
  family_id?: string;
  nickname?: string;
  avatar_emoji?: string;
  updated_at?: string;
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

export class ChildProfileApiClient {
  private readonly adapter: ParentFetchAdapter;
  private readonly baseUrl: string;

  constructor(adapter: ParentFetchAdapter, baseUrl: string) {
    this.adapter = adapter;
    this.baseUrl = ChildProfileApiClient.trimTrailingSlash(baseUrl);
  }

  async updateNickname(deviceToken: string, nickname: string): Promise<UpdatedChildProfile> {
    if (deviceToken.length === 0) {
      throw new ChildProfileHttpError('NOT_BOUND', 'no device token', 0);
    }
    const url: string = `${this.baseUrl}/api/v1/child/profile`;
    const headers: Record<string, string> = {};
    headers[HEADER_CONTENT_TYPE] = CONTENT_JSON;
    headers[HEADER_ACCEPT] = CONTENT_JSON;
    headers[HEADER_AUTH] = `Bearer ${deviceToken}`;

    const payload: Record<string, string> = { 'nickname': nickname };
    const body: string = JSON.stringify(payload);

    let res: ParentFetchResult;
    try {
      res = await this.adapter.put(url, headers, body);
    } catch (_err) {
      throw new ChildProfileHttpError('NETWORK', 'child/profile: transport failed', 0);
    }

    if (res.status !== 200) {
      throw new ChildProfileHttpError(
        ChildProfileApiClient.parseErrorCode(res.body),
        `child/profile: HTTP ${res.status}`,
        res.status,
      );
    }
    let parsed: RawProfileOut;
    try {
      parsed = JSON.parse(res.body) as RawProfileOut;
    } catch (_err) {
      throw new ChildProfileHttpError('UNKNOWN', 'child/profile: malformed response body', res.status);
    }
    const out: UpdatedChildProfile = new UpdatedChildProfile();
    out.profileId = typeof parsed.profile_id === 'string' ? parsed.profile_id : '';
    out.familyId = typeof parsed.family_id === 'string' ? parsed.family_id : '';
    out.nickname = typeof parsed.nickname === 'string' ? parsed.nickname : '';
    out.avatarEmoji = typeof parsed.avatar_emoji === 'string' ? parsed.avatar_emoji : '';
    out.updatedAt = typeof parsed.updated_at === 'string' ? parsed.updated_at : '';
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
      // fall through to UNKNOWN
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
