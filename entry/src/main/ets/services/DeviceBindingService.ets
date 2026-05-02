import { CloudCredentials, CloudCredentialsSnapshot } from './CloudCredentials';
import { DeviceIdProvider, DeviceIdResult } from './DeviceIdProvider';

/**
 * V0.6.2 — orchestrates the parent-binding state machine.
 *
 *   Idle → Scanning → Redeeming → Bound
 *                        ↘─────→ Failed (TOKEN_EXPIRED|TOKEN_REDEEMED|NETWORK|UNKNOWN)
 *
 * The service does NOT touch UI: it depends on `BarcodeScannerLike` (so
 * tests don't dial @kit.ScanKit), `BindingHttpClientLike` (so tests don't
 * dial real /api/v1/pair/redeem), `DeviceIdProvider`, and
 * `CloudCredentials`. Pages observe `state` via the listener callback.
 */

export type BindingState = 'idle' | 'scanning' | 'redeeming' | 'bound' | 'failed';

export type BindingFailureReason =
  | 'TOKEN_EXPIRED'
  | 'TOKEN_REDEEMED'
  | 'TOKEN_INVALID'
  | 'NETWORK'
  | 'CANCELLED'
  | 'UNKNOWN';

export class BindingStateUpdate {
  state: BindingState = 'idle';
  reason?: BindingFailureReason;
  snapshot?: CloudCredentialsSnapshot;
}

export type BindingStateListener = (update: BindingStateUpdate) => void;

/** Result of a successful redeem call. Mirrors server PairRedeemOut. */
export class BindingRedeemResult {
  bindingId: string = '';
  familyId: string = '';
  childProfileId: string = '';
  nickname: string = '';
  avatarEmoji: string = '';
  deviceToken: string = '';
}

/** Failure surface from the HTTP layer. `code` mirrors server's
 *  `error.code`: TOKEN_EXPIRED / TOKEN_REDEEMED / TOKEN_INVALID / NETWORK. */
export class BindingHttpError extends Error {
  code: string = 'UNKNOWN';
  status: number = 0;
  constructor(code: string, message: string, status: number) {
    super(message);
    this.name = 'BindingHttpError';
    this.code = code;
    this.status = status;
  }
}

/** Stub-friendly wrapper around the redeem endpoint. */
export interface BindingHttpClientLike {
  /** Either token or shortCode is set; never both empty. */
  redeem(args: BindingRedeemArgs): Promise<BindingRedeemResult>;
}

export class BindingRedeemArgs {
  token: string = '';
  shortCode: string = '';
  deviceId: string = '';
}

/** Minimal contract for `@kit.ScanKit`'s scan API. Returns the raw scanned
 *  string (e.g. "https://happyword.vercel.app/p/abc123"). Tests inject a
 *  stub that returns canned values. */
export interface BarcodeScannerLike {
  scan(): Promise<string>;
}

/** A deterministic stub useful for tests + a sentinel cancel marker. */
export class CancelledScanError extends Error {
  constructor() {
    super('scan cancelled');
    this.name = 'CancelledScanError';
  }
}

const TOKEN_PREFIX_LEN: number = 12;

/** Extracts the token prefix from a `/p/<token>` URL. Returns '' on miss. */
export function extractTokenFromQrPayload(payload: string): string {
  const idx: number = payload.indexOf('/p/');
  if (idx < 0) {
    return '';
  }
  let tail: string = payload.substring(idx + '/p/'.length);
  // Strip query / fragment.
  const qIdx: number = tail.indexOf('?');
  if (qIdx >= 0) {
    tail = tail.substring(0, qIdx);
  }
  const hIdx: number = tail.indexOf('#');
  if (hIdx >= 0) {
    tail = tail.substring(0, hIdx);
  }
  // Strip trailing slash.
  while (tail.length > 0 && tail.charAt(tail.length - 1) === '/') {
    tail = tail.substring(0, tail.length - 1);
  }
  return tail;
}

export class DeviceBindingService {
  private readonly scanner: BarcodeScannerLike;
  private readonly http: BindingHttpClientLike;
  private readonly deviceIdProvider: DeviceIdProvider;
  private readonly credentials: CloudCredentials;
  private listener?: BindingStateListener;
  private state: BindingState = 'idle';

  constructor(
    scanner: BarcodeScannerLike,
    http: BindingHttpClientLike,
    deviceIdProvider: DeviceIdProvider,
    credentials: CloudCredentials,
  ) {
    this.scanner = scanner;
    this.http = http;
    this.deviceIdProvider = deviceIdProvider;
    this.credentials = credentials;
  }

  setListener(l: BindingStateListener): void {
    this.listener = l;
  }

  getState(): BindingState {
    return this.state;
  }

  /** Drive the full scan → redeem → bound flow. */
  async start(): Promise<void> {
    this.transition('scanning');
    let payload: string = '';
    try {
      payload = await this.scanner.scan();
    } catch (err) {
      if (err instanceof CancelledScanError) {
        this.transition('idle');
        return;
      }
      this.fail('NETWORK');
      return;
    }
    const token: string = extractTokenFromQrPayload(payload);
    if (token.length < 4 || token.length > 64) {
      this.fail('TOKEN_INVALID');
      return;
    }
    await this.redeem(token, '');
  }

  /** Redeem a manually-typed 6-digit short code (no scan). */
  async redeemShortCode(code: string): Promise<void> {
    if (code.length !== 6) {
      this.fail('TOKEN_INVALID');
      return;
    }
    this.transition('scanning');
    await this.redeem('', code);
  }

  /** Cancel a Scanning/Redeeming flow. Idempotent if already in a final state. */
  cancel(): void {
    if (this.state === 'scanning' || this.state === 'redeeming') {
      this.transition('idle');
    }
  }

  private async redeem(token: string, shortCode: string): Promise<void> {
    this.transition('redeeming');
    const idResult: DeviceIdResult = await this.deviceIdProvider.get();
    await this.credentials.setDeviceIdSource(idResult.source);

    const args: BindingRedeemArgs = new BindingRedeemArgs();
    args.token = token;
    args.shortCode = shortCode;
    args.deviceId = idResult.deviceId;

    let result: BindingRedeemResult;
    try {
      result = await this.http.redeem(args);
    } catch (err) {
      if (err instanceof BindingHttpError) {
        const code: string = err.code;
        if (code === 'TOKEN_EXPIRED') {
          this.fail('TOKEN_EXPIRED');
          return;
        }
        if (code === 'TOKEN_REDEEMED') {
          this.fail('TOKEN_REDEEMED');
          return;
        }
        if (code === 'TOKEN_INVALID') {
          this.fail('TOKEN_INVALID');
          return;
        }
        this.fail('UNKNOWN');
        return;
      }
      this.fail('NETWORK');
      return;
    }

    const snap: CloudCredentialsSnapshot = new CloudCredentialsSnapshot();
    snap.deviceToken = result.deviceToken;
    snap.bindingId = result.bindingId;
    snap.familyId = result.familyId;
    snap.childProfileId = result.childProfileId;
    snap.nickname = result.nickname;
    snap.avatarEmoji = result.avatarEmoji;
    snap.pairedAtMs = Date.now();
    snap.deviceIdSource = idResult.source;
    await this.credentials.saveBinding(snap);

    this.transitionWithSnapshot('bound', snap);
  }

  private transition(next: BindingState): void {
    this.state = next;
    if (this.listener !== undefined) {
      const u: BindingStateUpdate = new BindingStateUpdate();
      u.state = next;
      this.listener(u);
    }
  }

  private transitionWithSnapshot(next: BindingState, snap: CloudCredentialsSnapshot): void {
    this.state = next;
    if (this.listener !== undefined) {
      const u: BindingStateUpdate = new BindingStateUpdate();
      u.state = next;
      u.snapshot = snap;
      this.listener(u);
    }
  }

  private fail(reason: BindingFailureReason): void {
    this.state = 'failed';
    if (this.listener !== undefined) {
      const u: BindingStateUpdate = new BindingStateUpdate();
      u.state = 'failed';
      u.reason = reason;
      this.listener(u);
    }
  }
}

/** Re-exported constant so tests can express expected token prefix length. */
export const _TOKEN_PREFIX_LEN_FOR_TEST: number = TOKEN_PREFIX_LEN;
