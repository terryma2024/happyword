import { describe, it, expect } from '@ohos/hypium';
import { MonsterKind } from '../main/ets/data/MonsterCatalog';
import {
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
}

