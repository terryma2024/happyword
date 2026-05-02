import { describe, it, expect } from '@ohos/hypium';
import {
  CloudWishlistItem,
  CloudWishlistService,
  PendingRedemption,
  RedemptionDecision,
} from '../main/ets/services/CloudWishlistService';
import { CloudCredentials, CloudCredentialsSnapshot } from '../main/ets/services/CloudCredentials';
import { ParentFetchAdapter, ParentFetchResult } from '../main/ets/services/ParentApiClient';
import { StringPreferencesLike } from '../main/ets/services/WrongAnswerStore';

const BASE: string = 'https://happyword.vercel.app';

class MemPrefs implements StringPreferencesLike {
  store: Map<string, string> = new Map<string, string>();
  flushCount: number = 0;
  async getString(key: string): Promise<string> {
    return this.store.get(key) ?? '';
  }
  async putString(key: string, value: string): Promise<void> {
    this.store.set(key, value);
  }
  async flush(): Promise<void> {
    this.flushCount += 1;
  }
}

class CapturedRequest {
  method: string = '';
  url: string = '';
  body: string = '';
  auth: string = '';
}

class CapturingAdapter implements ParentFetchAdapter {
  responses: ParentFetchResult[] = [];
  requests: CapturedRequest[] = [];
  failNetwork: boolean = false;

  enqueue(status: number, body: string): void {
    const r: ParentFetchResult = new ParentFetchResult();
    r.status = status;
    r.body = body;
    this.responses.push(r);
  }

  async get(url: string, headers: Record<string, string>): Promise<ParentFetchResult> {
    if (this.failNetwork) {
      throw new Error('network');
    }
    const c: CapturedRequest = new CapturedRequest();
    c.method = 'GET';
    c.url = url;
    c.auth = headers['Authorization'] ?? '';
    this.requests.push(c);
    return this.serve();
  }

  async post(url: string, headers: Record<string, string>, body: string): Promise<ParentFetchResult> {
    if (this.failNetwork) {
      throw new Error('network');
    }
    const c: CapturedRequest = new CapturedRequest();
    c.method = 'POST';
    c.url = url;
    c.body = body;
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

function makeUnboundCreds(): CloudCredentials {
  const cc: CloudCredentials = new CloudCredentials();
  cc.injectPreferences(new MemPrefs());
  return cc;
}

function makeService(adapter: CapturingAdapter, prefs: MemPrefs, bound: boolean): CloudWishlistService {
  const cc: CloudCredentials = bound ? makeBoundCreds() : makeUnboundCreds();
  const svc: CloudWishlistService = new CloudWishlistService(cc, adapter, BASE);
  svc.injectPreferences(prefs);
  svc.injectClock((): number => 1746068001234);
  return svc;
}

export default function cloudWishlistServiceTest(): void {
  describe('CloudWishlistService.refreshList', () => {
    it('returnsFalseWhenUnbound', 0, async () => {
      const adapter: CapturingAdapter = new CapturingAdapter();
      const svc: CloudWishlistService = makeService(adapter, new MemPrefs(), false);
      const ok: boolean = await svc.refreshList();
      expect(ok).assertEqual(false);
      expect(adapter.requests.length).assertEqual(0);
    });

    it('parsesActiveItemsAndCachesThem', 0, async () => {
      const adapter: CapturingAdapter = new CapturingAdapter();
      adapter.enqueue(
        200,
        '{"items":[{"item_id":"wsh-1","child_profile_id":"child-deadbeef","display_name":"冰棍","cost_coins":15,"icon_emoji":"🍦","state":"active","is_parent_curated":true,"created_by":"parent"}]}',
      );
      const svc: CloudWishlistService = makeService(adapter, new MemPrefs(), true);
      const ok: boolean = await svc.refreshList();
      expect(ok).assertEqual(true);
      const items: CloudWishlistItem[] = svc.cachedItems();
      expect(items.length).assertEqual(1);
      expect(items[0].displayName).assertEqual('冰棍');
      expect(items[0].costCoins).assertEqual(15);
      expect(items[0].iconEmoji).assertEqual('🍦');
      expect(adapter.requests[0].auth).assertEqual('Bearer jwt.body.sig');
    });

    it('returnsFalseAndKeepsCacheOnNetworkError', 0, async () => {
      const adapter: CapturingAdapter = new CapturingAdapter();
      adapter.enqueue(
        200,
        '{"items":[{"item_id":"wsh-1","display_name":"x","cost_coins":10}]}',
      );
      const svc: CloudWishlistService = makeService(adapter, new MemPrefs(), true);
      await svc.refreshList();
      adapter.failNetwork = true;
      const second: boolean = await svc.refreshList();
      expect(second).assertEqual(false);
      expect(svc.cachedItems().length).assertEqual(1);
    });
  });

  describe('CloudWishlistService.requestRedemption', () => {
    it('returnsEmptyWhenUnbound', 0, async () => {
      const adapter: CapturingAdapter = new CapturingAdapter();
      const svc: CloudWishlistService = makeService(adapter, new MemPrefs(), false);
      const id: string = await svc.requestRedemption('wsh-1', '冰棍', 15);
      expect(id).assertEqual('');
    });

    it('postsAndStoresPendingEntry', 0, async () => {
      const adapter: CapturingAdapter = new CapturingAdapter();
      adapter.enqueue(
        201,
        '{"request_id":"rdm-aaaa1111","wishlist_item_id":"wsh-1","cost_coins_at_request":15,"status":"pending"}',
      );
      const prefs: MemPrefs = new MemPrefs();
      const svc: CloudWishlistService = makeService(adapter, prefs, true);
      const id: string = await svc.requestRedemption('wsh-1', '冰棍', 15);
      expect(id).assertEqual('rdm-aaaa1111');
      expect(adapter.requests[0].url.indexOf('/api/v1/child/redemption-requests')).assertLargerOrEqual(0);
      expect(adapter.requests[0].body.indexOf('"wishlist_item_id":"wsh-1"')).assertLargerOrEqual(0);
      const pending: PendingRedemption | undefined = svc.pendingFor('wsh-1');
      expect(pending !== undefined).assertEqual(true);
      expect((pending as PendingRedemption).requestId).assertEqual('rdm-aaaa1111');
      // persisted
      const persisted: string = prefs.store.get('pending_redemptions_v1') ?? '';
      expect(persisted.indexOf('rdm-aaaa1111')).assertLargerOrEqual(0);
    });

    it('returnsEmptyAndDoesNotStoreOnConflict', 0, async () => {
      const adapter: CapturingAdapter = new CapturingAdapter();
      adapter.enqueue(409, '{"detail":{"error":{"code":"ITEM_INACTIVE"}}}');
      const prefs: MemPrefs = new MemPrefs();
      const svc: CloudWishlistService = makeService(adapter, prefs, true);
      const id: string = await svc.requestRedemption('wsh-1', '冰棍', 15);
      expect(id).assertEqual('');
      expect(svc.pendingFor('wsh-1')).assertEqual(undefined);
    });

    it('returnsEmptyOnNetworkError', 0, async () => {
      const adapter: CapturingAdapter = new CapturingAdapter();
      adapter.failNetwork = true;
      const svc: CloudWishlistService = makeService(adapter, new MemPrefs(), true);
      const id: string = await svc.requestRedemption('wsh-1', '冰棍', 15);
      expect(id).assertEqual('');
    });
  });

  describe('CloudWishlistService.hydrate', () => {
    it('rebuildsPendingFromPersistedJson', 0, async () => {
      const adapter: CapturingAdapter = new CapturingAdapter();
      const prefs: MemPrefs = new MemPrefs();
      prefs.store.set(
        'pending_redemptions_v1',
        '{"pending":[{"request_id":"rdm-x1","wishlist_item_id":"wsh-x1","display_name":"棒棒糖","cost_coins":20,"requested_at_ms":1700}]}',
      );
      const svc: CloudWishlistService = makeService(adapter, prefs, true);
      await svc.hydrate();
      const pending: PendingRedemption | undefined = svc.pendingFor('wsh-x1');
      expect(pending !== undefined).assertEqual(true);
      expect((pending as PendingRedemption).displayName).assertEqual('棒棒糖');
    });
  });

  describe('CloudWishlistService.pollDecisions', () => {
    it('returnsEmptyWhenUnbound', 0, async () => {
      const adapter: CapturingAdapter = new CapturingAdapter();
      const svc: CloudWishlistService = makeService(adapter, new MemPrefs(), false);
      const ds: RedemptionDecision[] = await svc.pollDecisions();
      expect(ds.length).assertEqual(0);
    });

    it('parsesDecisionsAndAdvancesCursor', 0, async () => {
      const adapter: CapturingAdapter = new CapturingAdapter();
      adapter.enqueue(
        200,
        '{"items":[{"request_id":"rdm-1","wishlist_item_id":"wsh-1","cost_coins_at_request":20,"status":"approved","decided_at":"2026-05-01T15:00:00Z"}],"server_now_ms":1746111111000}',
      );
      const prefs: MemPrefs = new MemPrefs();
      const svc: CloudWishlistService = makeService(adapter, prefs, true);
      const ds: RedemptionDecision[] = await svc.pollDecisions();
      expect(ds.length).assertEqual(1);
      expect(ds[0].requestId).assertEqual('rdm-1');
      expect(ds[0].status).assertEqual('approved');
      expect(ds[0].costCoinsAtRequest).assertEqual(20);
      expect(ds[0].decidedAtMs > 0).assertEqual(true);
      expect(prefs.store.get('redemption_poll_since_ms') ?? '').assertEqual('1746111111000');
      expect(adapter.requests[0].url.indexOf('since_ms=0')).assertLargerOrEqual(0);
    });

    it('forwardsPersistedSinceMs', 0, async () => {
      const adapter: CapturingAdapter = new CapturingAdapter();
      adapter.enqueue(200, '{"items":[],"server_now_ms":1746111122000}');
      const prefs: MemPrefs = new MemPrefs();
      prefs.store.set('redemption_poll_since_ms', '1746111000000');
      const svc: CloudWishlistService = makeService(adapter, prefs, true);
      await svc.pollDecisions();
      expect(adapter.requests[0].url.indexOf('since_ms=1746111000000')).assertLargerOrEqual(0);
    });
  });

  describe('CloudWishlistService.resolvePending', () => {
    it('removesPendingByRequestIdAndPersists', 0, async () => {
      const adapter: CapturingAdapter = new CapturingAdapter();
      adapter.enqueue(
        201,
        '{"request_id":"rdm-aaaa1111","wishlist_item_id":"wsh-1","cost_coins_at_request":15}',
      );
      const prefs: MemPrefs = new MemPrefs();
      const svc: CloudWishlistService = makeService(adapter, prefs, true);
      await svc.requestRedemption('wsh-1', '冰棍', 15);
      await svc.resolvePending('rdm-aaaa1111');
      expect(svc.pendingFor('wsh-1')).assertEqual(undefined);
      const persisted: string = prefs.store.get('pending_redemptions_v1') ?? '';
      expect(persisted.indexOf('rdm-aaaa1111')).assertEqual(-1);
    });
  });
}
