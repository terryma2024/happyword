import { describe, it, expect } from '@ohos/hypium';
import { MonsterEntry, MonsterKind, getMonsterByIndex, MONSTER_CATALOG } from '../main/ets/data/MonsterCatalog';

/**
 * Pure-data unit tests for the monster catalog.
 *
 * These pin the spec's invariants so future edits to the catalog
 * (adding a monster, swapping a color) keep the roster well-formed:
 *   - At least MONSTER_COUNT_MAX entries (cap is currently 10).
 *   - Names are unique.
 *   - Fills and strokes are unique within their channel.
 *   - No catalog color falls in the mage's purple hue band
 *     [240 deg, 300 deg], so children always see the monster as
 *     visually distinct from the wizard.
 *   - getMonsterByIndex is 1-based and mod-wraps on overflow so a
 *     future MONSTER_COUNT_MAX above 10 cannot crash a battle.
 */

const MONSTER_COUNT_CAP: number = 10;

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
    it('hasAtLeastMonsterCountCapEntries', 0, () => {
      expect(MONSTER_CATALOG.length >= MONSTER_COUNT_CAP).assertTrue();
    });

    it('allNamesAreUnique', 0, () => {
      const seen: Set<string> = new Set<string>();
      for (let i = 0; i < MONSTER_CATALOG.length; i++) {
        const name: string = MONSTER_CATALOG[i].name;
        expect(seen.has(name)).assertFalse();
        seen.add(name);
      }
    });

    it('allFillsAreUnique', 0, () => {
      const seen: Set<string> = new Set<string>();
      for (let i = 0; i < MONSTER_CATALOG.length; i++) {
        const fill: string = MONSTER_CATALOG[i].fill.toUpperCase();
        expect(seen.has(fill)).assertFalse();
        seen.add(fill);
      }
    });

    it('allStrokesAreUnique', 0, () => {
      const seen: Set<string> = new Set<string>();
      for (let i = 0; i < MONSTER_CATALOG.length; i++) {
        const stroke: string = MONSTER_CATALOG[i].stroke.toUpperCase();
        expect(seen.has(stroke)).assertFalse();
        seen.add(stroke);
      }
    });

    it('noSaturatedColorFallsInMagePurpleHueBand', 0, () => {
      // Mage uses #8E5EC8 (~273 deg) and #4A2577 (~269 deg). The
      // [240, 300] band covers both with margin so any future palette
      // tweak that drifts toward purple is rejected.
      //
      // Achromatic exception: colors with saturation < 0.10 (near-grey)
      // are visually neutral regardless of where the hex math places
      // their hue. Ash Imp (#6E6E73 / #2C2C2E) has the channel order
      // B>R=G which mathematically lands hue at exactly 240 deg, but
      // the saturation is ~2% so a child reads it as smoky grey, not
      // purple. Skip the hue check for these.
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

    it('getMonsterByIndexReturnsLavaImpForOne', 0, () => {
      const m: MonsterEntry = getMonsterByIndex(1);
      expect(m.name).assertEqual('Lava Imp');
    });

    it('getMonsterByIndexReturnsFrostWispForTwo', 0, () => {
      const m: MonsterEntry = getMonsterByIndex(2);
      expect(m.name).assertEqual('Frost Wisp');
    });

    it('getMonsterByIndexModWrapsAtElevenToFirstEntry', 0, () => {
      const first: MonsterEntry = getMonsterByIndex(1);
      const wrapped: MonsterEntry = getMonsterByIndex(11);
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
    it('defaultsEveryEntryToNormal', 0, () => {
      for (let i = 0; i < MONSTER_CATALOG.length; i++) {
        expect(MONSTER_CATALOG[i].kind).assertEqual(MonsterKind.Normal);
      }
    });
    it('exposesAllFiveKindsViaEnum', 0, () => {
      // Pin the enum surface so PlanQuestionSource and AdventureCatalog
      // can rely on the five labels.
      expect(MonsterKind.Normal).assertEqual('normal');
      expect(MonsterKind.Spelling).assertEqual('spelling');
      expect(MonsterKind.Review).assertEqual('review');
      expect(MonsterKind.Elite).assertEqual('elite');
      expect(MonsterKind.Boss).assertEqual('boss');
    });
  });
}
