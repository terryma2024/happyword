import { describe, it, expect } from '@ohos/hypium';
import { CodexEntry, MONSTER_CODEX } from '../main/ets/data/MonsterCodex';
import { MonsterKind } from '../main/ets/data/MonsterCatalog';
import { characterAssetForKind } from '../main/ets/data/CharacterAssets';

const EXPECTED_ARCHETYPE_KEYS: string[] = ['slime', 'zombie', 'dragon'];
const EXPECTED_BOSS_KEYS: string[] = [
  'pumpkin-king',
  'imp-king',
  'phoenix',
  'witch',
  'snow-queen',
  'unicorn',
  'kraken',
];
const EXPECTED_ASSET_ORDER: string[] = [
  'character/slime.svg',
  'character/zombie.svg',
  'character/dragon.svg',
  'character/pumpkin-king.svg',
  'character/imp-king.svg',
  'character/phoenix.svg',
  'character/witch.svg',
  'character/snow-queen.svg',
  'character/unicorn.svg',
  'character/kraken.svg',
];

export default function monsterCodexTests() {
  describe('MonsterCodex', () => {
    it('hasExactlyTenEntries', 0, () => {
      expect(MONSTER_CODEX.length).assertEqual(10);
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

    it('keysAreUniqueAndIncludeAllArchetypeAndBossKeys', 0, () => {
      const seen: string[] = [];
      for (let i: number = 0; i < MONSTER_CODEX.length; i++) {
        const k: string = MONSTER_CODEX[i].key;
        expect(seen.includes(k)).assertFalse();
        seen.push(k);
      }
      for (let i: number = 0; i < EXPECTED_ARCHETYPE_KEYS.length; i++) {
        expect(seen.includes(EXPECTED_ARCHETYPE_KEYS[i])).assertTrue();
      }
      for (let i: number = 0; i < EXPECTED_BOSS_KEYS.length; i++) {
        expect(seen.includes(EXPECTED_BOSS_KEYS[i])).assertTrue();
      }
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

    it('archetypeAssetsMatchCharacterAssetForKind', 0, () => {
      const slime: CodexEntry = MONSTER_CODEX[0];
      const zombie: CodexEntry = MONSTER_CODEX[1];
      const dragon: CodexEntry = MONSTER_CODEX[2];
      expect(slime.assetPath).assertEqual(characterAssetForKind(MonsterKind.Normal));
      expect(zombie.assetPath).assertEqual(characterAssetForKind(MonsterKind.Spelling));
      expect(dragon.assetPath).assertEqual(characterAssetForKind(MonsterKind.Elite));
    });

    it('codexOrderMatchesRegionAppearance', 0, () => {
      expect(MONSTER_CODEX.length).assertEqual(EXPECTED_ASSET_ORDER.length);
      for (let i: number = 0; i < EXPECTED_ASSET_ORDER.length; i++) {
        expect(MONSTER_CODEX[i].assetPath).assertEqual(EXPECTED_ASSET_ORDER[i]);
      }
    });

    it('allAssetPathsAreUnique', 0, () => {
      const seen: Set<string> = new Set<string>();
      for (let i: number = 0; i < MONSTER_CODEX.length; i++) {
        const p: string = MONSTER_CODEX[i].assetPath;
        expect(seen.has(p)).assertFalse();
        seen.add(p);
      }
    });

    it('bossEntriesHaveChineseLabel', 0, () => {
      for (let i: number = 0; i < EXPECTED_BOSS_KEYS.length; i++) {
        const wantedKey: string = EXPECTED_BOSS_KEYS[i];
        let found: boolean = false;
        for (let j: number = 0; j < MONSTER_CODEX.length; j++) {
          if (MONSTER_CODEX[j].key === wantedKey) {
            found = true;
            const label: string = MONSTER_CODEX[j].kindLabelZh;
            expect(label.length > 0).assertTrue();
            // Boss labels are flavour subtitles ("夜空魔法师"), not the
            // role-based archetype labels — they MUST NOT collide with
            // the three archetype labels.
            expect(label === '普通怪物').assertFalse();
            expect(label === '拼写专家').assertFalse();
            expect(label === '精英挑战者').assertFalse();
            break;
          }
        }
        expect(found).assertTrue();
      }
    });
  });
}
