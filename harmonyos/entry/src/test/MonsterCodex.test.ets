import { describe, it, expect } from '@ohos/hypium';
import { CodexEntry, MONSTER_CODEX } from '../main/ets/data/MonsterCodex';
import { MonsterKind } from '../main/ets/data/MonsterCatalog';
import { characterAssetForKind } from '../main/ets/data/CharacterAssets';

const EXPECTED_FIRST_NAMES: string[] = ['Slime', 'Zombie', 'Dragon'];
const EXPECTED_FIRST_BOSS_NAMES: string[] = [
  'Pumpkin King',
  'Imp King',
  'Phoenix',
  'Witch',
  'Snow Queen',
  'Unicorn',
  'Kraken',
];
const EXPECTED_LAST_NAMES: string[] = [
  'Toadstool Ogre',
  'Toy Soldier',
  'Porcelain Doll',
  'Button Golem',
  'Sock Dragon',
  'Kite Serpent',
  'Music Box Fairy',
];

export default function monsterCodexTests() {
  describe('MonsterCodex', () => {
    it('hasExactlyOneHundredEntries', 0, () => {
      expect(MONSTER_CODEX.length).assertEqual(100);
    });

    it('eachEntryHasNonEmptyFields', 0, () => {
      for (let i: number = 0; i < MONSTER_CODEX.length; i++) {
        const e: CodexEntry = MONSTER_CODEX[i];
        expect(e.key.length > 0).assertTrue();
        expect(e.nameEn.length > 0).assertTrue();
        expect(e.kindLabelZh.length > 0).assertTrue();
        expect(e.descriptionZh.length > 0).assertTrue();
        expect(e.assetPath.length > 0).assertTrue();
      }
    });

    it('keepsOriginalFirstTenOrderAndAddsExpandedTail', 0, () => {
      for (let i: number = 0; i < EXPECTED_FIRST_NAMES.length; i++) {
        expect(MONSTER_CODEX[i].nameEn).assertEqual(EXPECTED_FIRST_NAMES[i]);
      }
      for (let i: number = 0; i < EXPECTED_FIRST_BOSS_NAMES.length; i++) {
        expect(MONSTER_CODEX[i + 3].nameEn).assertEqual(EXPECTED_FIRST_BOSS_NAMES[i]);
      }
      for (let i: number = 0; i < EXPECTED_LAST_NAMES.length; i++) {
        expect(MONSTER_CODEX[MONSTER_CODEX.length - EXPECTED_LAST_NAMES.length + i].nameEn)
          .assertEqual(EXPECTED_LAST_NAMES[i]);
      }
    });

    it('keysNamesAndAssetPathsAreUnique', 0, () => {
      const keys: Set<string> = new Set<string>();
      const names: Set<string> = new Set<string>();
      const assets: Set<string> = new Set<string>();
      for (let i: number = 0; i < MONSTER_CODEX.length; i++) {
        const e: CodexEntry = MONSTER_CODEX[i];
        expect(keys.has(e.key)).assertFalse();
        expect(names.has(e.nameEn)).assertFalse();
        expect(assets.has(e.assetPath)).assertFalse();
        keys.add(e.key);
        names.add(e.nameEn);
        assets.add(e.assetPath);
      }
    });

    it('descriptionLengthsWithinBounds', 0, () => {
      for (let i: number = 0; i < MONSTER_CODEX.length; i++) {
        const len: number = MONSTER_CODEX[i].descriptionZh.length;
        expect(len >= 40).assertTrue();
        expect(len <= 200).assertTrue();
      }
    });

    it('archetypeAssetsMatchCharacterAssetForKind', 0, () => {
      expect(MONSTER_CODEX[0].assetPath).assertEqual(characterAssetForKind(MonsterKind.Normal));
      expect(MONSTER_CODEX[1].assetPath).assertEqual(characterAssetForKind(MonsterKind.Spelling));
      expect(MONSTER_CODEX[2].assetPath).assertEqual(characterAssetForKind(MonsterKind.Elite));
    });

    it('expandedEntriesUseCharacterSvgPaths', 0, () => {
      for (let i: number = 0; i < MONSTER_CODEX.length; i++) {
        expect(MONSTER_CODEX[i].assetPath).assertEqual(`character/${MONSTER_CODEX[i].key}.svg`);
      }
    });
  });
}
