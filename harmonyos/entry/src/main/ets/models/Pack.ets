import { WordEntry } from './WordEntry';
import { MonsterPlan } from './AdventureRegion';

/**
 * Pack source layer (V0.6.5 three-layer model):
 *   - 'builtin' — bundled rawfile, ships with every install
 *   - 'global'  — server-curated, anonymous read via
 *                 /api/v1/public/global-packs/latest.json
 *   - 'family'  — parent-uploaded, scoped to one family via
 *                 /api/v1/family/{family_id}/family-packs/latest.json
 */
export type PackSource = 'builtin' | 'global' | 'family';

/**
 * SceneMetadata — the visual + monster-plan envelope used by the battle
 * screen. Built-in packs ship with a curated scene; global packs may
 * carry one (admin-authored); family packs default to an empty scene
 * and the client falls back to a deterministic default at battle time
 * (see PackLibrary.fallbackSceneFor).
 */
export class SceneMetadata {
  bgPrimary: string = '#FFFFFF';
  bgAccent: string = '#FFFFFF';
  bossName: string = '';
  monsterPlan: MonsterPlan = new MonsterPlan();
  bossCandidates: number[] = [];
  storyEn?: string;
  storyZh?: string;
  spellbookCoverUrl?: string;
}

/**
 * V0.6.5 — first-class pack object that unifies built-in / global / family
 * data sources under one shape. The home page chip row, ConfigPage picker,
 * BattlePage repo construction and TodayAdventureBuilder all consume Pack.
 */
export class Pack {
  id: string = '';
  name: string = '';
  labelZh: string = '';
  source: PackSource = 'builtin';
  version: number = 0;
  publishedAtMs: number = 0;
  scene: SceneMetadata = new SceneMetadata();
  words: WordEntry[] = [];
}
