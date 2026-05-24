import { describe, it, expect } from '@ohos/hypium';
import { StringPreferencesLike } from '../main/ets/services/WrongAnswerStore';
import { CheckInRecordResult, CheckInStore } from '../main/ets/services/CheckInStore';
import { CheckInSnapshot } from '../main/ets/models/CheckInSnapshot';

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

function ts(dayKey: string): number {
  return Date.parse(`${dayKey}T12:00:00`);
}

function freshStore(): CheckInStore {
  const store: CheckInStore = new CheckInStore();
  store.injectPreferencesForTest(new MapPrefs());
  return store;
}

export default function checkInStoreTest() {
  describe('CheckInStore', () => {
    it('firstWinRecordsDay', 0, async () => {
      const store: CheckInStore = freshStore();
      const result: CheckInRecordResult = await store.recordWin(ts('2026-05-01'));
      const snap: CheckInSnapshot = store.snapshot();
      expect(result.changed).assertTrue();
      expect(result.dayKey).assertEqual('2026-05-01');
      expect(result.currentStreak).assertEqual(1);
      expect(result.bonusCoins).assertEqual(0);
      expect(snap.checkedDayKeys.length).assertEqual(1);
      expect(snap.checkedDayKeys[0]).assertEqual('2026-05-01');
      expect(snap.pendingSync).assertTrue();
    });

    it('sameDayRepeatIsIdempotent', 0, async () => {
      const store: CheckInStore = freshStore();
      await store.recordWin(ts('2026-05-01'));
      const again: CheckInRecordResult = await store.recordWin(ts('2026-05-01'));
      const snap: CheckInSnapshot = store.snapshot();
      expect(again.changed).assertFalse();
      expect(again.currentStreak).assertEqual(1);
      expect(again.bonusCoins).assertEqual(0);
      expect(snap.checkedDayKeys.length).assertEqual(1);
    });

    it('seventhContiguousDayAwardsWeeklyBonusOnce', 0, async () => {
      const store: CheckInStore = freshStore();
      let last: CheckInRecordResult = new CheckInRecordResult();
      for (let i = 1; i <= 7; i++) {
        const day: string = i < 10 ? `2026-05-0${i}` : `2026-05-${i}`;
        last = await store.recordWin(ts(day));
      }
      const repeat: CheckInRecordResult = await store.recordWin(ts('2026-05-07'));
      const snap: CheckInSnapshot = store.snapshot();
      expect(last.changed).assertTrue();
      expect(last.currentStreak).assertEqual(7);
      expect(last.bonusCoins).assertEqual(50);
      expect(last.bonusDayKey).assertEqual('2026-05-07');
      expect(repeat.bonusCoins).assertEqual(0);
      expect(snap.weeklyBonusDayKeys.length).assertEqual(1);
      expect(snap.weeklyBonusDayKeys[0]).assertEqual('2026-05-07');
    });

    it('missedDayResetsCurrentStreakAndPreservesBest', 0, async () => {
      const store: CheckInStore = freshStore();
      await store.recordWin(ts('2026-05-01'));
      await store.recordWin(ts('2026-05-02'));
      await store.recordWin(ts('2026-05-04'));
      const snap: CheckInSnapshot = store.snapshot();
      expect(snap.currentStreak).assertEqual(1);
      expect(snap.bestStreak).assertEqual(2);
    });

    it('applyCloudMergeUnionsDaysAndRecomputesStreak', 0, async () => {
      const store: CheckInStore = freshStore();
      await store.recordWin(ts('2026-05-01'));
      await store.applyCloudMerge(
        ['2026-05-01', '2026-05-02', '2026-05-03'],
        ['2026-05-07'],
        1778112000000,
      );
      const snap: CheckInSnapshot = store.snapshot();
      expect(snap.checkedDayKeys.length).assertEqual(3);
      expect(snap.currentStreak).assertEqual(3);
      expect(snap.bestStreak).assertEqual(3);
      expect(snap.weeklyBonusDayKeys.length).assertEqual(1);
      expect(snap.pendingSync).assertFalse();
      expect(snap.lastSyncedAtMs).assertEqual(1778112000000);
    });
  });
}
