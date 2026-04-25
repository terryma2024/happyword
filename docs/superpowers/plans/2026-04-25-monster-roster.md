# Monster Roster Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the single hard-coded "Word Slime" monster with a curated roster of 10 monsters; each monster has a unique English name and its own theme color rendered into the slime avatar and the backward magic projectile.

**Architecture:** Add a pure-data `MonsterCatalog.ets` exporting a 10-entry frozen list of `MonsterEntry { name, fill, stroke }` and a 1-based `getMonsterByIndex` lookup (mod-wrap on overflow). Thread two new `@Prop` color fields through `CharacterCard` (with defaults equal to today's slime green so other callers are no-ops) and three new optional `@Prop` accent fields through `MagicProjectile` (empty-string sentinels that activate only when `forward === false` and `intensity <= 1`). `BattlePage` deletes the `monsterName` constant, holds an `@State currentMonster: MonsterEntry`, syncs it inside `syncFromState` from `state.monsterIndex`, and threads it into the slime `CharacterCard` and the backward `MagicProjectile`. The forward projectile and combo-burst path are unchanged so per-monster theming never touches the gold spectacle.

**Tech Stack:** HarmonyOS NEXT, ArkTS, ArkUI components (`@Component`, `@Prop`, `@State`, `@Watch`, `@Builder`), `@ohos/hypium` for unit tests, `@kit.TestKit` (`Driver`, `ON`) for UI automation, `hvigorw` build, `codelinter` static analysis, `hdc` device control.

**Spec:** [`docs/superpowers/specs/2026-04-25-monster-roster-design.md`](../specs/2026-04-25-monster-roster-design.md)

---

## File Structure

| File | Responsibility | Status |
|------|----------------|--------|
| `entry/src/main/ets/data/MonsterCatalog.ets` | Frozen 10-entry monster list + `getMonsterByIndex` lookup. Pure data, no ArkUI imports. | Create |
| `entry/src/test/MonsterCatalog.test.ets` | Unit tests for catalog invariants (length, uniqueness, no purple, mod-wrap). | Create |
| `entry/src/test/List.test.ets` | Register `monsterCatalogTest` alongside the existing `localUnitTest`. | Modify |
| `entry/src/main/ets/components/CharacterCard.ets` | Add `bodyFill` / `bodyStroke` `@Prop`s (defaults = current slime green) and use them in `slimeAvatar()`. | Modify |
| `entry/src/main/ets/components/MagicProjectile.ets` | Add `accentCore` / `accentGlow` / `accentRing` `@Prop`s (empty-string default) and override the backward color helpers when set. | Modify |
| `entry/src/main/ets/pages/BattlePage.ets` | Delete `monsterName` constant; add `@State currentMonster`; sync in `syncFromState`; thread name + colors into `CharacterCard` and the backward `MagicProjectile`. | Modify |
| `entry/src/ohosTest/ets/test/MonsterRoster.ui.test.ets` | UI test: first monster reads `Lava Imp`; after defeating it, monster card reads `Frost Wisp`. | Create |
| `entry/src/ohosTest/ets/test/List.test.ets` | Register `monsterRosterUiTest`. | Modify |

Each file has one responsibility. The catalog is data-only so its tests are pure unit tests; the component changes are additive (props with safe defaults) so the existing UI tests keep passing while only the new UI test depends on the wiring in `BattlePage`.

---

## Task 1: MonsterCatalog data and unit tests

Build the data layer first. Pure-data, no ArkUI dependencies — the catalog is standalone and proves invariants before any UI consumes it.

**Files:**
- Create: `entry/src/main/ets/data/MonsterCatalog.ets`
- Create: `entry/src/test/MonsterCatalog.test.ets`
- Modify: `entry/src/test/List.test.ets`

- [ ] **Step 1.1: Write the failing unit tests for `MonsterCatalog`**

Create `entry/src/test/MonsterCatalog.test.ets` with the following content:

```typescript
import { describe, it, expect } from '@ohos/hypium';
import { MonsterEntry, getMonsterByIndex, MONSTER_CATALOG } from '../main/ets/data/MonsterCatalog';

/**
 * Pure-data unit tests for the monster catalog.
 *
 * These pin the spec's invariants so future edits to the catalog
 * (adding a monster, swapping a color) keep the roster well-formed:
 *   - At least MONSTER_COUNT_MAX entries (cap is currently 10).
 *   - Names are unique.
 *   - Fills and strokes are unique within their channel.
 *   - No catalog color falls in the mage's purple hue band
 *     [240 deg, 300 deg], so children always see the monster as
 *     visually distinct from the wizard.
 *   - getMonsterByIndex is 1-based and mod-wraps on overflow so a
 *     future MONSTER_COUNT_MAX above 10 cannot crash a battle.
 */

const MONSTER_COUNT_CAP: number = 10;

class HslColor {
  h: number = 0;
  s: number = 0;
  l: number = 0;
}

function hexToHsl(hex: string): HslColor {
  const r: number = parseInt(hex.substring(1, 3), 16) / 255;
  const g: number = parseInt(hex.substring(3, 5), 16) / 255;
  const b: number = parseInt(hex.substring(5, 7), 16) / 255;
  const max: number = Math.max(r, g, b);
  const min: number = Math.min(r, g, b);
  const l: number = (max + min) / 2;
  let h: number = 0;
  let s: number = 0;
  if (max !== min) {
    const d: number = max - min;
    s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
    if (max === r) {
      h = ((g - b) / d + (g < b ? 6 : 0));
    } else if (max === g) {
      h = ((b - r) / d + 2);
    } else {
      h = ((r - g) / d + 4);
    }
    h = h * 60;
  }
  const out: HslColor = new HslColor();
  out.h = h;
  out.s = s;
  out.l = l;
  return out;
}

export default function monsterCatalogTest() {
  describe('MonsterCatalog', () => {
    it('hasAtLeastMonsterCountCapEntries', 0, () => {
      expect(MONSTER_CATALOG.length >= MONSTER_COUNT_CAP).assertTrue();
    });

    it('allNamesAreUnique', 0, () => {
      const seen: Set<string> = new Set<string>();
      for (let i = 0; i < MONSTER_CATALOG.length; i++) {
        const name: string = MONSTER_CATALOG[i].name;
        expect(seen.has(name)).assertFalse();
        seen.add(name);
      }
    });

    it('allFillsAreUnique', 0, () => {
      const seen: Set<string> = new Set<string>();
      for (let i = 0; i < MONSTER_CATALOG.length; i++) {
        const fill: string = MONSTER_CATALOG[i].fill.toUpperCase();
        expect(seen.has(fill)).assertFalse();
        seen.add(fill);
      }
    });

    it('allStrokesAreUnique', 0, () => {
      const seen: Set<string> = new Set<string>();
      for (let i = 0; i < MONSTER_CATALOG.length; i++) {
        const stroke: string = MONSTER_CATALOG[i].stroke.toUpperCase();
        expect(seen.has(stroke)).assertFalse();
        seen.add(stroke);
      }
    });

    it('noColorFallsInMagePurpleHueBand', 0, () => {
      // Mage uses #8E5EC8 (~273 deg) and #4A2577 (~269 deg). The
      // [240, 300] band covers both with margin so any future palette
      // tweak that drifts toward purple is rejected.
      for (let i = 0; i < MONSTER_CATALOG.length; i++) {
        const fillHsl: HslColor = hexToHsl(MONSTER_CATALOG[i].fill);
        const strokeHsl: HslColor = hexToHsl(MONSTER_CATALOG[i].stroke);
        expect(fillHsl.h < 240 || fillHsl.h > 300).assertTrue();
        expect(strokeHsl.h < 240 || strokeHsl.h > 300).assertTrue();
      }
    });

    it('getMonsterByIndexReturnsLavaImpForOne', 0, () => {
      const m: MonsterEntry = getMonsterByIndex(1);
      expect(m.name).assertEqual('Lava Imp');
    });

    it('getMonsterByIndexReturnsFrostWispForTwo', 0, () => {
      const m: MonsterEntry = getMonsterByIndex(2);
      expect(m.name).assertEqual('Frost Wisp');
    });

    it('getMonsterByIndexModWrapsAtElevenToFirstEntry', 0, () => {
      const first: MonsterEntry = getMonsterByIndex(1);
      const wrapped: MonsterEntry = getMonsterByIndex(11);
      expect(wrapped.name).assertEqual(first.name);
      expect(wrapped.fill).assertEqual(first.fill);
      expect(wrapped.stroke).assertEqual(first.stroke);
    });

    it('getMonsterByIndexClampsZeroAndNegativeToFirstEntry', 0, () => {
      const first: MonsterEntry = getMonsterByIndex(1);
      const zero: MonsterEntry = getMonsterByIndex(0);
      const neg: MonsterEntry = getMonsterByIndex(-3);
      expect(zero.name).assertEqual(first.name);
      expect(neg.name).assertEqual(first.name);
    });
  });
}
```

- [ ] **Step 1.2: Register the new test in `entry/src/test/List.test.ets`**

Replace the entire file with:

```typescript
import localUnitTest from './LocalUnit.test';
import monsterCatalogTest from './MonsterCatalog.test';

export default function testsuite() {
  localUnitTest();
  monsterCatalogTest();
}
```

- [ ] **Step 1.3: Run the unit tests and confirm `MonsterCatalog` tests fail (RED)**

Run: `/bin/bash -c 'cd /Users/bytedance/Projects/happyword && hvigorw -p module=entry@default test'`

Expected: compile fails with a "module `MonsterCatalog` not found" error pointing at `MonsterCatalog.test.ets:2`. This proves the new test is registered and the test runner is reading it. (If hvigor instead reports `oh_modules` missing, run `ohpm install` first per `.cursor/dev-commands.md` §2 pre-flight, then re-run the test command.)

- [ ] **Step 1.4: Create `MonsterCatalog.ets` with the frozen 10-entry roster**

Create `entry/src/main/ets/data/MonsterCatalog.ets`:

```typescript
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
export class MonsterEntry {
  name: string = '';
  fill: string = '';
  stroke: string = '';
}

function makeEntry(name: string, fill: string, stroke: string): MonsterEntry {
  const e: MonsterEntry = new MonsterEntry();
  e.name = name;
  e.fill = fill;
  e.stroke = stroke;
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
```

- [ ] **Step 1.5: Run the unit tests and confirm green**

Run: `/bin/bash -c 'cd /Users/bytedance/Projects/happyword && hvigorw -p module=entry@default test'`

Expected: report shows `MonsterCatalog` describe block executes, all 9 `it` blocks PASS, and the existing `localUnitTest` suites are still passing. Total test count = previous count + 9.

- [ ] **Step 1.6: Commit**

```bash
git add entry/src/main/ets/data/MonsterCatalog.ets entry/src/test/MonsterCatalog.test.ets entry/src/test/List.test.ets
git commit -m "feat(monster-roster): add MonsterCatalog with 10 entries and unit tests"
```

---

## Task 2: Add UI test that pins the monster name pipeline (RED)

Drive the BattlePage integration with the UI test. The test will fail today because the right card still reads `Word Slime`; it will go green when Task 5 wires `currentMonster.name` into `CharacterCard`.

**Files:**
- Create: `entry/src/ohosTest/ets/test/MonsterRoster.ui.test.ets`
- Modify: `entry/src/ohosTest/ets/test/List.test.ets`

- [ ] **Step 2.1: Create `MonsterRoster.ui.test.ets`**

Create `entry/src/ohosTest/ets/test/MonsterRoster.ui.test.ets`:

```typescript
import { describe, it, expect } from '@ohos/hypium';
import { Driver, ON } from '@kit.TestKit';
import {
  launchAppShared,
  clickByIdShared,
  tapCorrectAnswerShared,
  resetToDefaultConfigShared,
} from './RoutingFlow.ui.test';

/**
 * Monster Roster UI test (per-monster name + color overhaul).
 *
 * Locked to the ONE behavioural invariant the UI test layer can read
 * reliably: the monster card's name text. Verifying per-monster
 * colors is left to the unit test (the catalog) and the avatar shape
 * test (manual visual review during build) — UiTest cannot read fill
 * / stroke off rendered shape components, and the catalog test
 * already guarantees the colors are wired into the right entries.
 *
 *   - On entering the battle, the monster card must display
 *     "Lava Imp" (catalog entry 1).
 *   - After defeating the first monster (3 correct answers at default
 *     monsterHp = 3), the monster card must display "Frost Wisp"
 *     (catalog entry 2). This proves syncFromState is updating
 *     currentMonster from state.monsterIndex.
 *
 * Each test starts and ends on HomePage so the hypium runner can
 * execute the suite sequentially without state leaking across `it`
 * blocks. Default config (5 monsters, monsterHp=3, playerHp=5) is
 * reset at the top of each test to keep the 3-correct-tap defeat
 * sequence stable.
 *
 * Runner: shares the 30 s per-test timeout with RoutingFlow — see
 * `.cursor/dev-commands.md` for the canonical invocation.
 */
export default function monsterRosterUiTest() {
  describe('MonsterRosterUiTest', () => {
    /**
     * First monster shown on entering BattlePage must be Lava Imp.
     */
    it('firstMonsterIsLavaImp', 0, async (done: Function) => {
      const driver: Driver = await launchAppShared();

      await driver.assertComponentExist(ON.id('HomeStartButton'));
      await resetToDefaultConfigShared(driver);
      await clickByIdShared(driver, 'HomeStartButton');
      await driver.delayMs(1000);
      await driver.assertComponentExist(ON.id('BattleTitle'));
      await driver.assertComponentExist(ON.id('BattlePrompt'));

      // The mage card always reads "Magician"; the monster card is
      // the only place "Lava Imp" can appear on this screen.
      await driver.assertComponentExist(ON.text('Lava Imp'));

      // Return to HomePage so the suite stays re-runnable.
      await clickByIdShared(driver, 'BattleFinishButton');
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('ResultTitle'));
      await clickByIdShared(driver, 'ResultHomeButton');
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('HomeStartButton'));

      expect(true).assertTrue();
      done();
    });

    /**
     * After defeating the first monster (3 correct answers at default
     * monsterHp = 3), the monster card transitions to Frost Wisp.
     */
    it('secondMonsterIsFrostWispAfterFirstDefeat', 0, async (done: Function) => {
      const driver: Driver = await launchAppShared();

      await driver.assertComponentExist(ON.id('HomeStartButton'));
      await resetToDefaultConfigShared(driver);
      await clickByIdShared(driver, 'HomeStartButton');
      await driver.delayMs(1000);
      await driver.assertComponentExist(ON.id('BattleTitle'));
      await driver.assertComponentExist(ON.id('BattlePrompt'));

      // Pre-tap baseline: monster #1 is Lava Imp.
      await driver.assertComponentExist(ON.text('Lava Imp'));

      // Defeat Lava Imp: 3 correct answers at default monsterHp = 3.
      // Each correct tap fires a forward projectile, takes ~320 ms
      // for the impact + ~650 ms feedback window before the next
      // question is rendered. 1100 ms cushion per tap is what
      // CritSpectacle.ui.test uses.
      for (let i = 0; i < 3; i++) {
        await tapCorrectAnswerShared(driver);
        await driver.delayMs(1100);
      }

      // Monster card has now transitioned to monster #2.
      await driver.assertComponentExist(ON.text('Frost Wisp'));

      // Return to HomePage so the suite stays re-runnable.
      await clickByIdShared(driver, 'BattleFinishButton');
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('ResultTitle'));
      await clickByIdShared(driver, 'ResultHomeButton');
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('HomeStartButton'));

      expect(true).assertTrue();
      done();
    });
  });
}
```

- [ ] **Step 2.2: Register the new UI suite in `entry/src/ohosTest/ets/test/List.test.ets`**

Replace the entire file with:

```typescript
import routingFlowUiTest from './RoutingFlow.ui.test';
import critSpectacleUiTest from './CritSpectacle.ui.test';
import speakerButtonUiTest from './SpeakerButton.ui.test';
import reviewModeUiTest from './ReviewMode.ui.test';
import magicAttackUiTest from './MagicAttack.ui.test';
import monsterRosterUiTest from './MonsterRoster.ui.test';

export default function testsuite() {
  routingFlowUiTest();
  critSpectacleUiTest();
  speakerButtonUiTest();
  reviewModeUiTest();
  magicAttackUiTest();
  monsterRosterUiTest();
}
```

- [ ] **Step 2.3: Build the HAP and confirm it compiles**

The new UI test must compile cleanly even though it is expected to fail at runtime. Run: `/bin/bash -c 'cd /Users/bytedance/Projects/happyword && hvigorw assembleHap'`

Expected: build succeeds, debug HAP and ohosTest HAP both produced. (Runtime RED is verified later in Step 6.4 once we run the full UI test suite.)

- [ ] **Step 2.4: Commit (RED — the new test will fail at runtime until Task 5)**

```bash
git add entry/src/ohosTest/ets/test/MonsterRoster.ui.test.ets entry/src/ohosTest/ets/test/List.test.ets
git commit -m "test(monster-roster): add UI test for per-monster name on BattlePage"
```

---

## Task 3: CharacterCard accepts `bodyFill` and `bodyStroke` `@Prop`s

Pure additive refactor. Defaults match today's hex literals so the existing app behavior — and every existing UI test — is unchanged.

**Files:**
- Modify: `entry/src/main/ets/components/CharacterCard.ets:38-46` (insert two `@Prop`s with the existing color literals as defaults)
- Modify: `entry/src/main/ets/components/CharacterCard.ets:268-271` (use the new props in `slimeAvatar`)

- [ ] **Step 3.1: Insert the two new `@Prop`s after the `sublabel` `@Prop`**

In `entry/src/main/ets/components/CharacterCard.ets`, locate this block (currently around lines 41-46):

```typescript
  @Prop hp: number = 0;
  @Prop maxHp: number = 1;
  // Must be @Prop so updates from the parent (e.g. "Monster 2 / 5" after
  // the first monster is defeated) actually invalidate this component. A
  // plain property would be captured at construction and stay stale.
  @Prop sublabel: string = '';
```

Replace it with:

```typescript
  @Prop hp: number = 0;
  @Prop maxHp: number = 1;
  // Must be @Prop so updates from the parent (e.g. "Monster 2 / 5" after
  // the first monster is defeated) actually invalidate this component. A
  // plain property would be captured at construction and stay stale.
  @Prop sublabel: string = '';

  // Per-monster theming colors used by slimeAvatar(). Defaults equal
  // the hex literals slimeAvatar painted before this prop existed, so
  // any caller that doesn't pass them gets the V0.2 slime green look
  // (mageAvatar never reads these — they're scoped to the slime body).
  @Prop bodyFill: string = '#4ECB71';
  @Prop bodyStroke: string = '#2E8B57';
```

- [ ] **Step 3.2: Use the new props in `slimeAvatar()`**

In the same file, locate the `slimeAvatar()` body (currently around lines 266-274):

```typescript
    Column() {
      Stack() {
        Ellipse({ width: 80, height: 72 })
          .fill('#4ECB71')
          .stroke('#2E8B57')
          .strokeWidth(2);
        Rect({ width: 84, height: 36 })
          .fill(this.backgroundForKind())
          .offset({ y: 20 });
```

Replace with:

```typescript
    Column() {
      Stack() {
        Ellipse({ width: 80, height: 72 })
          .fill(this.bodyFill)
          .stroke(this.bodyStroke)
          .strokeWidth(2);
        Rect({ width: 84, height: 36 })
          .fill(this.backgroundForKind())
          .offset({ y: 20 });
```

The `Rect` mask keeps using `this.backgroundForKind()` (the card pastel background, not the monster fill) so the dome silhouette is preserved exactly as today.

- [ ] **Step 3.3: Build and confirm compile is clean**

Run: `/bin/bash -c 'cd /Users/bytedance/Projects/happyword && hvigorw assembleHap'`

Expected: build succeeds. Existing callers (`BattlePage.ets:830-840` for the slime, every mage call site) compile unchanged because the new props have defaults.

- [ ] **Step 3.4: Run codelinter**

Run: `/bin/bash -c 'cd /Users/bytedance/Projects/happyword && codelinter -c ./code-linter.json5 .'`

Expected: exit 0, no new errors introduced. (If codelinter flags `@performance/avoid-overusing-custom-component-check` on `CharacterCard`, treat it as out of scope — the existing component already declared its shape and we are not splitting it.)

- [ ] **Step 3.5: Commit**

```bash
git add entry/src/main/ets/components/CharacterCard.ets
git commit -m "refactor(character-card): accept bodyFill/bodyStroke props with default slime colors"
```

---

## Task 4: MagicProjectile accepts `accentCore`, `accentGlow`, `accentRing` `@Prop`s

Additive refactor mirroring Task 3. The accents activate only on the backward (monster -> mage) projectile and only when `intensity <= 1`, so the forward path and combo-burst gold path are unchanged.

**Files:**
- Modify: `entry/src/main/ets/components/MagicProjectile.ets:35-39` (append three `@Prop`s after the existing ones)
- Modify: `entry/src/main/ets/components/MagicProjectile.ets:131-152` (override the three color helpers when accents are non-empty)

- [ ] **Step 4.1: Add the three accent `@Prop`s**

In `entry/src/main/ets/components/MagicProjectile.ets`, locate (currently lines 32-45):

```typescript
@Component
export struct MagicProjectile {
  /** Monotonically-increasing trigger. BattlePage bumps it per shot. */
  @Prop @Watch('onPulseChanged') projectilePulse: number = 0;
  /** true: fire from mage (left) toward monster (right). */
  @Prop forward: boolean = true;
  /** 1 = normal shot, 2 = combo-burst shot (gold, bigger). */
  @Prop intensity: number = 1;

  @State private translateX: number = 0;
  @State private coreOpacity: number = 0;
  @State private coreScale: number = 0.4;
  @State private outerOpacity: number = 0;
  @State private outerScale: number = 0.5;
```

Replace with:

```typescript
@Component
export struct MagicProjectile {
  /** Monotonically-increasing trigger. BattlePage bumps it per shot. */
  @Prop @Watch('onPulseChanged') projectilePulse: number = 0;
  /** true: fire from mage (left) toward monster (right). */
  @Prop forward: boolean = true;
  /** 1 = normal shot, 2 = combo-burst shot (gold, bigger). */
  @Prop intensity: number = 1;

  // Per-monster theme colors for the BACKWARD shot (monster -> mage).
  // Empty string is the "not set" sentinel; non-empty overrides the
  // backward defaults inside coreColor / glowColor / ringColor when
  // intensity <= 1. The forward path and combo-burst path always
  // win, so per-monster theming never affects the gold spectacle.
  // Empty-string defaults are preferred over `string | undefined`
  // because @Prop primitives default cleanly without a guard.
  @Prop accentCore: string = '';
  @Prop accentGlow: string = '';
  @Prop accentRing: string = '';

  @State private translateX: number = 0;
  @State private coreOpacity: number = 0;
  @State private coreScale: number = 0.4;
  @State private outerOpacity: number = 0;
  @State private outerScale: number = 0.5;
```

- [ ] **Step 4.2: Override the backward color helpers when accents are non-empty**

In the same file, locate the three color helpers (currently lines 130-152):

```typescript
  /** Outer glow halo colour. */
  private glowColor(): string {
    if (this.intensity > 1) {
      return '#FFE56F';
    }
    return this.forward ? '#C5DBFF' : '#FFCBCB';
  }

  /** Bright projectile core colour. */
  private coreColor(): string {
    if (this.intensity > 1) {
      return '#FFD93D';
    }
    return this.forward ? '#7BA9FF' : '#FF6B6B';
  }

  /** Solid ring stroke for the core, keeps the orb readable in flight. */
  private ringColor(): string {
    if (this.intensity > 1) {
      return '#FF8A1E';
    }
    return this.forward ? '#3D6FD0' : '#B23A3A';
  }
```

Replace with:

```typescript
  /** Outer glow halo colour. */
  private glowColor(): string {
    if (this.intensity > 1) {
      return '#FFE56F';
    }
    if (!this.forward && this.accentGlow.length > 0) {
      return this.accentGlow;
    }
    return this.forward ? '#C5DBFF' : '#FFCBCB';
  }

  /** Bright projectile core colour. */
  private coreColor(): string {
    if (this.intensity > 1) {
      return '#FFD93D';
    }
    if (!this.forward && this.accentCore.length > 0) {
      return this.accentCore;
    }
    return this.forward ? '#7BA9FF' : '#FF6B6B';
  }

  /** Solid ring stroke for the core, keeps the orb readable in flight. */
  private ringColor(): string {
    if (this.intensity > 1) {
      return '#FF8A1E';
    }
    if (!this.forward && this.accentRing.length > 0) {
      return this.accentRing;
    }
    return this.forward ? '#3D6FD0' : '#B23A3A';
  }
```

The crit-gold branch (`intensity > 1`) is checked first in every helper so the combo spectacle is never affected by per-monster theming, and the forward shot ignores accents because `!this.forward` is false.

- [ ] **Step 4.3: Build**

Run: `/bin/bash -c 'cd /Users/bytedance/Projects/happyword && hvigorw assembleHap'`

Expected: build succeeds. Existing call sites in `BattlePage.ets:863-872` compile unchanged because the new props have empty-string defaults.

- [ ] **Step 4.4: Run codelinter**

Run: `/bin/bash -c 'cd /Users/bytedance/Projects/happyword && codelinter -c ./code-linter.json5 .'`

Expected: exit 0, no new findings. The override branches are simple `if` returns and don't trigger the `hp-arkui-use-local-var-to-replace-state-var` rule.

- [ ] **Step 4.5: Commit**

```bash
git add entry/src/main/ets/components/MagicProjectile.ets
git commit -m "refactor(magic-projectile): add accent props for backward-shot per-monster colors"
```

---

## Task 5: Wire `currentMonster` into `BattlePage` (turn the UI test GREEN)

Final integration. This is the step where the RED Task 2 tests turn green: replace the hard-coded monster name with a `@State` that follows `state.monsterIndex` through the catalog, and pass its colors into the slime card and the backward projectile.

**Files:**
- Modify: `entry/src/main/ets/pages/BattlePage.ets:1-30` (add the `MonsterCatalog` import to the existing import block)
- Modify: `entry/src/main/ets/pages/BattlePage.ets:90` (delete the `monsterName` constant)
- Modify: `entry/src/main/ets/pages/BattlePage.ets:130-140` (add the `currentMonster` `@State` next to `monsterIndex`)
- Modify: `entry/src/main/ets/pages/BattlePage.ets:418-425` (sync `currentMonster` inside `syncFromState`)
- Modify: `entry/src/main/ets/pages/BattlePage.ets:830-845` (thread name + colors into the slime `CharacterCard`)
- Modify: `entry/src/main/ets/pages/BattlePage.ets:863-872` (thread accent colors into the backward `MagicProjectile`)

- [ ] **Step 5.1: Import `MonsterCatalog`**

At the top of `entry/src/main/ets/pages/BattlePage.ets`, add the import alongside the existing imports (place it next to other `data/` or `models/` imports — group with the closest in alphabetical order):

```typescript
import { MonsterEntry, getMonsterByIndex } from '../data/MonsterCatalog';
```

- [ ] **Step 5.2: Delete the `monsterName` constant**

Around line 90 of `BattlePage.ets`:

```typescript
  private readonly monsterName: string = 'Word Slime';
```

Delete this entire line (and the trailing newline if it leaves a double blank). The string `'Word Slime'` must no longer appear anywhere in `entry/src/main/ets`.

- [ ] **Step 5.3: Add the `currentMonster` `@State`**

Around line 134 of `BattlePage.ets` (next to `monsterIndex`):

```typescript
  @State monsterIndex: number = 1;
```

Add immediately after it:

```typescript
  // Mirror of MonsterCatalog entry for the monster currently in
  // combat. Updated inside syncFromState whenever monsterIndex
  // changes, then read by the slime CharacterCard (name +
  // bodyFill/bodyStroke) and the backward MagicProjectile (accent
  // colors). Initialised to entry 1 so the first paint of the page
  // before BattleEngine emits its first state still shows Lava Imp.
  @State currentMonster: MonsterEntry = getMonsterByIndex(1);
```

- [ ] **Step 5.4: Sync `currentMonster` in `syncFromState`**

Around line 421 of `BattlePage.ets`, inside `syncFromState`:

```typescript
    this.monsterIndex = state.monsterIndex;
    this.monsterTotal = state.monstersTotal;
```

Replace with:

```typescript
    this.monsterIndex = state.monsterIndex;
    this.monsterTotal = state.monstersTotal;
    // Re-read catalog every sync. getMonsterByIndex is a constant-
    // time array lookup, so the cost is negligible and keeping the
    // assignment unconditional avoids a stale @State if the engine
    // ever resets monsterIndex back to 1 between battles.
    this.currentMonster = getMonsterByIndex(state.monsterIndex);
```

- [ ] **Step 5.5: Thread name + colors into the slime `CharacterCard`**

Around line 832 of `BattlePage.ets`:

```typescript
            CharacterCard({
              kind: CharacterKind.Slime,
              name: this.monsterName,
              hp: this.monsterHp,
              maxHp: this.monsterMaxHp,
              sublabel: `Monster ${this.monsterIndex} / ${this.monsterTotal}`,
              hurtPulse: this.monsterHurtPulse,
              zoomPulse: this.monsterZoomPulse,
            });
```

Replace with:

```typescript
            CharacterCard({
              kind: CharacterKind.Slime,
              name: this.currentMonster.name,
              bodyFill: this.currentMonster.fill,
              bodyStroke: this.currentMonster.stroke,
              hp: this.monsterHp,
              maxHp: this.monsterMaxHp,
              sublabel: `Monster ${this.monsterIndex} / ${this.monsterTotal}`,
              hurtPulse: this.monsterHurtPulse,
              zoomPulse: this.monsterZoomPulse,
            });
```

- [ ] **Step 5.6: Thread accent colors into the backward `MagicProjectile`**

Around line 868 of `BattlePage.ets`:

```typescript
      MagicProjectile({
        projectilePulse: this.projectileBackwardPulse,
        forward: false,
        intensity: 1,
      });
```

Replace with:

```typescript
      MagicProjectile({
        projectilePulse: this.projectileBackwardPulse,
        forward: false,
        intensity: 1,
        accentCore: this.currentMonster.fill,
        // Glow tracks the core fill; outerOpacity 0.65 makes the
        // shared color read as a halo around the core orb.
        accentGlow: this.currentMonster.fill,
        accentRing: this.currentMonster.stroke,
      });
```

The forward `MagicProjectile` (line ~863) stays as-is — never touch the gold combo path with monster theming.

- [ ] **Step 5.7: Build**

Run: `/bin/bash -c 'cd /Users/bytedance/Projects/happyword && hvigorw assembleHap'`

Expected: build succeeds. Both HAPs (debug + ohosTest) are produced.

- [ ] **Step 5.8: Run codelinter**

Run: `/bin/bash -c 'cd /Users/bytedance/Projects/happyword && codelinter -c ./code-linter.json5 .'`

Expected: exit 0. The new state assignment in `syncFromState` is a single straightforward assignment and does not require the `animateTo({ duration: 0 })` wrapper that the magic-attack PR used (no animation start frames here).

- [ ] **Step 5.9: Confirm `'Word Slime'` is gone from main sources**

Run: `/bin/bash -c "rg 'Word Slime' entry/src/main/ets || echo 'no match'"`

Expected: prints `no match`. (The string may still appear in spec docs and old transcripts; only `entry/src/main/ets` matters here.)

- [ ] **Step 5.10: Commit**

```bash
git add entry/src/main/ets/pages/BattlePage.ets
git commit -m "feat(battle-page): wire currentMonster from catalog into card and backward projectile"
```

---

## Task 6: Verify the full pipeline (build + codelinter + unit + UI)

End-to-end verification: pure-data invariants pass, the new UI test goes from RED to GREEN, and every previously-passing UI test still passes.

**Files:** none modified by this task; this is the verification gate.

- [ ] **Step 6.1: Clean assemble**

Run: `/bin/bash -c 'cd /Users/bytedance/Projects/happyword && hvigorw assembleHap'`

Expected: exit 0, both `entry/build/.../entry-default-signed.hap` and the `ohosTest` HAP produced.

- [ ] **Step 6.2: Codelinter (no auto-fix; final verification)**

Run: `/bin/bash -c 'cd /Users/bytedance/Projects/happyword && codelinter -c ./code-linter.json5 .'`

Expected: exit 0, zero errors, zero new warnings on the four files this plan touches (`MonsterCatalog.ets`, `CharacterCard.ets`, `MagicProjectile.ets`, `BattlePage.ets`). If any new warning appears, fix it (the project's policy is zero-warning per the user's earlier directive — see `harmony-codelinter` skill) and amend the relevant Task 3/4/5 commit before continuing.

- [ ] **Step 6.3: Run no-device unit tests**

Run: `/bin/bash -c 'cd /Users/bytedance/Projects/happyword && hvigorw -p module=entry@default test'`

Expected: all `localUnitTest` suites pass, all 9 `MonsterCatalog` `it` blocks pass, total = previous passing count + 9.

- [ ] **Step 6.4: Run UI tests on a connected device or emulator**

Verify a target is connected:

`/bin/bash -c 'hdc list targets'`

Expected: at least one non-empty target line. If empty, start the simulator from DevEco (or follow `harmony-emulator-manage`) and re-check before proceeding.

Uninstall any previous build to avoid the `install sign info inconsistent` error:

`/bin/bash -c 'hdc uninstall com.terryma.wordmagicgame || true'`

Install the freshly built debug HAP and the ohosTest HAP. Use the paths from the build output of Step 6.1; the canonical pair is:

```bash
hdc install entry/build/default/outputs/default/entry-default-signed.hap
hdc install entry/build/default/outputs/ohosTest/entry-ohosTest-signed.hap
```

Run the on-device test runner with the 30s per-test timeout (the new tests do up to 4 seq taps + 800-1100 ms waits each):

`/bin/bash -c 'hdc shell aa test -b com.terryma.wordmagicgame -m entry_test -s unittest OpenHarmonyTestRunner -s timeout 30000 -w 180'`

Expected: `TestFinished-ResultCode: 0` and `OHOS_REPORT_CODE: 0`. The runner output should include both `MonsterRosterUiTest#firstMonsterIsLavaImp` and `MonsterRosterUiTest#secondMonsterIsFrostWispAfterFirstDefeat` reporting PASS, and the existing `RoutingFlowUiTest`, `CritSpectacleUiTest`, `SpeakerButtonUiTest`, `ReviewModeUiTest`, and `MagicAttackUiTest` suites also reporting PASS.

If `secondMonsterIsFrostWispAfterFirstDefeat` times out, capture `hdc hilog` for the bundle (see `harmony-log-analyzer` skill), check that the post-defeat transition delay matches the 1100 ms cushion in the test, and adjust the cushion (or extract a shared helper) before re-running. Do **not** delete the test or weaken the assertion to make it pass.

- [ ] **Step 6.5: Final commit only if Step 6.2 / 6.3 / 6.4 required tweaks**

If Steps 6.2, 6.3, or 6.4 were green on the first try with no source edits, skip this step. Otherwise, amend or stack a follow-up commit with whatever edits were needed (e.g. timing cushion, codelinter cleanup):

```bash
git status
git add <touched files>
git commit -m "chore(monster-roster): final verification fixes"
```

(Use `git commit --amend` only on commits created in this session and never pushed; otherwise stack a new commit.)

---

## Self-Review

**1. Spec coverage:**

| Spec section / requirement | Implemented in |
|----------------------------|---------------|
| `MonsterCatalog.ets` data layer | Task 1.4 |
| 10 hand-curated entries with frozen colors | Task 1.4 |
| `getMonsterByIndex` 1-based + mod-wrap | Task 1.4 |
| Catalog uniqueness invariants | Task 1.1 (tests) |
| No purple in catalog | Task 1.1 (tests) |
| `CharacterCard` `bodyFill` / `bodyStroke` `@Prop`s | Task 3.1 |
| `slimeAvatar()` reads new props | Task 3.2 |
| `MagicProjectile` accent props | Task 4.1 |
| Backward color helpers honour accents | Task 4.2 |
| Crit-gold path unchanged | Task 4.2 (the `intensity > 1` branch is still first) |
| Forward shot unchanged | Task 4.2 (`!this.forward` guards every override) |
| `BattlePage` `currentMonster` `@State` | Task 5.3 |
| `monsterName` constant deleted | Task 5.2 |
| `syncFromState` updates `currentMonster` | Task 5.4 |
| Slime card renders `currentMonster.name` + colors | Task 5.5 |
| Backward projectile renders `currentMonster` accents | Task 5.6 |
| First monster reads `Lava Imp` | Task 2.1 (UI test `firstMonsterIsLavaImp`) |
| Defeated -> next monster reads `Frost Wisp` | Task 2.1 (UI test `secondMonsterIsFrostWispAfterFirstDefeat`) |
| Existing battle / routing / crit / review / magic-attack tests still pass | Task 6.4 |
| Compile / package | Task 6.1 |
| Static analysis | Task 6.2 |

No gaps.

**2. Placeholder scan:** Each task has full code blocks for new content, exact `git add` / `git commit` commands, and exact build / lint / test invocations. No "TBD", no "similar to Task N", no "implement later".

**3. Type consistency:** The catalog uses `MonsterEntry` everywhere; `getMonsterByIndex` is referenced by both the unit test (Task 1.1) and the page integration (Task 5.1, 5.3, 5.4). `MONSTER_CATALOG` is the array name used in the test (Task 1.1) and the data file (Task 1.4). The new `@Prop` names (`bodyFill`, `bodyStroke` in `CharacterCard`; `accentCore`, `accentGlow`, `accentRing` in `MagicProjectile`) are consistent across their declaration tasks (3.1, 4.1) and the consumer wiring (5.5, 5.6). The slime call site passes `bodyFill`/`bodyStroke` and the backward projectile passes `accentCore`/`accentGlow`/`accentRing` — no name drift.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-04-25-monster-roster.md`. Two execution options:

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration. Tasks 1, 3, 4, 5 are independent in scope and ideal for delegation; Task 2 is a one-shot test write; Task 6 is the verification gate I'd run myself.

**2. Inline Execution** — Execute tasks in this session using `executing-plans`, batch execution with checkpoints for review.

Which approach?
