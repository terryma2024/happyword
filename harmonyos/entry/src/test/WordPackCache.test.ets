import { describe, it, expect } from '@ohos/hypium';
import { WordPackCache, WordPackCacheRecord } from '../main/ets/services/WordPackCache';
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
      prefs.store.set('pack_v2', '{not json}');
      cache.injectPreferencesForTest(prefs);
      const got: string = await cache.read();
      expect(got).assertEqual('');
    });

    it('rejectsPackMissingWordsField', 0, async () => {
      const cache: WordPackCache = new WordPackCache();
      const prefs: MapPrefs = new MapPrefs();
      prefs.store.set('pack_v2', '{"version":1}');
      cache.injectPreferencesForTest(prefs);
      const got: string = await cache.read();
      expect(got).assertEqual('');
    });

    it('storesAndReadsBackEnvelope', 0, async () => {
      const cache: WordPackCache = new WordPackCache();
      cache.injectPreferencesForTest(new MapPrefs());
      await cache.writeRecord(VALID_PACK_JSON, '"4"', 5);
      const rec: WordPackCacheRecord | undefined = await cache.readRecord();
      expect(rec !== undefined).assertTrue();
      if (rec !== undefined) {
        expect(rec.body).assertEqual(VALID_PACK_JSON);
        expect(rec.etag).assertEqual('"4"');
        expect(rec.schemaVersion).assertEqual(5);
        expect(rec.fetchedAt.length > 0).assertTrue();
      }
      // Legacy `read()` API still returns just the body so VC0.5.A
      // bootstrappers keep working.
      const body: string = await cache.read();
      expect(body).assertEqual(VALID_PACK_JSON);
    });

    it('readRecordReturnsUndefinedWhenSlotEmpty', 0, async () => {
      const cache: WordPackCache = new WordPackCache();
      cache.injectPreferencesForTest(new MapPrefs());
      const rec: WordPackCacheRecord | undefined = await cache.readRecord();
      expect(rec === undefined).assertTrue();
    });

    it('readReturnsBodyWhenLegacyBarePackPresent', 0, async () => {
      // A bare pack written by VC0.5.A (no envelope) must still feed
      // bootstrap so the upgrade does not strand existing installs.
      const cache: WordPackCache = new WordPackCache();
      const prefs: MapPrefs = new MapPrefs();
      prefs.store.set('pack_v2', VALID_PACK_JSON);
      cache.injectPreferencesForTest(prefs);
      const got: string = await cache.read();
      expect(got).assertEqual(VALID_PACK_JSON);
      // No envelope present, so readRecord() reports no record.
      const rec: WordPackCacheRecord | undefined = await cache.readRecord();
      expect(rec === undefined).assertTrue();
    });

    it('touchFetchedAtUpdatesTimestampWithoutChangingBody', 0, async () => {
      const cache: WordPackCache = new WordPackCache();
      cache.injectPreferencesForTest(new MapPrefs());
      await cache.writeRecord(VALID_PACK_JSON, '"4"', 5);
      const before: WordPackCacheRecord | undefined = await cache.readRecord();
      expect(before !== undefined).assertTrue();
      // Force a measurable timestamp delta. Date.now() resolution is 1 ms
      // on the Previewer so even a 5-ms wait is plenty.
      await new Promise<void>((resolve): void => { setTimeout(resolve, 5); });
      await cache.touchFetchedAt();
      const after: WordPackCacheRecord | undefined = await cache.readRecord();
      expect(after !== undefined).assertTrue();
      if (before !== undefined && after !== undefined) {
        expect(after.body).assertEqual(before.body);
        expect(after.etag).assertEqual(before.etag);
        expect(after.schemaVersion).assertEqual(before.schemaVersion);
        expect(after.fetchedAt !== before.fetchedAt).assertTrue();
      }
    });
  });
}
