import { describe, it, expect } from '@ohos/hypium';
import { MonsterEntry, MonsterKind, MONSTER_CATALOG } from '../main/ets/data/MonsterCatalog';
import {
  assetPathForEntry,
  characterAssetForKind,
  PLAYER_CHARACTER_ASSET,
} from '../main/ets/data/CharacterAssets';

export default function characterAssetsTests() {
  describe('CharacterAssets', () => {
    it('mapsNormalToSlime', 0, () => {
      expect(characterAssetForKind(MonsterKind.Normal)).assertEqual('character/slime.svg');
    });
    it('mapsSpellingToZombie', 0, () => {
      expect(characterAssetForKind(MonsterKind.Spelling)).assertEqual('character/zombie.svg');
    });
    it('mapsReviewToZombie', 0, () => {
      expect(characterAssetForKind(MonsterKind.Review)).assertEqual('character/zombie.svg');
    });
    it('mapsEliteToDragon', 0, () => {
      expect(characterAssetForKind(MonsterKind.Elite)).assertEqual('character/dragon.svg');
    });
    it('mapsBossToDragon', 0, () => {
      expect(characterAssetForKind(MonsterKind.Boss)).assertEqual('character/dragon.svg');
    });
    it('playerAssetIsMagican', 0, () => {
      expect(PLAYER_CHARACTER_ASSET).assertEqual('character/magican.svg');
    });
    it('allPathsLookLikeSvgRawfile', 0, () => {
      const paths: string[] = [
        characterAssetForKind(MonsterKind.Normal),
        characterAssetForKind(MonsterKind.Spelling),
        characterAssetForKind(MonsterKind.Review),
        characterAssetForKind(MonsterKind.Elite),
        characterAssetForKind(MonsterKind.Boss),
        PLAYER_CHARACTER_ASSET,
      ];
      for (let i: number = 0; i < paths.length; i++) {
        expect(paths[i].startsWith('character/')).assertTrue();
        expect(paths[i].endsWith('.svg')).assertTrue();
      }
    });
  });

  describe('V0.3.8 assetPathForEntry', () => {
    it('honorsExplicitAssetPath', 0, () => {
      const e: MonsterEntry = new MonsterEntry();
      e.kind = MonsterKind.Boss;
      e.assetPath = 'character/witch.svg';
      expect(assetPathForEntry(e)).assertEqual('character/witch.svg');
    });

    it('fallsBackForEmptyPathOnNormalKind', 0, () => {
      const e: MonsterEntry = new MonsterEntry();
      e.kind = MonsterKind.Normal;
      expect(assetPathForEntry(e)).assertEqual(characterAssetForKind(MonsterKind.Normal));
    });

    it('fallsBackForEmptyPathOnBossKind', 0, () => {
      const e: MonsterEntry = new MonsterEntry();
      e.kind = MonsterKind.Boss;
      expect(assetPathForEntry(e)).assertEqual(characterAssetForKind(MonsterKind.Boss));
    });

    it('resolvesEveryCatalogEntryToNonEmptySvgPath', 0, () => {
      for (let i: number = 0; i < MONSTER_CATALOG.length; i++) {
        const path: string = assetPathForEntry(MONSTER_CATALOG[i]);
        expect(path.length > 0).assertTrue();
        expect(path.startsWith('character/')).assertTrue();
        expect(path.endsWith('.svg')).assertTrue();
      }
    });

    it('explicitPathBeatsKindBucketEvenForLegacyArchetype', 0, () => {
      // Override demonstrates the "explicit wins" rule even when the
      // entry is kind=Normal (whose fallback is slime.svg).
      const e: MonsterEntry = new MonsterEntry();
      e.kind = MonsterKind.Normal;
      e.assetPath = 'character/witch.svg';
      expect(assetPathForEntry(e)).assertEqual('character/witch.svg');
    });
  });
}

