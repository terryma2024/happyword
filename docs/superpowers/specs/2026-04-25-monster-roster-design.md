# Monster Roster — Per-Monster Colors and Names — Design

Date: 2026-04-25
Status: Draft (pending user review)
Scope: HarmonyOS NEXT (ArkTS) — `entry` module only

## Goal

Replace the single hard-coded "Word Slime" monster with a hand-curated roster of 10 monsters. Each monster has a distinct English name and its own theme color, drawn into both the slime avatar on the right `CharacterCard` and the backward magic projectile fired at the mage on a wrong answer. The monster the player is currently fighting is selected by 1-based `BattleEngine.state.monsterIndex`, so monster N of the run is always the same species in the same colors — children can recognize "the third boss is Thorn Goblin".

## Non-goals

- No avatar **shape** variation. Every monster keeps the existing dome+two-eyes slime silhouette in `CharacterCard.slimeAvatar()`. Only `fill` / `stroke` change per monster. Different shapes per species is a much bigger art change and out of scope for this requirement.
- No localized (Chinese) names. Names stay English to match the existing `Magician` label and the project's "play to learn English vocabulary" framing. Q2 was answered as English-only.
- No effect on the **forward** projectile (mage → monster) or the **combo-burst** spectacle. The forward projectile keeps its existing blue palette, and the combo `CritOverlay` shockwave + oversized damage number stay gold regardless of which monster is on screen. Q3 was answered as "avatar + backward projectile only".
- No changes to `BattleEngine` rules, `GameConfig` schema, `MONSTER_COUNT_MIN/MAX`, HP bar rendering, audio cues, or persisted session state.
- No new third-party dependencies, no `oh-package.json5` changes.

## User-facing behavior

1. On entering `BattlePage`, the right card shows monster #1 — `Lava Imp`, painted in red-orange `#FF6B3D` body / `#B43A1A` outline. Sublabel under the name is unchanged: `Monster 1 / N`.
2. Each correct answer that defeats the current monster causes `BattleEngine` to bump `state.monsterIndex` by 1, and the right card transitions to the next species: `Frost Wisp` (#2, cyan) → `Thorn Goblin` (#3, dark green) → ... The transition is the same one-frame swap the existing flow does (no extra fade or slide animation; the `hurtPulse` impact and the index bump still happen on the same tick they always did).
3. Tapping a wrong answer fires a backward magic projectile from the monster card at the mage. The projectile core/glow now use the **current monster's** `fill`, and the ring uses the current monster's `stroke`. So Lava Imp throws an orange/red orb, Frost Wisp throws a cyan orb, etc.
4. The mage card and the forward projectile do not change appearance. The combo-burst gold spectacle does not change appearance.
5. Review mode (`REVIEW_MODE_MONSTERS_TOTAL = 3`) shows the first three roster entries: Lava Imp → Frost Wisp → Thorn Goblin.

## Architecture

### Files touched / added

- **New:** `entry/src/main/ets/data/MonsterCatalog.ets` — exports the `MonsterEntry` class, the immutable 10-entry catalog, and a `getMonsterByIndex(index1Based)` lookup.
- **Modified:** `entry/src/main/ets/components/CharacterCard.ets` — adds two optional `@Prop` color fields and threads them through `slimeAvatar()`.
- **Modified:** `entry/src/main/ets/components/MagicProjectile.ets` — adds three optional `@Prop` accent colors that override the built-in backward defaults when set, and pass through unchanged when empty.
- **Modified:** `entry/src/main/ets/pages/BattlePage.ets` — replaces the hard-coded `private readonly monsterName = 'Word Slime'` with a `@State currentMonster: MonsterEntry` synced from `state.monsterIndex` inside `syncFromState`, and threads its colors into `CharacterCard` + the backward `MagicProjectile`.
- **New:** `entry/src/test/MonsterCatalog.test.ets` — pure-data unit tests for the catalog invariants.
- **New:** `entry/src/ohosTest/ets/test/MonsterRoster.ui.test.ets` — UI automation that the first monster reads `Lava Imp` and the second reads `Frost Wisp` after the first is defeated.
- **Modified:** `entry/src/test/List.test.ets` and `entry/src/ohosTest/ets/test/List.test.ets` — register the two new test files.

### Data: `MonsterCatalog`

```ts
export class MonsterEntry {
  name: string = '';     // English display name, shown on CharacterCard.name line
  fill: string = '';     // Avatar body fill + backward projectile core
  stroke: string = '';   // Avatar body outline + backward projectile ring
}

const CATALOG: MonsterEntry[] = [
  // (Listed in spec order; the Implementation table below freezes the values.)
];

export function getMonsterByIndex(index1Based: number): MonsterEntry {
  // BattleEngine.state.monsterIndex is 1-based and clamped at 1..monstersTotal.
  // monstersTotal is configurable up to MONSTER_COUNT_MAX (= 10), exactly the
  // catalog length, so the modulo is purely defensive — if a future caller
  // raises the cap above 10, monster 11+ recycles from the start of the
  // roster (visible duplication is preferable to an out-of-bounds read).
  const idx0: number = (index1Based - 1) % CATALOG.length;
  return CATALOG[idx0 < 0 ? 0 : idx0];
}
```

The 10 catalog entries (frozen by this spec):

| Idx | name | fill | stroke | Theme |
|-----|------|------|--------|-------|
| 1 | `Lava Imp` | `#FF6B3D` | `#B43A1A` | Red-orange |
| 2 | `Frost Wisp` | `#4ECDC4` | `#2A9088` | Cyan |
| 3 | `Thorn Goblin` | `#5C9C3A` | `#355E1F` | Dark green |
| 4 | `Sand Beetle` | `#D4A055` | `#8B6014` | Sand yellow |
| 5 | `Storm Sprite` | `#F4D03F` | `#B8860B` | Lightning yellow |
| 6 | `Coral Slime` | `#FF8C94` | `#C25A60` | Coral pink |
| 7 | `Moss Hopper` | `#8FAF40` | `#5C7625` | Moss olive |
| 8 | `Ash Imp` | `#6E6E73` | `#2C2C2E` | Smoky grey |
| 9 | `Sea Drop` | `#45B7D1` | `#287590` | Sea blue |
| 10 | `Ember Tail` | `#E67E22` | `#A04500` | Deep orange |

Constraints encoded in the unit test:

- All 10 names are unique.
- All 10 fills are unique; all 10 strokes are unique.
- No saturated `fill` or `stroke` falls in the purple hue band (HSL hue ∈ [240°, 300°]). The mage uses `#8E5EC8` (hue ≈ 273°) and `#4A2577` (hue ≈ 269°), so this exclusion guarantees "怪物的颜色不和魔法师相同" both literally and visually. Achromatic (saturation < 0.10) colors are exempt from the hue check — they read as neutral grey regardless of where the hex math places their hue. Ash Imp's smoky grey (`#6E6E73` / `#2C2C2E`) is the one entry where this matters: B is the max channel by 5/255 so the formula lands hue at 240°, but saturation is ~2% so children see grey, not purple.
- `getMonsterByIndex(1)` returns entry index 0 (Lava Imp); `getMonsterByIndex(11)` also returns entry index 0 (mod wrap is the documented overflow behavior).

### Component: `CharacterCard` — new optional props

```ts
@Prop bodyFill: string = '#4ECB71';     // default = current slime green
@Prop bodyStroke: string = '#2E8B57';   // default = current slime outline
```

The defaults are exactly the colors `slimeAvatar()` paints today, so any caller that doesn't pass the new props gets the V0.2 look. `mageAvatar()` is a separate `@Builder` and never reads these props, so leaving them at the default on the mage card is a no-op (safe dead default — kept rather than forcing every caller to pass values).

`slimeAvatar()` line:

```diff
-  Ellipse({ width: 80, height: 72 })
-    .fill('#4ECB71')
-    .stroke('#2E8B57')
+  Ellipse({ width: 80, height: 72 })
+    .fill(this.bodyFill)
+    .stroke(this.bodyStroke)
```

The `Rect` mask that hides the bottom half of the ellipse keeps reading `this.backgroundForKind()` (the card's own pastel background, **not** the monster fill) so the dome silhouette is preserved exactly as today.

### Component: `MagicProjectile` — new optional props

```ts
@Prop accentCore: string = '';
@Prop accentGlow: string = '';
@Prop accentRing: string = '';
```

The three color helpers gain a single override branch:

```ts
private coreColor(): string {
  if (this.intensity > 1) return '#FFD93D';                  // crit gold — UNCHANGED
  if (!this.forward && this.accentCore.length > 0) return this.accentCore;  // monster tint
  return this.forward ? '#7BA9FF' : '#FF6B6B';               // built-in defaults
}
```

`glowColor()` and `ringColor()` follow the same shape (override only when `forward === false` and the relevant accent is non-empty). The empty-string sentinel is preferable to `string | undefined` because `@Prop` works most cleanly on primitive defaults and ArkTS's optional-prop story is less polished than its default-value story.

The crit-gold branch comes first so `intensity > 1` always wins. This is what preserves the Q3=B promise that the combo spectacle is unaffected by per-monster theming.

### Page: `BattlePage` integration

```ts
import { MonsterEntry, getMonsterByIndex } from '../data/MonsterCatalog';

@State currentMonster: MonsterEntry = getMonsterByIndex(1);
```

Inside `syncFromState(state: BattleState)`:

```ts
this.monsterIndex = state.monsterIndex;
this.monsterTotal = state.monstersTotal;
this.currentMonster = getMonsterByIndex(state.monsterIndex);   // NEW
```

The hard-coded `private readonly monsterName: string = 'Word Slime'` field is deleted. The `CharacterCard(kind=Slime)` call site changes:

```ts
CharacterCard({
  kind: CharacterKind.Slime,
  name: this.currentMonster.name,                  // was: this.monsterName
  bodyFill: this.currentMonster.fill,              // NEW
  bodyStroke: this.currentMonster.stroke,          // NEW
  hp: this.monsterHp,
  maxHp: this.monsterMaxHp,
  sublabel: `Monster ${this.monsterIndex} / ${this.monsterTotal}`,
  hurtPulse: this.monsterHurtPulse,
  // ... (other pulses unchanged)
});
```

The backward `MagicProjectile` call site:

```ts
MagicProjectile({
  projectilePulse: this.projectileBackwardPulse,
  forward: false,
  intensity: 1,
  accentCore: this.currentMonster.fill,            // NEW
  accentGlow: this.currentMonster.fill,            // NEW (intentionally same as core; outerOpacity 0.65 makes it read as a halo)
  accentRing: this.currentMonster.stroke,          // NEW
});
```

The forward `MagicProjectile({ forward: true, ... })` is unchanged. The combo-burst path is unchanged.

`syncFromState` is called from every place the engine updates state today (start of battle, after each `submitAnswer`, on monster transitions), so `currentMonster` stays in lock-step with `monsterIndex` automatically — no extra wiring inside `onOptionTap`.

### Removed code

- `BattlePage.ets:90` `private readonly monsterName: string = 'Word Slime';` — replaced by `currentMonster.name`.
- The string `'Word Slime'` no longer appears anywhere in `entry/src/main/ets`.

## Verification

| Invariant | Where verified |
|-----------|----------------|
| Catalog has ≥ `MONSTER_COUNT_MAX` (= 10) entries | `MonsterCatalog.test.ets` |
| All names unique | `MonsterCatalog.test.ets` |
| All fills unique; all strokes unique | `MonsterCatalog.test.ets` |
| No catalog color in hue band [240°, 300°] (mage purple band) | `MonsterCatalog.test.ets` |
| `getMonsterByIndex(1)` = Lava Imp | `MonsterCatalog.test.ets` |
| `getMonsterByIndex(11)` mod-wraps to Lava Imp | `MonsterCatalog.test.ets` |
| Battle page shows `Lava Imp` on first monster | `MonsterRoster.ui.test.ets` |
| Battle page advances to `Frost Wisp` after first monster defeated | `MonsterRoster.ui.test.ets` |
| Wrong answer still drops player HP (backward projectile pipeline still applies damage when accent props are non-empty) | `MagicAttack.ui.test.ets` (existing) |
| Correct answer still drops monster HP | `MagicAttack.ui.test.ets` (existing) |
| Crit spectacle still ends at `Combo: 0` | `CritSpectacle.ui.test.ets` (existing) |
| Battle → Result → Home routing still works | `RoutingFlow.ui.test.ets` (existing) |
| Compile / package | `hvigorw assembleHap` |
| Static analysis | `codelinter -c ./code-linter.json5 .` → 0 defects |

The two new tests follow the same templates already used in this repo (`LocalUnit.test.ets` for the unit side, `MagicAttack.ui.test.ets` for the UI side), so they don't introduce any new test infrastructure.

## Risks and trade-offs considered

- **Mod-wrap on overflow**: If `MONSTER_COUNT_MAX` is ever raised above 10 without expanding the catalog, monsters 11+ will repeat from the start of the roster. The unit test pins this behavior so future maintainers see it as deliberate (documented "wrap, not crash"). An assertion-style alternative was rejected because it would crash the user's run on a config bug; visible duplication is the kinder failure mode.
- **One slime silhouette for 10 species**: An orange `Lava Imp` rendered in the dome+two-eyes slime body is technically still slime-shaped. We accept this because (a) the user's requirement was explicitly "换颜色" not "换形状", (b) reusing the silhouette keeps the avatar size budget (`AVATAR_HEIGHT = 84vp`) stable, and (c) future shape variants can be added later by widening `MonsterEntry` with optional shape fields without breaking this spec.
- **Empty-string sentinel for accent props**: Using `string = ''` as "not set" trades a tiny bit of clarity for compatibility with ArkTS `@Prop` defaults. An alternative `accentCore?: string` would have to be guarded with `!== undefined` everywhere; the empty-string check is one operator simpler and the prop is private to two adjacent files.
- **Catalog as code rather than JSON**: We could load the catalog from `rawfile/`, but at 10 entries × 3 fields the maintenance overhead of a separate file + parser + IO error path far outweighs the benefit, and code-as-data lets the unit tests typecheck the catalog directly.
- **No transition animation on monster swap**: The right card swaps colors and name in a single render frame at the moment `monsterIndex` increments. We considered a brief cross-fade but rejected it: it would either race with the existing `hurtPulse` squash that fires when the monster is defeated, or push the index bump out by another 100–200 ms, both of which are worse than a clean instant swap.

## Process note

Followed the `using-superpowers` workflow: brainstorming gate first, three clarifying questions answered (Q1=A curated roster, Q2=A English names, Q3=B avatar + backward projectile color), then this design presented in four sections (catalog data, component API, render integration, testing) and approved by the user before this spec was written. Implementation will be driven by the `writing-plans` skill once the user approves this spec file.
