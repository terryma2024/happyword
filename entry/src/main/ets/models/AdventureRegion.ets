import { MonsterKind } from '../data/MonsterCatalog';

/** One slot in a region's monster plan; references catalog by index. */
export class MonsterSlot {
  kind: MonsterKind = MonsterKind.Normal;
  catalogIndex: number = 0;
}

export class MonsterPlan {
  slots: MonsterSlot[] = [];
}

/**
 * AdventureRegion — V0.3's themed battle environment. Pure data so
 * AdventureCatalog can freeze a list of regions without allocating
 * services. The plan layer (TodayAdventureBuilder) consumes
 * `themeWordCategories` to weight word selection and `monsterPlan`
 * to drive PlanQuestionSource at battle time.
 */
export class AdventureRegion {
  id: string = '';
  displayName: string = '';
  themeWordCategories: string[] = [];
  bgPrimary: string = '#FFFFFF';
  bgAccent: string = '#FFFFFF';
  bossName: string = '';
  monsterPlan: MonsterPlan = new MonsterPlan();
  /**
   * V0.3.8: catalogIndex candidates for the slot-5 boss; empty array
   * keeps the legacy fallback (slot 5 sticks with whatever the
   * monsterPlan template specified, typically `monsterIndexForKind(Boss)`
   * = 13 = Dragon). When non-empty, TodayAdventureBuilder hashes the
   * region id + local day key to deterministically pick one candidate
   * and override the slot-5 catalogIndex.
   */
  bossCandidates: number[] = [];
}

export enum WordSource {
  Review = 'review',
  Learning = 'learning',
  New = 'new',
}

export class WordSlot {
  wordId: string = '';
  source: WordSource = WordSource.New;
}

/**
 * TodaySessionPlan — handed off from HomePage to BattlePage via
 * AppStorage when the player taps the today-adventure card. Only
 * the engine plus PlanQuestionSource read it during a battle.
 */
export class TodaySessionPlan {
  regionId: string = '';
  monsterSlots: MonsterSlot[] = [];
  wordPlan: WordSlot[] = [];
  bossWordIds: string[] = [];
  isFirstToday: boolean = false;
}

export const MONSTER_PLAN_SLOT_COUNT: number = 5;
export const WORD_PLAN_MULTIPLIER: number = 2;
