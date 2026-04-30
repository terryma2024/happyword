import { describe, it, expect } from '@ohos/hypium';
import { WordPackCache } from '../main/ets/services/WordPackCache';
import { StringPreferencesLike } from '../main/ets/services/WrongAnswerStore';

class MapPrefs implements StringPreferencesLike {
  readonly store: Map<string, string> = new Map<string, string>();
  async getString(key: string): Promise<string> {
    return this.store.get(key) ?? '';
  }
  async putString(key: string, value: string): Promise<void> {
    this.store.set(key, value);
  }
  async flush(): Promise<void> {}
}

const VALID_PACK_JSON: string =
  '{"version":1,"schema_version":1,"published_at":"2026-05-08T12:34:56Z",' +
  '"words":[{"id":"fruit-apple","word":"apple","meaningZh":"苹果","category":"fruit","difficulty":1}]}';

export default function wordPackCacheTest() {
  describe('WordPackCache', () => {
    it('readsEmptyWhenNothingStored', 0, async () => {
      const cache: WordPackCache = new WordPackCache();
      cache.injectPreferencesForTest(new MapPrefs());
      const got: string = await cache.read();
      expect(got).assertEqual('');
    });

    it('roundTripsValidPackJson', 0, async () => {
      const cache: WordPackCache = new WordPackCache();
      const prefs: MapPrefs = new MapPrefs();
      cache.injectPreferencesForTest(prefs);
      await cache.write(VALID_PACK_JSON);
      const got: string = await cache.read();
      expect(got).assertEqual(VALID_PACK_JSON);
    });

    it('rejectsObviouslyCorruptJson', 0, async () => {
      const cache: WordPackCache = new WordPackCache();
      const prefs: MapPrefs = new MapPrefs();
      prefs.store.set('pack_v1', '{not json}');
      cache.injectPreferencesForTest(prefs);
      const got: string = await cache.read();
      expect(got).assertEqual('');
    });

    it('rejectsPackMissingWordsField', 0, async () => {
      const cache: WordPackCache = new WordPackCache();
      const prefs: MapPrefs = new MapPrefs();
      prefs.store.set('pack_v1', '{"version":1}');
      cache.injectPreferencesForTest(prefs);
      const got: string = await cache.read();
      expect(got).assertEqual('');
    });
  });
}
