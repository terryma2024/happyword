import { describe, it, expect } from '@ohos/hypium';
import {
  RedemptionHistoryStore,
  __resetRedemptionHistoryStoreForTest,
  getRedemptionHistoryStore,
} from '../main/ets/services/RedemptionHistoryStore';
import {
  RedemptionRecord,
  REDEMPTION_HISTORY_CAP,
} from '../main/ets/models/RedemptionRecord';
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

function makeRecord(suffix: string, ts: number): RedemptionRecord {
  const r: RedemptionRecord = new RedemptionRecord();
  r.id = `r-${suffix}`;
  r.ts = ts;
  r.wishId = `wish-${suffix}`;
  r.displayName = `Wish ${suffix}`;
  r.iconEmoji = '🎁';
  r.costCoins = 10;
  return r;
}

function freshStore(): RedemptionHistoryStore {
  const s: RedemptionHistoryStore = new RedemptionHistoryStore();
  s.injectPreferencesForTest(new MapPrefs());
  return s;
}

export default function redemptionHistoryStoreTest() {
  describe('RedemptionHistoryStore', () => {
    it('startsEmptyBeforeAnyAdd', 0, () => {
      __resetRedemptionHistoryStoreForTest();
      const s: RedemptionHistoryStore = freshStore();
      expect(s.list().length).assertEqual(0);
    });

    it('addAppendsAndListReturnsDeepClones', 0, () => {
      __resetRedemptionHistoryStoreForTest();
      const s: RedemptionHistoryStore = freshStore();
      s.add(makeRecord('a', 1000));
      const out1: RedemptionRecord[] = s.list();
      expect(out1.length).assertEqual(1);
      out1[0].displayName = 'mutated-by-caller';
      const out2: RedemptionRecord[] = s.list();
      expect(out2[0].displayName).assertEqual('Wish a');
    });

    it('listReturnsNewestFirstByTs', 0, () => {
      __resetRedemptionHistoryStoreForTest();
      const s: RedemptionHistoryStore = freshStore();
      s.add(makeRecord('old', 1000));
      s.add(makeRecord('new', 5000));
      s.add(makeRecord('mid', 3000));
      const out: RedemptionRecord[] = s.list();
      expect(out.length).assertEqual(3);
      expect(out[0].id).assertEqual('r-new');
      expect(out[1].id).assertEqual('r-mid');
      expect(out[2].id).assertEqual('r-old');
    });

    it('dropsOldestWhenExceedingCap', 0, () => {
      __resetRedemptionHistoryStoreForTest();
      const s: RedemptionHistoryStore = freshStore();
      for (let i = 0; i < REDEMPTION_HISTORY_CAP + 1; i++) {
        s.add(makeRecord(`${i}`, i + 1));
      }
      const out: RedemptionRecord[] = s.list();
      expect(out.length).assertEqual(REDEMPTION_HISTORY_CAP);
      // ts=1 was the first (oldest) — should have been shifted out.
      for (let i = 0; i < out.length; i++) {
        expect(out[i].ts > 1).assertTrue();
      }
    });

    it('persistsSnapshotAcrossInstanceBoundary', 0, async () => {
      __resetRedemptionHistoryStoreForTest();
      const prefs: MapPrefs = new MapPrefs();

      const a: RedemptionHistoryStore = new RedemptionHistoryStore();
      a.injectPreferencesForTest(prefs);
      a.add(makeRecord('persisted', 2000));
      await a.flushNow();

      const b: RedemptionHistoryStore = new RedemptionHistoryStore();
      b.injectPreferencesForTest(prefs);
      await b.rehydrateForTest();

      const out: RedemptionRecord[] = b.list();
      expect(out.length).assertEqual(1);
      expect(out[0].id).assertEqual('r-persisted');
    });

    it('singletonReturnsSameInstance', 0, () => {
      __resetRedemptionHistoryStoreForTest();
      const a: RedemptionHistoryStore = getRedemptionHistoryStore();
      const b: RedemptionHistoryStore = getRedemptionHistoryStore();
      expect(a === b).assertTrue();
    });
  });
}
