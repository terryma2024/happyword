import { describe, it, expect } from '@ohos/hypium';
import { CodexEntry, MONSTER_CODEX } from '../main/ets/data/MonsterCodex';
import { MonsterKind } from '../main/ets/data/MonsterCatalog';
import { characterAssetForKind } from '../main/ets/data/CharacterAssets';

export default function monsterCodexTests() {
  describe('MonsterCodex', () => {
    it('hasExactlyThreeEntries', 0, () => {
      expect(MONSTER_CODEX.length).assertEqual(3);
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

    it('keysAreUniqueAndExpected', 0, () => {
      const seen: string[] = [];
      for (let i: number = 0; i < MONSTER_CODEX.length; i++) {
        const k: string = MONSTER_CODEX[i].key;
        expect(seen.includes(k)).assertFalse();
        seen.push(k);
      }
      expect(seen.includes('slime')).assertTrue();
      expect(seen.includes('zombie')).assertTrue();
      expect(seen.includes('dragon')).assertTrue();
    });

    it('namesAreUnique', 0, () => {
      const seen: string[] = [];
      for (let i: number = 0; i < MONSTER_CODEX.length; i++) {
        const n: string = MONSTER_CODEX[i].nameEn;
        expect(seen.includes(n)).assertFalse();
        seen.push(n);
      }
    });

    it('descriptionLengthsWithinBounds', 0, () => {
      for (let i: number = 0; i < MONSTER_CODEX.length; i++) {
        const len: number = MONSTER_CODEX[i].descriptionZh.length;
        expect(len >= 40).assertTrue();
        expect(len <= 200).assertTrue();
      }
    });

    it('assetsMatchCharacterAssetForKind', 0, () => {
      const slime: CodexEntry = MONSTER_CODEX[0];
      const zombie: CodexEntry = MONSTER_CODEX[1];
      const dragon: CodexEntry = MONSTER_CODEX[2];
      expect(slime.assetPath).assertEqual(characterAssetForKind(MonsterKind.Normal));
      expect(zombie.assetPath).assertEqual(characterAssetForKind(MonsterKind.Spelling));
      expect(dragon.assetPath).assertEqual(characterAssetForKind(MonsterKind.Elite));
    });
  });
}
