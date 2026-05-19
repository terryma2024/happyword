import { describe, it, expect } from '@ohos/hypium';
import {
  MonsterEntry,
  MonsterKind,
  MonsterLevel,
  getMonsterByIndex,
  MONSTER_CATALOG,
  monsterIndexForKind,
  monsterLevelForCatalogIndex,
} from '../main/ets/data/MonsterCatalog';

const MONSTER_COUNT_CAP: number = 100;
const ORIGINAL_FIRST_TEN: string[] = [
  'Slime',
  'Zombie',
  'Dragon',
  'Pumpkin King',
  'Imp King',
  'Phoenix',
  'Witch',
  'Snow Queen',
  'Unicorn',
  'Kraken',
];

class HslColor {
  h: number = 0;
  s: number = 0;
  l: number = 0;
}

function hexToHsl(hex: string): HslColor {
  const r: number = parseInt(hex.substring(1, 3), 16) / 255;
  const g: number = parseInt(hex.substring(3, 5), 16) / 255;
  const b: number = parseInt(hex.substring(5, 7), 16) / 255;
  const max: number = Math.max(r, g, b);
  const min: number = Math.min(r, g, b);
  const l: number = (max + min) / 2;
  let h: number = 0;
  let s: number = 0;
  if (max !== min) {
    const d: number = max - min;
    s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
    if (max === r) {
      h = ((g - b) / d + (g < b ? 6 : 0));
    } else if (max === g) {
      h = ((b - r) / d + 2);
    } else {
      h = ((r - g) / d + 4);
    }
    h = h * 60;
  }
  const out: HslColor = new HslColor();
  out.h = h;
  out.s = s;
  out.l = l;
  return out;
}

export default function monsterCatalogTest() {
  describe('MonsterCatalog', () => {
    it('hasExactlyMonsterCountCapEntries', 0, () => {
      expect(MONSTER_CATALOG.length).assertEqual(MONSTER_COUNT_CAP);
    });

    it('keepsOriginalFirstTenNames', 0, () => {
      for (let i: number = 0; i < ORIGINAL_FIRST_TEN.length; i++) {
        expect(getMonsterByIndex(i + 1).name).assertEqual(ORIGINAL_FIRST_TEN[i]);
      }
    });

    it('allNamesAreUnique', 0, () => {
      const seen: Set<string> = new Set<string>();
      for (let i: number = 0; i < MONSTER_CATALOG.length; i++) {
        const name: string = MONSTER_CATALOG[i].name;
        expect(seen.has(name)).assertFalse();
        seen.add(name);
      }
    });

    it('allFillsAndStrokesAreUnique', 0, () => {
      const seen: Set<string> = new Set<string>();
      for (let i: number = 0; i < MONSTER_CATALOG.length; i++) {
        const fill: string = MONSTER_CATALOG[i].fill.toUpperCase();
        const stroke: string = MONSTER_CATALOG[i].stroke.toUpperCase();
        expect(seen.has(fill)).assertFalse();
        seen.add(fill);
        expect(seen.has(stroke)).assertFalse();
        seen.add(stroke);
      }
    });

    it('noSaturatedColorFallsInMagePurpleHueBand', 0, () => {
      const SATURATION_FLOOR: number = 0.10;
      for (let i = 0; i < MONSTER_CATALOG.length; i++) {
        const fillHsl: HslColor = hexToHsl(MONSTER_CATALOG[i].fill);
        const strokeHsl: HslColor = hexToHsl(MONSTER_CATALOG[i].stroke);
        if (fillHsl.s >= SATURATION_FLOOR) {
          expect(fillHsl.h < 240 || fillHsl.h > 300).assertTrue();
        }
        if (strokeHsl.s >= SATURATION_FLOOR) {
          expect(strokeHsl.h < 240 || strokeHsl.h > 300).assertTrue();
        }
      }
    });

    it('getMonsterByIndexReturnsSlimeForOne', 0, () => {
      const m: MonsterEntry = getMonsterByIndex(1);
      expect(m.name).assertEqual('Slime');
    });

    it('getMonsterByIndexReturnsJellyfishForEleven', 0, () => {
      const m: MonsterEntry = getMonsterByIndex(11);
      expect(m.name).assertEqual('Jellyfish');
    });

    it('getMonsterByIndexModWrapsBeyondCatalogToFirstEntry', 0, () => {
      const first: MonsterEntry = getMonsterByIndex(1);
      const wrapped: MonsterEntry = getMonsterByIndex(MONSTER_CATALOG.length + 1);
      expect(wrapped.name).assertEqual(first.name);
      expect(wrapped.fill).assertEqual(first.fill);
      expect(wrapped.stroke).assertEqual(first.stroke);
    });

    it('getMonsterByIndexClampsZeroAndNegativeToFirstEntry', 0, () => {
      const first: MonsterEntry = getMonsterByIndex(1);
      const zero: MonsterEntry = getMonsterByIndex(0);
      const neg: MonsterEntry = getMonsterByIndex(-3);
      expect(zero.name).assertEqual(first.name);
      expect(neg.name).assertEqual(first.name);
    });
  });

  describe('MonsterEntry.kind', () => {
    it('exposesAllFiveKindsViaEnum', 0, () => {
      expect(MonsterKind.Normal).assertEqual('normal');
      expect(MonsterKind.Spelling).assertEqual('spelling');
      expect(MonsterKind.Review).assertEqual('review');
      expect(MonsterKind.Elite).assertEqual('elite');
      expect(MonsterKind.Boss).assertEqual('boss');
    });
  });

  describe('Archetype entries + mapping', () => {
    it('addsSlimeZombieDragonAtExpectedIndices', 0, () => {
      expect(getMonsterByIndex(1).name).assertEqual('Slime');
      expect(getMonsterByIndex(2).name).assertEqual('Zombie');
      expect(getMonsterByIndex(3).name).assertEqual('Dragon');
    });

    it('monsterIndexForKindMapsDifficultyToLevelRepresentatives', 0, () => {
      expect(monsterIndexForKind(MonsterKind.Normal)).assertEqual(1);
      expect(monsterIndexForKind(MonsterKind.Spelling)).assertEqual(2);
      expect(monsterIndexForKind(MonsterKind.Review)).assertEqual(1);
      expect(monsterIndexForKind(MonsterKind.Elite)).assertEqual(8);
      expect(monsterIndexForKind(MonsterKind.Boss)).assertEqual(10);
    });

    it('archetypeEntriesHaveEmptyAssetPath', 0, () => {
      for (let i: number = 1; i <= 3; i++) {
        expect(getMonsterByIndex(i).assetPath).assertEqual('');
      }
    });
  });

  describe('MonsterLevel (V0.8.3)', () => {
    it('firstTenLevelsMatchDesignTable', 0, () => {
      expect(getMonsterByIndex(1).level).assertEqual(MonsterLevel.Beginner);
      expect(getMonsterByIndex(2).level).assertEqual(MonsterLevel.Intermediate);
      expect(getMonsterByIndex(3).level).assertEqual(MonsterLevel.Intermediate);
      expect(getMonsterByIndex(4).level).assertEqual(MonsterLevel.Intermediate);
      expect(getMonsterByIndex(5).level).assertEqual(MonsterLevel.Intermediate);
      expect(getMonsterByIndex(6).level).assertEqual(MonsterLevel.Intermediate);
      expect(getMonsterByIndex(7).level).assertEqual(MonsterLevel.Intermediate);
      expect(getMonsterByIndex(8).level).assertEqual(MonsterLevel.Advanced);
      expect(getMonsterByIndex(9).level).assertEqual(MonsterLevel.Advanced);
      expect(getMonsterByIndex(10).level).assertEqual(MonsterLevel.Super);
    });

    it('catalogLevelCountsMatchTargetRatio', 0, () => {
      let beginner: number = 0;
      let intermediate: number = 0;
      let advanced: number = 0;
      let superCount: number = 0;
      for (let i: number = 1; i <= MONSTER_CATALOG.length; i++) {
        const level: MonsterLevel = monsterLevelForCatalogIndex(i);
        if (level === MonsterLevel.Beginner) {
          beginner += 1;
        } else if (level === MonsterLevel.Intermediate) {
          intermediate += 1;
        } else if (level === MonsterLevel.Advanced) {
          advanced += 1;
        } else {
          superCount += 1;
        }
      }
      expect(beginner).assertEqual(10);
      expect(intermediate).assertEqual(60);
      expect(advanced).assertEqual(20);
      expect(superCount).assertEqual(10);
    });

    it('bossesAreNotForcedToAdvanced', 0, () => {
      expect(getMonsterByIndex(4).kind).assertEqual(MonsterKind.Boss);
      expect(getMonsterByIndex(4).level).assertEqual(MonsterLevel.Intermediate);
    });
  });

  describe('Expanded boss entries', () => {
    it('bossEntriesAreAllKindBoss', 0, () => {
      for (let i: number = 4; i <= MONSTER_CATALOG.length; i++) {
        expect(getMonsterByIndex(i).kind).assertEqual(MonsterKind.Boss);
      }
    });

    it('bossEntriesHaveNonEmptyAssetPath', 0, () => {
      for (let i: number = 4; i <= MONSTER_CATALOG.length; i++) {
        const m: MonsterEntry = getMonsterByIndex(i);
        expect(m.assetPath.length > 0).assertTrue();
        expect(m.assetPath.indexOf('character/')).assertEqual(0);
        expect(m.assetPath.endsWith('.svg')).assertTrue();
      }
    });

    it('bossAssetPathsAreUniqueAndDistinctFromArchetypeFallbacks', 0, () => {
      const seen: Set<string> = new Set<string>();
      for (let i: number = 4; i <= MONSTER_CATALOG.length; i++) {
        const p: string = getMonsterByIndex(i).assetPath;
        expect(seen.has(p)).assertFalse();
        seen.add(p);
      }
      expect(seen.has('character/slime.svg')).assertFalse();
      expect(seen.has('character/zombie.svg')).assertFalse();
      expect(seen.has('character/dragon.svg')).assertFalse();
    });
  });
}
