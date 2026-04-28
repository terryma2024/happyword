import { describe, it, expect } from '@ohos/hypium';
import { MagicWish, WishState } from '../main/ets/models/MagicWish';
import { WishlistStore } from '../main/ets/services/WishlistStore';
import { CoinAccount } from '../main/ets/services/CoinAccount';
import { StringPreferencesLike } from '../main/ets/services/WrongAnswerStore';

class MapPrefs implements StringPreferencesLike {
  private map: Map<string, string> = new Map<string, string>();
  getString(key: string): Promise<string> {
    return Promise.resolve(this.map.has(key) ? (this.map.get(key) as string) : '');
  }
  putString(key: string, value: string): Promise<void> {
    this.map.set(key, value);
    return Promise.resolve();
  }
  flush(): Promise<void> {
    return Promise.resolve();
  }
}

const NOW: number = 1700_000_000_000;

function makeAccountWithCoins(amount: number): CoinAccount {
  const acct: CoinAccount = new CoinAccount();
  acct.injectPreferencesForTest(new MapPrefs());
  acct.beginToday(NOW);
  // The daily cap is 20; tests calling for 25 still succeed because
  // we add one earn per call without crossing the cap in any single call.
  acct.earn('today-first', amount, NOW);
  return acct;
}

function freshStore(): WishlistStore {
  const store: WishlistStore = new WishlistStore();
  store.injectPreferencesForTest(new MapPrefs());
  return store;
}

function findWish(list: MagicWish[], id: string): MagicWish {
  for (let i = 0; i < list.length; i++) {
    if (list[i].id === id) {
      return list[i];
    }
  }
  return new MagicWish();
}

export default function wishlistStoreTest() {
  describe('WishlistStore', () => {
    it('listsThreeBuiltInWishesIdleByDefault', 0, () => {
      const store: WishlistStore = freshStore();
      const xs: MagicWish[] = store.list();
      expect(xs.length).assertEqual(3);
      for (let i = 0; i < xs.length; i++) {
        expect(xs[i].state).assertEqual(WishState.Idle);
      }
    });

    it('requestMovesIdleToPendingWhenBalanceSufficient', 0, () => {
      const store: WishlistStore = freshStore();
      const acct: CoinAccount = makeAccountWithCoins(20);
      const ok: boolean = store.request('wish-ipad-20min', acct, NOW);
      expect(ok).assertTrue();
      const w: MagicWish = findWish(store.list(), 'wish-ipad-20min');
      expect(w.state).assertEqual(WishState.Pending);
      expect(w.requestedAt).assertEqual(NOW);
    });

    it('requestRefusedWhenBalanceInsufficient', 0, () => {
      const store: WishlistStore = freshStore();
      const acct: CoinAccount = makeAccountWithCoins(5);
      const ok: boolean = store.request('wish-watch-topup-10', acct, NOW);
      expect(ok).assertFalse();
      expect(findWish(store.list(), 'wish-watch-topup-10').state).assertEqual(WishState.Idle);
    });

    it('confirmByParentRedeemsAndAdvancesState', 0, () => {
      const store: WishlistStore = freshStore();
      const acct: CoinAccount = makeAccountWithCoins(20);
      store.request('wish-ipad-20min', acct, NOW);
      const ok: boolean = store.confirmByParent('wish-ipad-20min', acct, NOW);
      expect(ok).assertTrue();
      expect(findWish(store.list(), 'wish-ipad-20min').state).assertEqual(WishState.Confirmed);
      expect(acct.snapshot().spentCoins).assertEqual(10);
    });

    it('confirmFailsWhenNotPending', 0, () => {
      const store: WishlistStore = freshStore();
      const acct: CoinAccount = makeAccountWithCoins(20);
      const ok: boolean = store.confirmByParent('wish-ipad-20min', acct, NOW);
      expect(ok).assertFalse();
      expect(acct.snapshot().spentCoins).assertEqual(0);
    });

    it('cancelReturnsPendingToIdle', 0, () => {
      const store: WishlistStore = freshStore();
      const acct: CoinAccount = makeAccountWithCoins(20);
      store.request('wish-ipad-20min', acct, NOW);
      store.cancel('wish-ipad-20min');
      expect(findWish(store.list(), 'wish-ipad-20min').state).assertEqual(WishState.Idle);
    });

    it('acknowledgeReturnsConfirmedToIdle', 0, () => {
      const store: WishlistStore = freshStore();
      const acct: CoinAccount = makeAccountWithCoins(20);
      store.request('wish-ipad-20min', acct, NOW);
      store.confirmByParent('wish-ipad-20min', acct, NOW);
      store.acknowledge('wish-ipad-20min');
      expect(findWish(store.list(), 'wish-ipad-20min').state).assertEqual(WishState.Idle);
    });
  });
}
