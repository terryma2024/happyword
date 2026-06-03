import { describe, it, expect } from '@ohos/hypium';
import { CheckInStore } from '../main/ets/services/CheckInStore';
import { CloudCheckInResult, CloudCheckInService } from '../main/ets/services/CloudCheckInService';
import { CloudCredentials, CloudCredentialsSnapshot } from '../main/ets/services/CloudCredentials';
import { CoinAccount } from '../main/ets/services/CoinAccount';
import { StringPreferencesLike } from '../main/ets/services/WrongAnswerStore';
import { ParentFetchAdapter, ParentFetchResult } from '../main/ets/services/ParentApiClient';

const BASE: string = 'https://happyword.com.cn';
const SYNC_PATH: string = '/api/v1/family/fam-12345678/checkins/sync';

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

class CapturedPost {
  url: string = '';
  body: string = '';
  auth: string = '';
}

class CapturingAdapter implements ParentFetchAdapter {
  responses: ParentFetchResult[] = [];
  posts: CapturedPost[] = [];
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
  async post(url: string, headers: Record<string, string>, body: string): Promise<ParentFetchResult> {
    if (this.failNetwork) {
      throw new Error('network');
    }
    const p: CapturedPost = new CapturedPost();
    p.url = url;
    p.body = body;
    p.auth = headers['Authorization'] ?? '';
    this.posts.push(p);
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
    if (next !== undefined) {
      return next;
    }
    const fb: ParentFetchResult = new ParentFetchResult();
    fb.status = 500;
    fb.body = '{}';
    return fb;
  }
}

function makeBoundCreds(): CloudCredentials {
  const cc: CloudCredentials = new CloudCredentials();
  cc.injectPreferences(new MemPrefs());
  const snap: CloudCredentialsSnapshot = new CloudCredentialsSnapshot();
  snap.deviceToken = 'jwt.body.sig';
  snap.bindingId = 'bind-aabbccdd';
  snap.familyId = 'fam-12345678';
  snap.childProfileId = 'child-deadbeef';
  snap.pairedAtMs = 1746068000000;
  snap.deviceIdSource = 'asset_store';
  cc.saveBinding(snap);
  return cc;
}

async function storeWithDay(dayKey: string): Promise<CheckInStore> {
  const store: CheckInStore = new CheckInStore();
  store.injectPreferencesForTest(new MemPrefs());
  await store.recordWin(Date.parse(`${dayKey}T12:00:00`));
  return store;
}

function coinWithBonus(): CoinAccount {
  const coins: CoinAccount = new CoinAccount();
  coins.injectPreferencesForTest(new MemPrefs());
  coins.applyExternalTxn(
    'checkin-weekly-bonus:2026-05-07',
    50,
    'checkin-weekly-bonus:2026-05-07',
    1778112000000,
  );
  return coins;
}

export default function cloudCheckInServiceTest(): void {
  describe('CloudCheckInService', () => {
    it('returnsUnboundWithoutPosting', 0, async () => {
      const creds: CloudCredentials = new CloudCredentials();
      creds.injectPreferences(new MemPrefs());
      const adapter: CapturingAdapter = new CapturingAdapter();
      const store: CheckInStore = await storeWithDay('2026-05-01');
      const svc: CloudCheckInService = new CloudCheckInService(
        store,
        new CoinAccount(),
        creds,
        adapter,
        (): string => BASE,
      );
      const out: CloudCheckInResult = await svc.syncOnce();
      expect(out.status).assertEqual('unbound');
      expect(adapter.posts.length).assertEqual(0);
    });

    it('postsLocalDaysAndCoinTxnsWhenBound', 0, async () => {
      const adapter: CapturingAdapter = new CapturingAdapter();
      adapter.enqueue(
        200,
        '{"checked_day_keys":["2026-05-01"],"weekly_bonus_day_keys":["2026-05-07"],"coin_txns":[{"txn_id":"checkin-weekly-bonus:2026-05-07","ts":1778112000000,"delta":50,"reason":"checkin-weekly-bonus:2026-05-07","balance_after":70,"updated_at":"2026-05-07T12:00:00Z"}],"server_now_ms":1778112000000}',
      );
      const svc: CloudCheckInService = new CloudCheckInService(
        await storeWithDay('2026-05-01'),
        coinWithBonus(),
        makeBoundCreds(),
        adapter,
        (): string => BASE,
      );
      const out: CloudCheckInResult = await svc.syncOnce();
      expect(out.status).assertEqual('synced');
      expect(adapter.posts.length).assertEqual(1);
      expect(adapter.posts[0].url.indexOf(SYNC_PATH)).assertLargerOrEqual(0);
      expect(adapter.posts[0].auth).assertEqual('Bearer jwt.body.sig');
      expect(adapter.posts[0].body.indexOf('"checked_day_keys":["2026-05-01"]')).assertLargerOrEqual(0);
      expect(adapter.posts[0].body.indexOf('"txn_id":"checkin-weekly-bonus:2026-05-07"')).assertLargerOrEqual(0);
    });

    it('appliesMergedCloudDaysAndCoinTxns', 0, async () => {
      const store: CheckInStore = await storeWithDay('2026-05-01');
      const coins: CoinAccount = new CoinAccount();
      coins.injectPreferencesForTest(new MemPrefs());
      const adapter: CapturingAdapter = new CapturingAdapter();
      adapter.enqueue(
        200,
        '{"checked_day_keys":["2026-05-01","2026-05-02"],"weekly_bonus_day_keys":["2026-05-07"],"coin_txns":[{"txn_id":"checkin-weekly-bonus:2026-05-07","ts":1778112000000,"delta":50,"reason":"checkin-weekly-bonus:2026-05-07","balance_after":70,"updated_at":"2026-05-07T12:00:00Z"}],"server_now_ms":1778112000000}',
      );
      const svc: CloudCheckInService = new CloudCheckInService(store, coins, makeBoundCreds(), adapter, (): string => BASE);
      const out: CloudCheckInResult = await svc.syncOnce();
      expect(out.status).assertEqual('synced');
      expect(store.snapshot().checkedDayKeys.length).assertEqual(2);
      expect(store.snapshot().pendingSync).assertFalse();
      expect(coins.balance()).assertEqual(50);
    });

    it('networkFailureLeavesPendingSync', 0, async () => {
      const store: CheckInStore = await storeWithDay('2026-05-01');
      const adapter: CapturingAdapter = new CapturingAdapter();
      adapter.failNetwork = true;
      const svc: CloudCheckInService = new CloudCheckInService(store, new CoinAccount(), makeBoundCreds(), adapter, (): string => BASE);
      const out: CloudCheckInResult = await svc.syncOnce();
      expect(out.status).assertEqual('network_error');
      expect(store.snapshot().pendingSync).assertTrue();
    });
  });
}
