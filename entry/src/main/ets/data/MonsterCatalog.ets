/**
 * MonsterCatalog: a frozen, 1-based roster of monsters fought in
 * BattlePage. The single `MONSTER_CATALOG` array is the source of
 * truth — UI code reaches it via `getMonsterByIndex`.
 *
 * Spec: docs/superpowers/specs/2026-04-25-monster-roster-design.md
 *
 * Invariants (pinned in MonsterCatalog.test.ets):
 *   - All names are unique English strings.
 *   - All fills are unique #RRGGBB values; same for strokes.
 *   - No fill or stroke falls in HSL hue band [240, 300] (mage purple).
 *   - getMonsterByIndex(1) === MONSTER_CATALOG[0] (Lava Imp).
 *   - getMonsterByIndex(idx) mod-wraps on idx > length so a future
 *     MONSTER_COUNT_MAX above 10 cannot crash mid-battle.
 */
/**
 * V0.3 monster archetypes — fed into AdventureRegion.monsterPlan to
 * decide what kind of question (Choice, FillLetter, …) the player
 * faces on each slot. Default is `Normal` so V0.2 catalog entries
 * keep their existing behaviour.
 */
export enum MonsterKind {
  Normal = 'normal',
  Spelling = 'spelling',
  Review = 'review',
  Elite = 'elite',
  Boss = 'boss',
}

export class MonsterEntry {
  name: string = '';
  fill: string = '';
  stroke: string = '';
  kind: MonsterKind = MonsterKind.Normal;
}

function makeEntry(name: string, fill: string, stroke: string): MonsterEntry {
  const e: MonsterEntry = new MonsterEntry();
  e.name = name;
  e.fill = fill;
  e.stroke = stroke;
  return e;
}

/**
 * Factory for AdventureCatalog use: builds a MonsterEntry with an
 * explicit `kind` for region monster plans. Kept separate from
 * makeEntry so the V0.2 roster stays Normal by default.
 */
export function makeMonsterEntryWithKind(
  name: string,
  fill: string,
  stroke: string,
  kind: MonsterKind
): MonsterEntry {
  const e: MonsterEntry = new MonsterEntry();
  e.name = name;
  e.fill = fill;
  e.stroke = stroke;
  e.kind = kind;
  return e;
}

export const MONSTER_CATALOG: MonsterEntry[] = [
  makeEntry('Lava Imp',     '#FF6B3D', '#B43A1A'),
  makeEntry('Frost Wisp',   '#4ECDC4', '#2A9088'),
  makeEntry('Thorn Goblin', '#5C9C3A', '#355E1F'),
  makeEntry('Sand Beetle',  '#D4A055', '#8B6014'),
  makeEntry('Storm Sprite', '#F4D03F', '#B8860B'),
  makeEntry('Coral Slime',  '#FF8C94', '#C25A60'),
  makeEntry('Moss Hopper',  '#8FAF40', '#5C7625'),
  makeEntry('Ash Imp',      '#6E6E73', '#2C2C2E'),
  makeEntry('Sea Drop',     '#45B7D1', '#287590'),
  makeEntry('Ember Tail',   '#E67E22', '#A04500'),
  // V0.3.5: difficulty archetypes used by Today Adventure.
  makeMonsterEntryWithKind('Slime',  '#7BD389', '#3F8C50', MonsterKind.Normal),
  makeMonsterEntryWithKind('Zombie', '#9DAA7A', '#4F5E33', MonsterKind.Spelling),
  makeMonsterEntryWithKind('Dragon', '#E63946', '#7C1A23', MonsterKind.Elite),
];

/**
 * 1-based monster lookup. BattleEngine.state.monsterIndex starts at
 * 1 and increments on each defeat, so this is the natural API.
 *
 * On overflow (idx > MONSTER_CATALOG.length) the index mod-wraps
 * back to entry 0. Mod-wrap is preferred over throwing because a
 * crash mid-battle is the worst possible failure mode for a kid's
 * vocabulary game; visible duplication ("we've seen Lava Imp before")
 * is the kinder fallback.
 *
 * On non-positive idx (idx <= 0) the lookup also returns entry 0;
 * that branch is defensive and not expected from BattleEngine.
 */
export function getMonsterByIndex(index1Based: number): MonsterEntry {
  if (index1Based <= 0) {
    return MONSTER_CATALOG[0];
  }
  const idx0: number = (index1Based - 1) % MONSTER_CATALOG.length;
  return MONSTER_CATALOG[idx0];
}

/**
 * V0.3.5: map MonsterKind to the shared visual archetype catalog index.
 * Indices are 1-based (same convention as getMonsterByIndex).
 */
export function monsterIndexForKind(kind: MonsterKind): number {
  if (kind === MonsterKind.Normal) {
    return 11;
  }
  if (kind === MonsterKind.Spelling || kind === MonsterKind.Review) {
    return 12;
  }
  return 13;
}
