import { describe, it, expect } from '@ohos/hypium';
import { TodayPreferences } from '../main/ets/services/TodayPreferences';
import { StringPreferencesLike } from '../main/ets/services/WrongAnswerStore';
import { DEFAULT_REGION_ID } from '../main/ets/data/AdventureCatalog';

class FakePrefs implements StringPreferencesLike {
  private readonly map: Map<string, string> = new Map<string, string>();

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

export default function todayPreferencesTest() {
  describe('TodayPreferences', () => {
    it('loadDefaultsToFruitForestWhenEmpty', 0, async () => {
      const prefs: TodayPreferences = new TodayPreferences();
      prefs.injectPreferencesForTest(new FakePrefs());
      const id: string = await prefs.loadRegionId();
      expect(id).assertEqual(DEFAULT_REGION_ID);
    });

    it('saveThenLoadRoundTripsKnownId', 0, async () => {
      const prefs: TodayPreferences = new TodayPreferences();
      prefs.injectPreferencesForTest(new FakePrefs());
      await prefs.saveRegionId('school-castle');
      const id: string = await prefs.loadRegionId();
      expect(id).assertEqual('school-castle');
    });

    it('illegalIdRollsBackToDefault', 0, async () => {
      const prefs: TodayPreferences = new TodayPreferences();
      prefs.injectPreferencesForTest(new FakePrefs());
      await prefs.saveRegionId('not-real');
      const id: string = await prefs.loadRegionId();
      expect(id).assertEqual(DEFAULT_REGION_ID);
    });
  });
}

