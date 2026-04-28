import {
  AdventureRegion,
  MonsterPlan,
  MonsterSlot,
} from '../models/AdventureRegion';
import { MonsterKind } from './MonsterCatalog';

function slot(kind: MonsterKind, catalogIndex: number): MonsterSlot {
  const s: MonsterSlot = new MonsterSlot();
  s.kind = kind;
  s.catalogIndex = catalogIndex;
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
    slot(MonsterKind.Normal, 1),
    slot(MonsterKind.Spelling, 2),
    slot(MonsterKind.Review, 3),
    slot(MonsterKind.Elite, 4),
    slot(MonsterKind.Boss, 5),
  ];
  r.monsterPlan = plan;
  return r;
})();

export const ADVENTURE_REGIONS: AdventureRegion[] = [FRUIT_FOREST];

export const DEFAULT_REGION_ID: string = 'fruit-forest';

export function getRegionById(id: string): AdventureRegion {
  for (let i = 0; i < ADVENTURE_REGIONS.length; i++) {
    if (ADVENTURE_REGIONS[i].id === id) {
      return ADVENTURE_REGIONS[i];
    }
  }
  return ADVENTURE_REGIONS[0];
}
