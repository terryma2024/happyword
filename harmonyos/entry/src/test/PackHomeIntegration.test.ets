import { describe, it, expect } from '@ohos/hypium';
import { AdventureRegion } from '../main/ets/models/AdventureRegion';
import { Pack } from '../main/ets/models/Pack';
import { WordEntry } from '../main/ets/models/WordEntry';
import { ADVENTURE_REGIONS } from '../main/ets/data/AdventureCatalog';
import {
  fallbackPackFromRegion,
  homePackStoryLine,
  HomeIntegrationBundle,
  resolveHomeChipSelection,
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

function makeWordWithDifficulty(id: string, difficulty: number): WordEntry {
  const w: WordEntry = makeWord(id, id);
  w.difficulty = difficulty;
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

  describe('PackHomeIntegration.resolveHomeChipSelection', () => {
    it('resolvesSyntheticChipPackToLibraryPackWithWords', 0, () => {
      const selected: Pack = makePack('school-castle', 'school');
      const other: Pack = makePack('fruit-forest', 'fruit');
      const bundle: HomeIntegrationBundle = makeBundle([other, selected]);
      const synthetic: Pack = fallbackPackFromRegion(ADVENTURE_REGIONS[1]);

      const resolved: Pack = resolveHomeChipSelection(bundle, synthetic);

      expect(resolved.id).assertEqual('school-castle');
      expect(resolved.words.length).assertEqual(2);
      expect(resolved.words[0].id.startsWith('school-')).assertTrue();
    });
  });

  describe('PackHomeIntegration.homePackStoryLine', () => {
    it('prefersPackLittleStoryWhenPresent', 0, () => {
      const pack: Pack = makePack('storybook', 'story');
      pack.scene.storyZh = '跟着小魔法师走进故事森林。';

      expect(homePackStoryLine(pack)).assertEqual('跟着小魔法师走进故事森林。');
    });

    it('summarizesDifficultyBucketsAndSkipsZeroBuckets', 0, () => {
      const pack: Pack = new Pack();
      pack.id = 'mixed';
      pack.name = 'Mixed';
      pack.words = [
        makeWordWithDifficulty('low-1', 1),
        makeWordWithDifficulty('low-2', 1),
        makeWordWithDifficulty('mid-1', 2),
        makeWordWithDifficulty('high-1', 3),
        makeWordWithDifficulty('high-2', 3),
        makeWordWithDifficulty('high-3', 3),
      ];

      expect(homePackStoryLine(pack)).assertEqual('本词包 6 个单词，其中 2 个低难度，1 个中难度，3 个高难度');
    });

    it('omitsDifficultyPhrasesWithNoWords', 0, () => {
      const pack: Pack = new Pack();
      pack.id = 'low-only';
      pack.name = 'Low Only';
      pack.words = [
        makeWordWithDifficulty('low-1', 1),
        makeWordWithDifficulty('low-2', 1),
      ];

      expect(homePackStoryLine(pack)).assertEqual('本词包 2 个单词，其中 2 个低难度');
    });
  });
}
