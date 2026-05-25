import { describe, it, expect } from '@ohos/hypium';
import { AdventureRegion } from '../main/ets/models/AdventureRegion';
import { Pack } from '../main/ets/models/Pack';
import { WordEntry } from '../main/ets/models/WordEntry';
import { ADVENTURE_REGIONS } from '../main/ets/data/AdventureCatalog';
import {
  fallbackPackFromRegion,
  HomeIntegrationBundle,
  resolveTodayAdventurePack,
} from '../main/ets/services/PackHomeIntegration';
import { PackLibrary } from '../main/ets/services/PackLibrary';

function makeWord(id: string, word: string): WordEntry {
  const w: WordEntry = new WordEntry();
  w.id = id;
  w.word = word;
  w.meaningZh = '_';
  w.category = 'test';
  w.difficulty = 1;
  return w;
}

function makePack(id: string, wordPrefix: string): Pack {
  const p: Pack = new Pack();
  p.id = id;
  p.name = id;
  p.source = 'builtin';
  p.words = [
    makeWord(`${wordPrefix}-1`, `${wordPrefix}One`),
    makeWord(`${wordPrefix}-2`, `${wordPrefix}Two`),
  ];
  return p;
}

function makeBundle(packs: Pack[]): HomeIntegrationBundle {
  const lib: PackLibrary = new PackLibrary();
  lib.setBuiltins(packs);
  const bundle: HomeIntegrationBundle = new HomeIntegrationBundle();
  bundle.library = lib;
  return bundle;
}

export default function packHomeIntegrationTest() {
  describe('PackHomeIntegration.resolveTodayAdventurePack', () => {
    it('recoversPersistedPackWhenCurrentPackIsSyntheticFallback', 0, () => {
      const selected: Pack = makePack('school-castle', 'school');
      const other: Pack = makePack('fruit-forest', 'fruit');
      const bundle: HomeIntegrationBundle = makeBundle([other, selected]);
      const region: AdventureRegion = ADVENTURE_REGIONS[1];
      const current: Pack = fallbackPackFromRegion(region);

      const resolved: Pack = resolveTodayAdventurePack(bundle, current, 'school-castle');

      expect(resolved.id).assertEqual('school-castle');
      expect(resolved.words.length).assertEqual(2);
      expect(resolved.words[0].id.startsWith('school-')).assertTrue();
    });
  });
}
