import { describe, it, expect } from '@ohos/hypium';
import {
  ADVENTURE_REGIONS,
  DEFAULT_REGION_ID,
  getRegionById,
} from '../main/ets/data/AdventureCatalog';
import { AdventureRegion, MonsterSlot } from '../main/ets/models/AdventureRegion';
import { MonsterKind, monsterIndexForKind } from '../main/ets/data/MonsterCatalog';

export default function adventureCatalogTest() {
  describe('AdventureCatalog', () => {
    it('shipsThreeRegionsInV035', 0, () => {
      expect(ADVENTURE_REGIONS.length).assertEqual(3);
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

    it('getRegionByIdReturnsNewRegions', 0, () => {
      const school: AdventureRegion = getRegionById('school-castle');
      expect(school.displayName).assertEqual('School Castle');
      expect(school.themeWordCategories[0]).assertEqual('place');
      expect(school.bossName).assertEqual('Clock Wizard');

      const home: AdventureRegion = getRegionById('home-cottage');
      expect(home.displayName).assertEqual('Home Cottage');
      expect(home.themeWordCategories[0]).assertEqual('home');
      expect(home.bossName).assertEqual('Toy Knight');
    });

    it('getRegionByIdFallsBackForUnknown', 0, () => {
      const r: AdventureRegion = getRegionById('does-not-exist');
      expect(r.id).assertEqual('fruit-forest');
    });

    it('eachRegionHasFiveMonsterSlotsEndingInBoss', 0, () => {
      for (let i = 0; i < ADVENTURE_REGIONS.length; i++) {
        const r: AdventureRegion = ADVENTURE_REGIONS[i];
        const slots: MonsterSlot[] = r.monsterPlan.slots;
        expect(slots.length).assertEqual(5);
        expect(slots[4].kind).assertEqual(MonsterKind.Boss);
      }
    });

    it('regionMonsterPlanIncludesSpellingReviewElite', 0, () => {
      for (let i = 0; i < ADVENTURE_REGIONS.length; i++) {
        const slots: MonsterSlot[] = ADVENTURE_REGIONS[i].monsterPlan.slots;
        const kinds: MonsterKind[] = slots.map((s: MonsterSlot): MonsterKind => s.kind);
        expect(kinds.indexOf(MonsterKind.Spelling) >= 0).assertTrue();
        expect(kinds.indexOf(MonsterKind.Review) >= 0).assertTrue();
        expect(kinds.indexOf(MonsterKind.Elite) >= 0).assertTrue();
      }
    });

    it('allSlotsUseMonsterIndexForKind', 0, () => {
      for (let i = 0; i < ADVENTURE_REGIONS.length; i++) {
        const slots: MonsterSlot[] = ADVENTURE_REGIONS[i].monsterPlan.slots;
        for (let j = 0; j < slots.length; j++) {
          expect(slots[j].catalogIndex).assertEqual(monsterIndexForKind(slots[j].kind));
        }
      }
    });
  });

  describe('V0.3.8 region bossCandidates', () => {
    it('forestHostsThreeBossCandidatesForestRange', 0, () => {
      const r: AdventureRegion = getRegionById('fruit-forest');
      expect(r.bossCandidates.length).assertEqual(3);
      // V0.3.8 (post V0.2 retirement): bosses occupy catalog 4..10.
      // Forest owns the first three (Pumpkin King / Imp King / Phoenix).
      for (let i: number = 0; i < r.bossCandidates.length; i++) {
        const v: number = r.bossCandidates[i];
        expect(v >= 4 && v <= 6).assertTrue();
      }
    });

    it('castleHostsTwoBossCandidatesCastleRange', 0, () => {
      const r: AdventureRegion = getRegionById('school-castle');
      expect(r.bossCandidates.length).assertEqual(2);
      // Castle owns Witch / Snow Queen at catalog 7..8.
      for (let i: number = 0; i < r.bossCandidates.length; i++) {
        const v: number = r.bossCandidates[i];
        expect(v >= 7 && v <= 8).assertTrue();
      }
    });

    it('cottageHostsTwoBossCandidatesCottageRange', 0, () => {
      const r: AdventureRegion = getRegionById('home-cottage');
      expect(r.bossCandidates.length).assertEqual(2);
      // Cottage owns Unicorn / Kraken at catalog 9..10.
      for (let i: number = 0; i < r.bossCandidates.length; i++) {
        const v: number = r.bossCandidates[i];
        expect(v >= 9 && v <= 10).assertTrue();
      }
    });

    it('bossCandidatesUnionCoversAllSevenIndicesUniquely', 0, () => {
      const seen: Set<number> = new Set<number>();
      for (let i: number = 0; i < ADVENTURE_REGIONS.length; i++) {
        const cands: number[] = ADVENTURE_REGIONS[i].bossCandidates;
        for (let j: number = 0; j < cands.length; j++) {
          expect(seen.has(cands[j])).assertFalse();
          seen.add(cands[j]);
        }
      }
      expect(seen.size).assertEqual(7);
      for (let i: number = 4; i <= 10; i++) {
        expect(seen.has(i)).assertTrue();
      }
    });
  });
}
