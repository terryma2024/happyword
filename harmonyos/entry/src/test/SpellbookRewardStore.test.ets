import { describe, it, expect } from '@ohos/hypium';
import { StringPreferencesLike } from '../main/ets/services/WrongAnswerStore';
import {
  SPELLBOOK_REWARD_PREFS_KEY,
  SpellbookRewardSnapshot,
  SpellbookRewardStore,
  parseSpellbookRewardSnapshot,
  serializeSpellbookRewardSnapshot,
} from '../main/ets/services/SpellbookRewardStore';

class MapPrefs implements StringPreferencesLike {
  private map: Map<string, string> = new Map<string, string>();
  flushCount: number = 0;

  getString(key: string): Promise<string> {
    return Promise.resolve(this.map.has(key) ? (this.map.get(key) as string) : '');
  }

  putString(key: string, value: string): Promise<void> {
    this.map.set(key, value);
    return Promise.resolve();
  }

  flush(): Promise<void> {
    this.flushCount += 1;
    return Promise.resolve();
  }

  raw(key: string): string {
    return this.map.has(key) ? (this.map.get(key) as string) : '';
  }
}

export default function spellbookRewardStoreTest(): void {
  describe('SpellbookRewardStore', () => {
    it('parsesMalformedJsonAsEmptyV1Snapshot', 0, () => {
      const snap: SpellbookRewardSnapshot = parseSpellbookRewardSnapshot('{bad');
      expect(snap.version).assertEqual(1);
      expect(snap.claimedPackIds.length).assertEqual(0);
    });

    it('parsesValidJsonAndDropsEmptyDuplicatePackIds', 0, () => {
      const snap: SpellbookRewardSnapshot = parseSpellbookRewardSnapshot(
        '{"version":1,"claimedPackIds":["fruit-forest","","fruit-forest","school-castle"]}',
      );
      expect(snap.claimedPackIds.length).assertEqual(2);
      expect(snap.claimedPackIds[0]).assertEqual('fruit-forest');
      expect(snap.claimedPackIds[1]).assertEqual('school-castle');
    });

    it('serializesSnapshot', 0, () => {
      const snap: SpellbookRewardSnapshot = new SpellbookRewardSnapshot();
      snap.claimedPackIds = ['fruit-forest'];
      expect(serializeSpellbookRewardSnapshot(snap))
        .assertEqual('{"version":1,"claimedPackIds":["fruit-forest"]}');
    });

    it('claimPackIdPersistsOnceAndIsIdempotent', 0, async () => {
      const prefs: MapPrefs = new MapPrefs();
      const store: SpellbookRewardStore = new SpellbookRewardStore();
      store.injectPreferencesForTest(prefs);
      const first: boolean = await store.claimPackId('fruit-forest');
      const second: boolean = await store.claimPackId('fruit-forest');
      const snap: SpellbookRewardSnapshot =
        parseSpellbookRewardSnapshot(prefs.raw(SPELLBOOK_REWARD_PREFS_KEY));
      expect(first).assertTrue();
      expect(second).assertFalse();
      expect(store.hasClaimed('fruit-forest')).assertTrue();
      expect(snap.claimedPackIds.length).assertEqual(1);
      expect(prefs.flushCount).assertEqual(1);
    });
  });
}
