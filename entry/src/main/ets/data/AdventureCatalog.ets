import {
  AdventureRegion,
  MonsterPlan,
  MonsterSlot,
} from '../models/AdventureRegion';
import { MonsterKind, monsterIndexForKind } from './MonsterCatalog';

function slot(kind: MonsterKind): MonsterSlot {
  const s: MonsterSlot = new MonsterSlot();
  s.kind = kind;
  s.catalogIndex = monsterIndexForKind(kind);
  return s;
}

/**
 * Frozen list of regions for V0.3. We currently ship a single
 * fruit-forest region (per V0.3 scope decision: regions and the
 * picker UI ship in V0.3.5). The 5-slot monster plan trades
 * Spelling and Review monsters into the middle, with an Elite at
 * slot 4 and a Boss at slot 5.
 */
const FRUIT_FOREST: AdventureRegion = (() => {
  const r: AdventureRegion = new AdventureRegion();
  r.id = 'fruit-forest';
  r.displayName = 'Fruit Forest';
  r.themeWordCategories = ['fruit'];
  r.bgPrimary = '#FFF6E0';
  r.bgAccent = '#FFD49A';
  r.bossName = 'Orchard Sentinel';
  const plan: MonsterPlan = new MonsterPlan();
  plan.slots = [
    slot(MonsterKind.Normal),
    slot(MonsterKind.Spelling),
    slot(MonsterKind.Review),
    slot(MonsterKind.Elite),
    slot(MonsterKind.Boss),
  ];
  r.monsterPlan = plan;
  // V0.3.8: Forest hosts Pumpkin King / Imp King / Phoenix; rotated
  // per local day by TodayAdventureBuilder.
  r.bossCandidates = [4, 5, 6];
  return r;
})();

const SCHOOL_CASTLE: AdventureRegion = (() => {
  const r: AdventureRegion = new AdventureRegion();
  r.id = 'school-castle';
  r.displayName = 'School Castle';
  r.themeWordCategories = ['place'];
  r.bgPrimary = '#E8F0FE';
  r.bgAccent = '#AECBFA';
  r.bossName = 'Clock Wizard';
  const plan: MonsterPlan = new MonsterPlan();
  plan.slots = [
    slot(MonsterKind.Normal),
    slot(MonsterKind.Spelling),
    slot(MonsterKind.Review),
    slot(MonsterKind.Elite),
    slot(MonsterKind.Boss),
  ];
  r.monsterPlan = plan;
  // V0.3.8: Castle hosts Witch / Snow Queen.
  r.bossCandidates = [7, 8];
  return r;
})();

const HOME_COTTAGE: AdventureRegion = (() => {
  const r: AdventureRegion = new AdventureRegion();
  r.id = 'home-cottage';
  r.displayName = 'Home Cottage';
  r.themeWordCategories = ['home'];
  r.bgPrimary = '#FFF1E6';
  r.bgAccent = '#F4B98A';
  r.bossName = 'Toy Knight';
  const plan: MonsterPlan = new MonsterPlan();
  plan.slots = [
    slot(MonsterKind.Normal),
    slot(MonsterKind.Spelling),
    slot(MonsterKind.Review),
    slot(MonsterKind.Elite),
    slot(MonsterKind.Boss),
  ];
  r.monsterPlan = plan;
  // V0.4.6: cottage drops Kraken; Unicorn is the only candidate now.
  // Kraken migrates to OCEAN_REALM per the V0.3.8 standing promise
  // ("Kraken will migrate to a future ocean region in v0.4").
  r.bossCandidates = [9];
  return r;
})();

const ANIMAL_SAFARI: AdventureRegion = (() => {
  const r: AdventureRegion = new AdventureRegion();
  r.id = 'animal-safari';
  r.displayName = 'Animal Safari';
  r.themeWordCategories = ['animal'];
  // Warm savanna palette so the picker chip + adventure card stand
  // out from the existing fruit / school / home backdrops.
  r.bgPrimary = '#FFF4D9';
  r.bgAccent = '#E0B973';
  r.bossName = 'Phoenix Spirit';
  const plan: MonsterPlan = new MonsterPlan();
  plan.slots = [
    slot(MonsterKind.Normal),
    slot(MonsterKind.Spelling),
    slot(MonsterKind.Review),
    slot(MonsterKind.Elite),
    slot(MonsterKind.Boss),
  ];
  r.monsterPlan = plan;
  // V0.4.6: borrows Phoenix (#6) from the FRUIT_FOREST rotation pool;
  // pairs with Unicorn (#9) which now becomes a multi-region rotation
  // member after the cottage Kraken migration. Boss sharing is
  // legitimate because the rotation key is per-region (regionId +
  // dayKey) — same boss can appear in different regions on different
  // local days without a uniqueness conflict.
  r.bossCandidates = [6, 9];
  return r;
})();

const OCEAN_REALM: AdventureRegion = (() => {
  const r: AdventureRegion = new AdventureRegion();
  r.id = 'ocean-realm';
  r.displayName = 'Ocean Realm';
  r.themeWordCategories = ['ocean'];
  // Cool teal palette to read as deep water.
  r.bgPrimary = '#E0F4F7';
  r.bgAccent = '#7BB6BF';
  r.bossName = 'Kraken';
  const plan: MonsterPlan = new MonsterPlan();
  plan.slots = [
    slot(MonsterKind.Normal),
    slot(MonsterKind.Spelling),
    slot(MonsterKind.Review),
    slot(MonsterKind.Elite),
    slot(MonsterKind.Boss),
  ];
  r.monsterPlan = plan;
  // V0.4.6: Kraken (#10) lands here as its dedicated home. Single-
  // candidate rotation pool means every local day surfaces the same
  // boss; future V0.4.x can add a second oceanic boss to the codex.
  r.bossCandidates = [10];
  return r;
})();

export const ADVENTURE_REGIONS: AdventureRegion[] =
  [FRUIT_FOREST, SCHOOL_CASTLE, HOME_COTTAGE, ANIMAL_SAFARI, OCEAN_REALM];

export const DEFAULT_REGION_ID: string = 'fruit-forest';

export function getRegionById(id: string): AdventureRegion {
  for (let i = 0; i < ADVENTURE_REGIONS.length; i++) {
    if (ADVENTURE_REGIONS[i].id === id) {
      return ADVENTURE_REGIONS[i];
    }
  }
  return ADVENTURE_REGIONS[0];
}
