import { describe, it, expect } from '@ohos/hypium';
import { CoinAccount } from '../main/ets/services/CoinAccount';
import {
  CoinSnapshot,
  DAILY_CAP,
  MAX_TXN_HISTORY,
  formatDayKeyLocal,
} from '../main/ets/models/CoinSnapshot';
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

const NOW: number = Date.parse('2026-04-28T03:00:00Z');

function freshAccount(): CoinAccount {
  const acct: CoinAccount = new CoinAccount();
  acct.injectPreferencesForTest(new MapPrefs());
  acct.beginToday(NOW);
  return acct;
}

export default function coinAccountTest() {
  describe('CoinAccount', () => {
    it('earnCreditsAndCapsAtDailyLimit', 0, () => {
      const acct: CoinAccount = freshAccount();
      const got1: number = acct.earn('today-first', 5, NOW);
      const got2: number = acct.earn('monster-defeat', 5, NOW);
      const got3: number = acct.earn('accuracy-80', 30, NOW);
      const snap: CoinSnapshot = acct.snapshot();
      expect(got1).assertEqual(5);
      expect(got2).assertEqual(5);
      expect(got3).assertEqual(DAILY_CAP - 10);
      expect(snap.todayCoinsEarned).assertEqual(DAILY_CAP);
      expect(snap.totalCoins).assertEqual(DAILY_CAP);
    });

    it('todayFirstSetsCompletionEvenIfCapped', 0, () => {
      const acct: CoinAccount = freshAccount();
      acct.earn('accuracy-80', DAILY_CAP, NOW);
      const got: number = acct.earn('today-first', 5, NOW);
      const snap: CoinSnapshot = acct.snapshot();
      expect(got).assertEqual(0);
      expect(snap.todayAdventureCompleted).assertTrue();
    });

    it('beginTodayResetsAcrossDayBoundary', 0, () => {
      const acct: CoinAccount = freshAccount();
      acct.earn('today-first', 5, NOW);
      const tomorrow: number = NOW + 24 * 3600 * 1000;
      acct.beginToday(tomorrow);
      const snap: CoinSnapshot = acct.snapshot();
      expect(snap.todayCoinsEarned).assertEqual(0);
      expect(snap.todayAdventureCompleted).assertFalse();
      expect(snap.todayDayKey).assertEqual(formatDayKeyLocal(tomorrow));
    });

    it('redeemDeductsRegardlessOfDailyCap', 0, () => {
      const acct: CoinAccount = freshAccount();
      acct.earn('today-first', 5, NOW);
      acct.earn('accuracy-80', 15, NOW);
      const ok: boolean = acct.redeem('wish-ipad-20min', 10);
      const snap: CoinSnapshot = acct.snapshot();
      expect(ok).assertTrue();
      expect(snap.spentCoins).assertEqual(10);
      expect(acct.balance()).assertEqual(10);
    });

    it('redeemRejectedWhenInsufficient', 0, () => {
      const acct: CoinAccount = freshAccount();
      const ok: boolean = acct.redeem('wish-something', 5);
      expect(ok).assertFalse();
      expect(acct.snapshot().spentCoins).assertEqual(0);
    });

    it('truncatesTxnHistoryToCap', 0, () => {
      const acct: CoinAccount = freshAccount();
      // Roll the day forward each iteration so beginToday resets the
      // cap and every earn writes a new txn.
      for (let i = 0; i < MAX_TXN_HISTORY + 5; i++) {
        const t: number = NOW + i * 24 * 3600 * 1000;
        acct.beginToday(t);
        acct.earn('today-first', 5, t);
      }
      expect(acct.snapshot().txns.length).assertEqual(MAX_TXN_HISTORY);
    });
  });
}
