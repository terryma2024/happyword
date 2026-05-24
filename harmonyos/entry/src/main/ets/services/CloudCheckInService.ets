import { CoinAccount } from './CoinAccount';
import { CoinTxn } from '../models/CoinSnapshot';
import { CheckInSnapshot } from '../models/CheckInSnapshot';
import { CheckInStore } from './CheckInStore';
import { CloudCredentials, CloudCredentialsSnapshot } from './CloudCredentials';
import { ParentFetchAdapter, ParentFetchResult } from './ParentApiClient';
import { effectiveServerBaseUrl } from './RemoteWordPackConfig';

const HEADER_AUTH: string = 'Authorization';
const HEADER_CONTENT_TYPE: string = 'Content-Type';
const HEADER_ACCEPT: string = 'Accept';
const CONTENT_JSON: string = 'application/json';

interface RawCoinTxnIn {
  txn_id: string;
  ts: number;
  delta: number;
  reason: string;
  balance_after: number;
}

interface RawCoinTxnOut {
  txn_id?: string;
  ts?: number;
  delta?: number;
  reason?: string;
  balance_after?: number;
}

interface RawCheckInSyncOut {
  checked_day_keys?: string[];
  weekly_bonus_day_keys?: string[];
  coin_txns?: RawCoinTxnOut[];
  server_now_ms?: number;
}

interface RawCheckInSyncIn {
  checked_day_keys: string[];
  weekly_bonus_day_keys: string[];
  coin_txns: RawCoinTxnIn[];
  synced_through_ms: number;
}

export class CloudCheckInResult {
  status: string = 'no_changes';
  pushedDays: number = 0;
  appliedCoinTxns: number = 0;
  serverNowMs: number = 0;
}

export class CloudCheckInService {
  private readonly store: CheckInStore;
  private readonly coins: CoinAccount;
  private readonly credentials: CloudCredentials;
  private readonly adapter: ParentFetchAdapter;
  private readonly resolveBaseUrl: () => string;
  private inFlight: boolean = false;

  constructor(
    store: CheckInStore,
    coins: CoinAccount,
    credentials: CloudCredentials,
    adapter: ParentFetchAdapter,
    resolveBaseUrl: () => string,
  ) {
    this.store = store;
    this.coins = coins;
    this.credentials = credentials;
    this.adapter = adapter;
    this.resolveBaseUrl = resolveBaseUrl;
  }

  static defaultBaseUrlResolver(): string {
    return CloudCheckInService.trimTrailingSlash(effectiveServerBaseUrl());
  }

  async syncOnce(): Promise<CloudCheckInResult> {
    const out: CloudCheckInResult = new CloudCheckInResult();
    if (this.inFlight) {
      return out;
    }
    this.inFlight = true;
    try {
      return await this.runSync(out);
    } finally {
      this.inFlight = false;
    }
  }

  private async runSync(out: CloudCheckInResult): Promise<CloudCheckInResult> {
    const creds: CloudCredentialsSnapshot = await this.credentials.load();
    if (!creds.isBound() || creds.deviceToken.length === 0) {
      out.status = 'unbound';
      return out;
    }
    const local: CheckInSnapshot = this.store.snapshot();
    const wireTxns: RawCoinTxnIn[] = this.coinTxnsToWire();
    const raw: RawCheckInSyncOut | null = await this.postSync(creds, local, wireTxns);
    if (raw === null) {
      this.store.markPendingSync();
      out.status = 'network_error';
      return out;
    }
    const checked: string[] = Array.isArray(raw.checked_day_keys) ? raw.checked_day_keys : [];
    const weekly: string[] = Array.isArray(raw.weekly_bonus_day_keys) ? raw.weekly_bonus_day_keys : [];
    const serverNow: number = typeof raw.server_now_ms === 'number' ? raw.server_now_ms : 0;
    let applied: number = 0;
    const rawTxns: RawCoinTxnOut[] = Array.isArray(raw.coin_txns) ? raw.coin_txns : [];
    for (let i = 0; i < rawTxns.length; i++) {
      const t: RawCoinTxnOut = rawTxns[i];
      const txnId: string = typeof t.txn_id === 'string' ? t.txn_id : '';
      const delta: number = typeof t.delta === 'number' ? t.delta : 0;
      const reason: string = typeof t.reason === 'string' ? t.reason : '';
      const ts: number = typeof t.ts === 'number' ? t.ts : serverNow;
      if (this.coins.applyExternalTxn(txnId, delta, reason, ts)) {
        applied += 1;
      }
    }
    await this.store.applyCloudMerge(checked, weekly, serverNow);
    await this.coins.flushNow();
    out.status = 'synced';
    out.pushedDays = local.checkedDayKeys.length;
    out.appliedCoinTxns = applied;
    out.serverNowMs = serverNow;
    return out;
  }

  private async postSync(
    creds: CloudCredentialsSnapshot,
    local: CheckInSnapshot,
    wireTxns: RawCoinTxnIn[],
  ): Promise<RawCheckInSyncOut | null> {
    const base: string = CloudCheckInService.trimTrailingSlash(this.resolveBaseUrl());
    const fid: string = creds.familyId.trim().length > 0 ? creds.familyId.trim() : '_';
    const url: string = `${base}/api/v1/family/${fid}/checkins/sync`;
    const headers: Record<string, string> = {};
    headers[HEADER_CONTENT_TYPE] = CONTENT_JSON;
    headers[HEADER_ACCEPT] = CONTENT_JSON;
    headers[HEADER_AUTH] = `Bearer ${creds.deviceToken}`;
    const body: string = JSON.stringify({
      checked_day_keys: local.checkedDayKeys,
      weekly_bonus_day_keys: local.weeklyBonusDayKeys,
      coin_txns: wireTxns,
      synced_through_ms: local.lastSyncedAtMs,
    } as RawCheckInSyncIn);
    let res: ParentFetchResult;
    try {
      res = await this.adapter.post(url, headers, body);
    } catch (_err) {
      return null;
    }
    if (res.status !== 200 && res.status !== 201) {
      return null;
    }
    try {
      return JSON.parse(res.body) as RawCheckInSyncOut;
    } catch (_err) {
      return null;
    }
  }

  private coinTxnsToWire(): RawCoinTxnIn[] {
    const txns: CoinTxn[] = this.coins.snapshot().txns;
    const out: RawCoinTxnIn[] = [];
    for (let i = 0; i < txns.length; i++) {
      const txn: CoinTxn = txns[i];
      if (txn.txnId.length === 0) {
        continue;
      }
      out.push({
        txn_id: txn.txnId,
        ts: txn.ts,
        delta: txn.delta,
        reason: txn.reason,
        balance_after: txn.balanceAfter,
      });
    }
    return out;
  }

  private static trimTrailingSlash(p: string): string {
    let end: number = p.length;
    while (end > 0 && p.charAt(end - 1) === '/') {
      end -= 1;
    }
    return p.substring(0, end);
  }
}
