import { describe, it, expect } from '@ohos/hypium';
import {
  ADVENTURE_REGIONS,
  DEFAULT_REGION_ID,
  getRegionById,
} from '../main/ets/data/AdventureCatalog';
import { AdventureRegion, MonsterSlot } from '../main/ets/models/AdventureRegion';
import { MonsterKind } from '../main/ets/data/MonsterCatalog';

export default function adventureCatalogTest() {
  describe('AdventureCatalog', () => {
    it('shipsExactlyOneRegionInV03', 0, () => {
      expect(ADVENTURE_REGIONS.length).assertEqual(1);
    });

    it('defaultRegionIdMatchesFirstEntry', 0, () => {
      expect(DEFAULT_REGION_ID).assertEqual(ADVENTURE_REGIONS[0].id);
      expect(DEFAULT_REGION_ID).assertEqual('fruit-forest');
    });

    it('getRegionByIdReturnsKnownRegion', 0, () => {
      const r: AdventureRegion = getRegionById('fruit-forest');
      expect(r.id).assertEqual('fruit-forest');
      expect(r.themeWordCategories[0]).assertEqual('fruit');
    });

    it('getRegionByIdFallsBackForUnknown', 0, () => {
      const r: AdventureRegion = getRegionById('does-not-exist');
      expect(r.id).assertEqual('fruit-forest');
    });

    it('regionHasFiveMonsterSlotsEndingInBoss', 0, () => {
      const r: AdventureRegion = ADVENTURE_REGIONS[0];
      const slots: MonsterSlot[] = r.monsterPlan.slots;
      expect(slots.length).assertEqual(5);
      expect(slots[4].kind).assertEqual(MonsterKind.Boss);
    });

    it('regionMonsterPlanIncludesSpellingAndReview', 0, () => {
      const slots: MonsterSlot[] = ADVENTURE_REGIONS[0].monsterPlan.slots;
      const kinds: MonsterKind[] = slots.map((s: MonsterSlot): MonsterKind => s.kind);
      expect(kinds.indexOf(MonsterKind.Spelling) >= 0).assertTrue();
      expect(kinds.indexOf(MonsterKind.Review) >= 0).assertTrue();
      expect(kinds.indexOf(MonsterKind.Elite) >= 0).assertTrue();
    });
  });
}
