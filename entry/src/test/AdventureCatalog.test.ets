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
    it('shipsFiveRegionsInV046', 0, () => {
      // V0.4.6: 3 → 5 (animal-safari + ocean-realm join the picker).
      expect(ADVENTURE_REGIONS.length).assertEqual(5);
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

    it('getRegionByIdReturnsAnimalSafariRegion', 0, () => {
      const r: AdventureRegion = getRegionById('animal-safari');
      expect(r.displayName).assertEqual('Animal Safari');
      expect(r.themeWordCategories[0]).assertEqual('animal');
      expect(r.bossName).assertEqual('Phoenix Spirit');
    });

    it('getRegionByIdReturnsOceanRealmRegion', 0, () => {
      const r: AdventureRegion = getRegionById('ocean-realm');
      expect(r.displayName).assertEqual('Ocean Realm');
      expect(r.themeWordCategories[0]).assertEqual('ocean');
      expect(r.bossName).assertEqual('Kraken');
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

    it('cottageHostsUnicornAfterV046KrakenMigration', 0, () => {
      // V0.4.6: cottage drops Kraken; only Unicorn (#9) remains.
      const r: AdventureRegion = getRegionById('home-cottage');
      expect(r.bossCandidates.length).assertEqual(1);
      expect(r.bossCandidates[0]).assertEqual(9);
    });

    it('safariHostsPhoenixAndUnicornCandidates', 0, () => {
      const r: AdventureRegion = getRegionById('animal-safari');
      // V0.4.6: borrows Phoenix (#6) and Unicorn (#9) — both
      // fairy-tale creature-themed bosses.
      expect(r.bossCandidates.length).assertEqual(2);
      expect(r.bossCandidates.indexOf(6) >= 0).assertTrue();
      expect(r.bossCandidates.indexOf(9) >= 0).assertTrue();
    });

    it('oceanHostsKrakenSoleBoss', 0, () => {
      const r: AdventureRegion = getRegionById('ocean-realm');
      expect(r.bossCandidates.length).assertEqual(1);
      expect(r.bossCandidates[0]).assertEqual(10);
    });

    it('bossCandidatesUnionCoversFullCatalogPossiblyShared', 0, () => {
      // V0.4.6 relaxes the V0.3.8 uniqueness invariant — multiple
      // regions can share the same boss in their rotation pool
      // (Phoenix appears in fruit-forest AND animal-safari; Unicorn
      // appears in home-cottage AND animal-safari). The remaining
      // contract is "every catalog index 4..10 is reachable from at
      // least one region".
      const seen: Set<number> = new Set<number>();
      for (let i: number = 0; i < ADVENTURE_REGIONS.length; i++) {
        const cands: number[] = ADVENTURE_REGIONS[i].bossCandidates;
        for (let j: number = 0; j < cands.length; j++) {
          seen.add(cands[j]);
        }
      }
      for (let i: number = 4; i <= 10; i++) {
        expect(seen.has(i)).assertTrue();
      }
    });
  });
}
