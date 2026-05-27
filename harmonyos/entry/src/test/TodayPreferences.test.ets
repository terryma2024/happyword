import { describe, it, expect } from '@ohos/hypium';
import { TodayPreferences } from '../main/ets/services/TodayPreferences';
import { StringPreferencesLike } from '../main/ets/services/WrongAnswerStore';
import { DEFAULT_REGION_ID } from '../main/ets/data/AdventureCatalog';

class FakePrefs implements StringPreferencesLike {
  private readonly committed: Map<string, string> = new Map<string, string>();
  private readonly pending: Map<string, string> = new Map<string, string>();
  flushCount: number = 0;

  getString(key: string): Promise<string> {
    return Promise.resolve(this.committed.has(key) ? (this.committed.get(key) as string) : '');
  }

  putString(key: string, value: string): Promise<void> {
    this.pending.set(key, value);
    return Promise.resolve();
  }

  flush(): Promise<void> {
    this.pending.forEach((value: string, key: string): void => {
      this.committed.set(key, value);
    });
    this.pending.clear();
    this.flushCount = this.flushCount + 1;
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

    it('saveRegionIdFlushesBeforeResolving', 0, async () => {
      const backing: FakePrefs = new FakePrefs();
      const prefs: TodayPreferences = new TodayPreferences();
      prefs.injectPreferencesForTest(backing);
      await prefs.saveRegionId('school-castle');
      expect(backing.flushCount).assertEqual(1);
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
