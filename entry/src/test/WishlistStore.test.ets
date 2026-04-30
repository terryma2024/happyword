import { describe, it, expect } from '@ohos/hypium';
import { MagicWish, WishState, WISHLIST_PREFS_KEY } from '../main/ets/models/MagicWish';
import {
  WishlistStore,
  CUSTOM_WISH_DEFAULT_EMOJI,
  CUSTOM_WISH_NAME_MAX_CHARS,
  CUSTOM_WISH_COST_MAX,
} from '../main/ets/services/WishlistStore';
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

    // V0.3.9 ----- new flow: PIN gate + markConfirmed -----

    it('markConfirmedFlipsIdleToConfirmedAndStampsTimestamp', 0, () => {
      const store: WishlistStore = freshStore();
      const wishes: MagicWish[] = store.list();
      const target: MagicWish = wishes[0];
      expect(target.state).assertEqual(WishState.Idle);

      const ok: boolean = store.markConfirmed(target.id, 5000);
      expect(ok).assertTrue();

      const after: MagicWish = findWish(store.list(), target.id);
      expect(after.state).assertEqual(WishState.Confirmed);
      expect(after.confirmedAt).assertEqual(5000);
    });

    it('markConfirmedRefusesWhenWishIsNotIdle', 0, () => {
      const store: WishlistStore = freshStore();
      const target: MagicWish = store.list()[0];
      store.markConfirmed(target.id, 1000);
      expect(store.markConfirmed(target.id, 2000)).assertFalse();
    });

    it('markConfirmedRefusesUnknownWishId', 0, () => {
      const store: WishlistStore = freshStore();
      expect(store.markConfirmed('does-not-exist', 1000)).assertFalse();
    });

    it('acknowledgeRecyclesMarkConfirmedBackToIdleAndClearsTimestamps', 0, () => {
      const store: WishlistStore = freshStore();
      const target: MagicWish = store.list()[0];
      store.markConfirmed(target.id, 1000);
      store.acknowledge(target.id);

      const after: MagicWish = findWish(store.list(), target.id);
      expect(after.state).assertEqual(WishState.Idle);
      expect(after.requestedAt).assertEqual(0);
      expect(after.confirmedAt).assertEqual(0);
    });

    // V0.4.7 ----- new flow: parent-created custom wishes -----

    it('addCustomWishAppendsAtEndAndMarksIsCustomTrue', 0, () => {
      const store: WishlistStore = freshStore();
      const before: number = store.list().length;
      const newId: string = store.addCustomWish('看动画 30 分钟', 15, '🎬', 1700000000000);
      expect(newId.length > 0).assertTrue();
      const after: MagicWish[] = store.list();
      expect(after.length).assertEqual(before + 1);
      const last: MagicWish = after[after.length - 1];
      expect(last.id).assertEqual(newId);
      expect(last.displayName).assertEqual('看动画 30 分钟');
      expect(last.costCoins).assertEqual(15);
      expect(last.iconEmoji).assertEqual('🎬');
      expect(last.isCustom).assertTrue();
      expect(last.state).assertEqual(WishState.Idle);
    });

    it('addCustomWishGeneratesIdWithCustomPrefix', 0, () => {
      const store: WishlistStore = freshStore();
      const id: string = store.addCustomWish('小奖励', 8, '🎁', 99);
      expect(id.indexOf('custom-')).assertEqual(0);
    });

    it('addCustomWishFallsBackToDefaultEmojiWhenBlank', 0, () => {
      const store: WishlistStore = freshStore();
      const id: string = store.addCustomWish('小奖励', 8, '   ', 99);
      const w: MagicWish = findWish(store.list(), id);
      expect(w.iconEmoji).assertEqual(CUSTOM_WISH_DEFAULT_EMOJI);
    });

    it('addCustomWishRejectsEmptyName', 0, () => {
      const store: WishlistStore = freshStore();
      const id: string = store.addCustomWish('   ', 10, '🎬', 1);
      expect(id).assertEqual('');
      expect(store.list().length).assertEqual(3);
    });

    it('addCustomWishRejectsOverlongName', 0, () => {
      const store: WishlistStore = freshStore();
      let longName: string = '';
      for (let i = 0; i < CUSTOM_WISH_NAME_MAX_CHARS + 1; i++) {
        longName = longName + 'a';
      }
      const id: string = store.addCustomWish(longName, 10, '🎬', 1);
      expect(id).assertEqual('');
    });

    it('addCustomWishRejectsCostBelowMinimum', 0, () => {
      const store: WishlistStore = freshStore();
      const id: string = store.addCustomWish('小奖励', 1, '🎬', 1);
      expect(id).assertEqual('');
    });

    it('addCustomWishRejectsCostAboveMaximum', 0, () => {
      const store: WishlistStore = freshStore();
      const id: string = store.addCustomWish('小奖励', CUSTOM_WISH_COST_MAX + 1, '🎬', 1);
      expect(id).assertEqual('');
    });

    it('addCustomWishCoercesNonIntegerCost', 0, () => {
      const store: WishlistStore = freshStore();
      const id: string = store.addCustomWish('小奖励', 12.7, '🎬', 1);
      const w: MagicWish = findWish(store.list(), id);
      expect(w.costCoins).assertEqual(12);
    });

    it('removeCustomWishDropsTheWish', 0, () => {
      const store: WishlistStore = freshStore();
      const id: string = store.addCustomWish('小奖励', 8, '🎁', 99);
      const ok: boolean = store.removeCustomWish(id);
      expect(ok).assertTrue();
      expect(findWish(store.list(), id).id.length).assertEqual(0);
    });

    it('removeCustomWishRefusesDefaultCatalogIds', 0, () => {
      const store: WishlistStore = freshStore();
      const ok: boolean = store.removeCustomWish('wish-ipad-20min');
      expect(ok).assertFalse();
      expect(findWish(store.list(), 'wish-ipad-20min').id).assertEqual('wish-ipad-20min');
    });

    it('removeCustomWishRefusesUnknownId', 0, () => {
      const store: WishlistStore = freshStore();
      expect(store.removeCustomWish('does-not-exist')).assertFalse();
    });

    it('addThenRehydratePersistsCustomWish', 0, async () => {
      const prefs: MapPrefs = new MapPrefs();
      const store: WishlistStore = new WishlistStore();
      store.injectPreferencesForTest(prefs);
      const id: string = store.addCustomWish('看动画 30 分钟', 15, '🎬', 1700000000000);
      await store.flushNow();

      const reborn: WishlistStore = new WishlistStore();
      reborn.injectPreferencesForTest(prefs);
      await reborn.rehydrateForTest();
      const w: MagicWish = findWish(reborn.list(), id);
      expect(w.id).assertEqual(id);
      expect(w.displayName).assertEqual('看动画 30 分钟');
      expect(w.costCoins).assertEqual(15);
      expect(w.iconEmoji).assertEqual('🎬');
      expect(w.isCustom).assertTrue();
    });

    it('rehydrateAcceptsLegacyV1JsonAndDefaultsIsCustomToFalse', 0, async () => {
      const prefs: MapPrefs = new MapPrefs();
      const legacyJson: string =
        '{"version":1,"wishes":[' +
        '{"id":"wish-ipad-20min","displayName":"看 iPad 20 分钟","costCoins":10,' +
        '"iconEmoji":"📱","state":"idle","requestedAt":0,"confirmedAt":0}' +
        ']}';
      await prefs.putString(WISHLIST_PREFS_KEY, legacyJson);
      const store: WishlistStore = new WishlistStore();
      store.injectPreferencesForTest(prefs);
      await store.rehydrateForTest();
      const w: MagicWish = findWish(store.list(), 'wish-ipad-20min');
      expect(w.isCustom).assertFalse();
    });

    it('rehydrateNormalisesLegacyPendingStateToIdle', 0, async () => {
      const prefs: MapPrefs = new MapPrefs();
      // V0.3.8 schema: state literal 'pending' was a real value; v0.3.9
      // reader normalises it to Idle on rehydrate. Build the snapshot
      // as raw JSON since ArkTS forbids untyped object literals.
      const legacyJson: string =
        '{"version":1,"wishes":[' +
        '{"id":"wish-ipad-20min","displayName":"看 iPad 20 分钟","costCoins":10,' +
        '"iconEmoji":"📱","state":"pending","requestedAt":12345,"confirmedAt":0}' +
        ']}';
      await prefs.putString(WISHLIST_PREFS_KEY, legacyJson);

      const store: WishlistStore = new WishlistStore();
      store.injectPreferencesForTest(prefs);
      await store.rehydrateForTest();

      const w: MagicWish = findWish(store.list(), 'wish-ipad-20min');
      expect(w.state).assertEqual(WishState.Idle);
    });
  });
}
