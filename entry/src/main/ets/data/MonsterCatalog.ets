/**
 * MonsterCatalog: a frozen, 1-based roster of monsters fought in
 * BattlePage. The single `MONSTER_CATALOG` array is the source of
 * truth — UI code reaches it via `getMonsterByIndex`.
 *
 * Spec: docs/superpowers/specs/2026-04-25-monster-roster-design.md
 *       docs/superpowers/specs/2026-04-29-v0.3.8-boss-codex-expansion-design.md
 *
 * V0.3.8 compact roster (10 entries total):
 *   1. Slime           (archetype, kind=Normal)
 *   2. Zombie          (archetype, kind=Spelling)
 *   3. Dragon          (archetype, kind=Elite)
 *   4. Pumpkin King    (boss, region=Forest)
 *   5. Imp King        (boss, region=Forest)
 *   6. Phoenix         (boss, region=Forest)
 *   7. Witch           (boss, region=Castle)
 *   8. Snow Queen      (boss, region=Castle)
 *   9. Unicorn         (boss, region=Cottage)
 *  10. Kraken          (boss, region=Cottage)
 *
 * Historical note: V0.2 shipped with 10 color-tinted Slime variants
 * (Lava Imp / Frost Wisp / …). V0.3.8 retires them — boss diversity
 * now provides the per-monster visual variety, and the lone slime SVG
 * is sufficient for the Normal archetype.
 *
 * Invariants (pinned in MonsterCatalog.test.ets):
 *   - All names are unique English strings.
 *   - All fills are unique #RRGGBB values; same for strokes.
 *   - No saturated fill or stroke falls in HSL hue band [240, 300]
 *     (mage purple) so children always read the monster as visually
 *     distinct from the wizard.
 *   - getMonsterByIndex(1) === MONSTER_CATALOG[0] (Slime).
 *   - getMonsterByIndex(idx) mod-wraps on idx > length so a future
 *     MONSTER_COUNT_MAX above 10 cannot crash mid-battle.
 */

/**
 * V0.3 monster archetypes — fed into AdventureRegion.monsterPlan to
 * decide what kind of question (Choice, FillLetter, …) the player
 * faces on each slot. Defaults to `Normal`.
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
  assetPath: string = '';
}

/**
 * Factory for AdventureCatalog use: builds a MonsterEntry with an
 * explicit `kind` for region monster plans.
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

/**
 * V0.3.8 factory: builds a MonsterKind.Boss entry that carries its
 * own SVG asset path. Per-entry assetPath wins in BattlePage's
 * `assetPathForEntry` resolver so each region's slot 5 can show a
 * unique boss without expanding MonsterKind.
 */
export function makeBossEntry(
  name: string,
  fill: string,
  stroke: string,
  assetPath: string
): MonsterEntry {
  const e: MonsterEntry = new MonsterEntry();
  e.name = name;
  e.fill = fill;
  e.stroke = stroke;
  e.kind = MonsterKind.Boss;
  e.assetPath = assetPath;
  return e;
}

export const MONSTER_CATALOG: MonsterEntry[] = [
  // V0.3.5: difficulty archetypes used by Today Adventure.
  makeMonsterEntryWithKind('Slime',  '#7BD389', '#3F8C50', MonsterKind.Normal),    // 1
  makeMonsterEntryWithKind('Zombie', '#9DAA7A', '#4F5E33', MonsterKind.Spelling),  // 2
  makeMonsterEntryWithKind('Dragon', '#E63946', '#7C1A23', MonsterKind.Elite),     // 3
  // V0.3.8: per-region boss roster. catalogIndex 4-10 (1-based).
  // Each entry carries its own assetPath; AdventureCatalog assigns
  // these indices to region.bossCandidates so TodayAdventureBuilder
  // can pick one deterministically per day.
  makeBossEntry('Pumpkin King', '#F2812B', '#B5530F', 'character/pumpkin-king.svg'), // 4
  makeBossEntry('Imp King',     '#5C9C3B', '#355E20', 'character/imp-king.svg'),     // 5
  makeBossEntry('Phoenix',      '#F4A261', '#9A4A1F', 'character/phoenix.svg'),      // 6
  makeBossEntry('Witch',        '#2B3470', '#13183A', 'character/witch.svg'),        // 7
  makeBossEntry('Snow Queen',   '#9DC8E2', '#3F6B7F', 'character/snow-queen.svg'),   // 8
  makeBossEntry('Unicorn',      '#F2B5C3', '#9C4F6E', 'character/unicorn.svg'),      // 9
  makeBossEntry('Kraken',       '#1A6E7A', '#0F3B45', 'character/kraken.svg'),       // 10
];

/**
 * 1-based monster lookup. BattleEngine.state.monsterIndex starts at
 * 1 and increments on each defeat, so this is the natural API.
 *
 * On overflow (idx > MONSTER_CATALOG.length) the index mod-wraps
 * back to entry 0. Mod-wrap is preferred over throwing because a
 * crash mid-battle is the worst possible failure mode for a kid's
 * vocabulary game; visible duplication ("we've seen Slime before")
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
 *
 * V0.3.8: re-pinned to the compact catalog (Slime=1, Zombie=2, Dragon=3).
 * Boss falls back to Dragon's archetype index — region-specific bosses
 * override slot 5 via AdventureRegion.bossCandidates + TodayAdventureBuilder
 * rotation, so this fallback only applies to free-play / non-Today modes.
 */
export function monsterIndexForKind(kind: MonsterKind): number {
  if (kind === MonsterKind.Normal) {
    return 1;
  }
  if (kind === MonsterKind.Spelling || kind === MonsterKind.Review) {
    return 2;
  }
  return 3;
}
