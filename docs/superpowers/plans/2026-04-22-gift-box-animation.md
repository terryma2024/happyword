# Gift Box Open Animation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a gift-box open animation above the existing "点击我" button on the Index page: tapping the button pops the lid off, bursts ~10 colored ribbons radially, and auto-closes the box 1.5s later.

**Architecture:** One new self-contained ArkTS component `GiftBox` under `entry/src/main/ets/components/`, composed of a parent `GiftBox` struct (owns the box body, lid, trigger-watch, and ribbon list) and a nested `GiftBoxRibbon` struct (each ribbon owns its own per-instance animation state). All visuals are drawn with ArkTS primitives — no new media files. A pure `generateRibbons(count)` helper is exported from the same file and unit-tested.

**Tech Stack:** HarmonyOS NEXT, ArkTS, ArkUI (`@Component`, `@State`, `@Prop`, `@Watch`, `animateTo`), `@ohos/hypium` for tests, `@kit.TestKit` `Driver`/`ON` for UI tests.

**Spec:** [`docs/superpowers/specs/2026-04-22-gift-box-animation-design.md`](../specs/2026-04-22-gift-box-animation-design.md)

---

## File Map

- **Create:** `entry/src/main/ets/components/GiftBox.ets` — exports `class Ribbon`, `generateRibbons(count: number): Ribbon[]`, `RIBBON_COLORS`, `@Component struct GiftBox`, and an internal `@Component struct GiftBoxRibbon`.
- **Modify:** `entry/src/main/ets/pages/Index.ets` — import `GiftBox`, add `@State clickTick`, render `GiftBox` above the button, increment `clickTick` on tap.
- **Modify:** `entry/src/ohosTest/ets/test/IndexPage.ui.test.ets` — extend with three new UI cases for the gift-box lifecycle.
- **Modify:** `entry/src/test/LocalUnit.test.ets` — add a `generateRibbons` test suite.

---

## Design notes locked in here (slight refinements over the spec)

The spec describes `tx`, `ty`, `opacity` as fields on the `Ribbon` class. In this plan those per-ribbon animation values live on the **nested `GiftBoxRibbon` component's `@State`** instead — each ribbon owns and animates its own transform. The exported `Ribbon` data class therefore carries only `id`, `angleDeg`, `color`. This is a cleaner way to get reliable per-item animation under `ForEach` in ArkTS and keeps the spec's public-behavior guarantees intact (same count, same palette, same timings).

The parent `GiftBox` owns:

- `@Prop @Watch('onTriggerChanged') trigger: number` (driven by parent tap-counter)
- `@State isOpen: boolean` — drives lid transform + presence of `GiftBoxOpenMarker`
- `@State boxScale: number` — drives the open-pop bounce
- `@State ribbons: Ribbon[]` — populated on open, cleared at 900 ms
- `private timers: number[]` — every `setTimeout` id, cleared on reset and `aboutToDisappear`

---

## Task 1: Ribbon data class, `generateRibbons` helper, and its unit test

**Files:**
- Create: `entry/src/main/ets/components/GiftBox.ets`
- Modify: `entry/src/test/LocalUnit.test.ets`

This task lays the foundation: a pure helper with no UI dependency, fully unit-tested. We start here because TDD is easiest on pure code, and later tasks will depend on this output.

- [ ] **Step 1: Write the failing unit test**

Replace the body of `entry/src/test/LocalUnit.test.ets` with:

```ts
import { describe, it, expect } from '@ohos/hypium';
import { generateRibbons, Ribbon, RIBBON_COLORS } from '../main/ets/components/GiftBox';

export default function localUnitTest() {
  describe('generateRibbons', () => {
    it('returnsRequestedCount', 0, () => {
      const ribbons: Ribbon[] = generateRibbons(10);
      expect(ribbons.length).assertEqual(10);
    });

    it('assignsUniqueIncrementingIds', 0, () => {
      const ribbons: Ribbon[] = generateRibbons(10);
      for (let i = 0; i < ribbons.length; i++) {
        expect(ribbons[i].id).assertEqual(i);
      }
    });

    it('spreadsAnglesAcrossCircle', 0, () => {
      const ribbons: Ribbon[] = generateRibbons(10);
      // Normalize to [0, 360) and check we cover a wide range.
      const normalized: number[] = ribbons.map((r: Ribbon) => ((r.angleDeg % 360) + 360) % 360);
      const min: number = Math.min.apply(null, normalized);
      const max: number = Math.max.apply(null, normalized);
      expect(max - min >= 270).assertTrue();
    });

    it('colorsOnlyFromPalette', 0, () => {
      const ribbons: Ribbon[] = generateRibbons(10);
      for (let i = 0; i < ribbons.length; i++) {
        expect(RIBBON_COLORS.indexOf(ribbons[i].color) >= 0).assertTrue();
      }
    });

    it('isDeterministic', 0, () => {
      const a: Ribbon[] = generateRibbons(10);
      const b: Ribbon[] = generateRibbons(10);
      for (let i = 0; i < a.length; i++) {
        expect(a[i].angleDeg).assertEqual(b[i].angleDeg);
        expect(a[i].color).assertEqual(b[i].color);
      }
    });

    it('handlesZeroCount', 0, () => {
      const ribbons: Ribbon[] = generateRibbons(0);
      expect(ribbons.length).assertEqual(0);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run from project root:

```bash
hvigorw -p module=entry@default test
```

Expected: FAIL — module `../main/ets/components/GiftBox` cannot be resolved (file does not exist yet).

- [ ] **Step 3: Create `GiftBox.ets` with just the helper (component shell comes in Task 2)**

Create `entry/src/main/ets/components/GiftBox.ets` with:

```ts
export const RIBBON_COLORS: string[] = ['#E63946', '#F4C430', '#457B9D', '#F78DA7'];

export class Ribbon {
  id: number = 0;
  angleDeg: number = 0;
  color: string = '#E63946';
}

/**
 * Deterministic — no Math.random(). Same `count` always produces the same output
 * so that unit tests are stable.
 *
 * Angles are evenly spaced around the circle (i * 360/count) with a small
 * deterministic jitter derived from `i`. Colors cycle through RIBBON_COLORS.
 */
export function generateRibbons(count: number): Ribbon[] {
  const out: Ribbon[] = [];
  if (count <= 0) {
    return out;
  }
  const step: number = 360 / count;
  for (let i = 0; i < count; i++) {
    const jitter: number = ((i * 37) % 21) - 10;
    const r: Ribbon = new Ribbon();
    r.id = i;
    r.angleDeg = i * step + jitter;
    r.color = RIBBON_COLORS[i % RIBBON_COLORS.length];
    out.push(r);
  }
  return out;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
hvigorw -p module=entry@default test
```

Expected: PASS — all six `generateRibbons` cases green. The existing `localUnitTest > assertContain` case has been replaced (we own the file now), so only the `generateRibbons` suite runs.

- [ ] **Step 5: Commit**

```bash
git add entry/src/main/ets/components/GiftBox.ets entry/src/test/LocalUnit.test.ets
git commit -m "feat(giftbox): add Ribbon data class and generateRibbons helper"
```

---

## Task 2: GiftBox component (closed state) + integration into Index

**Files:**
- Modify: `entry/src/main/ets/components/GiftBox.ets`
- Modify: `entry/src/main/ets/pages/Index.ets`
- Modify: `entry/src/ohosTest/ets/test/IndexPage.ui.test.ets`

This task gets the static closed-state gift box on screen, verified via a UI test. No animation, no click wiring yet.

- [ ] **Step 1: Write the failing UI test**

Replace `entry/src/ohosTest/ets/test/IndexPage.ui.test.ets` with:

```ts
import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry, Driver, ON } from '@kit.TestKit';
import { Want } from '@kit.AbilityKit';

const delegator: abilityDelegatorRegistry.AbilityDelegator = abilityDelegatorRegistry.getAbilityDelegator();

function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void) => setTimeout(resolve, ms));
}

async function componentExists(driver: Driver, id: string): Promise<boolean> {
  try {
    const c = await driver.findComponent(ON.id(id));
    return c !== null && c !== undefined;
  } catch (e) {
    return false;
  }
}

async function launchIndex(): Promise<Driver> {
  const bundleName = abilityDelegatorRegistry.getArguments().bundleName;
  const want: Want = { bundleName, abilityName: 'EntryAbility' };
  await delegator.startAbility(want);
  await sleep(1000);
  const driver = Driver.create();
  await driver.delayMs(500);
  return driver;
}

export default function indexPageUiTest(): void {
  describe('IndexPageUiTest', () => {
    it('clickHelloButton_shouldNotBlockUi', 0, async (done: Function) => {
      const driver = await launchIndex();
      await driver.assertComponentExist(ON.id('HelloWorld'));
      await driver.assertComponentExist(ON.id('HelloButton'));

      const button = await driver.findComponent(ON.id('HelloButton'));
      await button.click();
      await driver.delayMs(500);

      const buttonAgain = await driver.findComponent(ON.id('HelloButton'));
      await buttonAgain.click();
      await driver.delayMs(500);

      await driver.assertComponentExist(ON.id('HelloWorld'));
      expect(true).assertTrue();
      done();
    });

    it('giftBox_initiallyClosed', 0, async (done: Function) => {
      const driver = await launchIndex();
      await driver.assertComponentExist(ON.id('GiftBoxContainer'));
      const openMarkerPresent: boolean = await componentExists(driver, 'GiftBoxOpenMarker');
      expect(openMarkerPresent).assertFalse();
      done();
    });
  });
}
```

- [ ] **Step 2: Run the UI test to verify it fails**

Build the HAP, install it, and run on-device tests (requires emulator/device per `.cursor/dev-commands.md` sections 3–4). From project root:

```bash
hvigorw assembleHap
hdc install <path-to-built-debug.hap>
hdc shell aa test -b com.terryma.wordmagicgame -m entry_test -s unittest OpenHarmonyTestRunner -w 120
```

Expected: `giftBox_initiallyClosed` FAILS with `assertComponentExist` timing out — there is no `GiftBoxContainer` on screen yet.

If no device is available, verify via build-only compile check: `hvigorw assembleHap` must still succeed, and you skip the on-device step until a device is up.

- [ ] **Step 3: Add the `GiftBox` component (closed-state visuals) to `GiftBox.ets`**

Append to `entry/src/main/ets/components/GiftBox.ets` (after the existing exports, keep them):

```ts
const BOX_BODY_RED: string = '#E63946';
const BOX_RIBBON_GOLD: string = '#F4C430';

@Component
export struct GiftBox {
  // Parent increments on every tap. Reserved for Task 3.
  @Prop trigger: number = 0;

  build(): void {
    Stack() {
      // Body — rounded rectangle with a vertical gold stripe down its center.
      Stack() {
        Column()
          .width(120)
          .height(80)
          .borderRadius(8)
          .backgroundColor(BOX_BODY_RED);
        Column()
          .width(8)
          .height(80)
          .backgroundColor(BOX_RIBBON_GOLD);
      }
      .width(120)
      .height(80)
      .alignContent(Alignment.Bottom);

      // Lid group — rectangle + bowtie.
      Stack() {
        Column()
          .width(132)
          .height(32)
          .borderRadius(6)
          .backgroundColor(BOX_BODY_RED);
        Row() {
          Column()
            .width(24)
            .height(10)
            .borderRadius(5)
            .backgroundColor(BOX_RIBBON_GOLD)
            .rotate({ angle: 25 });
          Column()
            .width(24)
            .height(10)
            .borderRadius(5)
            .backgroundColor(BOX_RIBBON_GOLD)
            .rotate({ angle: -25 });
        }
        .width(56)
        .justifyContent(FlexAlign.Center);
      }
      .id('GiftBoxLid')
      .width(132)
      .height(32)
      .offset({ x: 0, y: -64 });
    }
    .id('GiftBoxContainer')
    .width(132)
    .height(120);
  }
}
```

- [ ] **Step 4: Integrate `GiftBox` into `Index.ets`**

Modify `entry/src/main/ets/pages/Index.ets`:

Add near the top of the file, after the existing `import { common } from '@kit.AbilityKit';` line:

```ts
import { GiftBox } from '../components/GiftBox';
```

Inside `struct Index`, add a state field below `@State message: string = 'Hello World';`:

```ts
@State private clickTick: number = 0;
```

Inside `build()` → `RelativeContainer()`, add the `GiftBox` call immediately **before** `Button('点击我')`:

```ts
GiftBox({ trigger: this.clickTick })
  .alignRules({
    bottom: { anchor: 'HelloButton', align: VerticalAlign.Top },
    middle: { anchor: '__container__', align: HorizontalAlign.Center }
  })
  .margin({ bottom: 24 });
```

Do **not** modify the button's `onClick` yet — that happens in Task 3. The button currently only plays the sound; leave it.

- [ ] **Step 5: Run build + UI test to verify it passes**

```bash
hvigorw assembleHap
hdc install <path-to-built-debug.hap>
hdc shell aa test -b com.terryma.wordmagicgame -m entry_test -s unittest OpenHarmonyTestRunner -w 120
```

Expected: both `clickHelloButton_shouldNotBlockUi` and `giftBox_initiallyClosed` PASS. Visually confirm the box appears above the button (optional, via screenshot or emulator).

- [ ] **Step 6: Commit**

```bash
git add entry/src/main/ets/components/GiftBox.ets \
        entry/src/main/ets/pages/Index.ets \
        entry/src/ohosTest/ets/test/IndexPage.ui.test.ets
git commit -m "feat(giftbox): render closed gift box above the click button"
```

---

## Task 3: Open/close cycle, trigger wiring, auto-close, timer cleanup

**Files:**
- Modify: `entry/src/main/ets/components/GiftBox.ets`
- Modify: `entry/src/main/ets/pages/Index.ets`
- Modify: `entry/src/ohosTest/ets/test/IndexPage.ui.test.ets`

Wire the button tap to the component, animate the lid off on open, auto-close after 1.5s, reset on rapid repeat taps. No ribbons yet (Task 4).

- [ ] **Step 1: Write the failing UI tests**

Add two new `it` cases inside the existing `describe('IndexPageUiTest', ...)` block in `entry/src/ohosTest/ets/test/IndexPage.ui.test.ets`. Place them after `giftBox_initiallyClosed`:

```ts
    it('giftBox_opensOnTap', 0, async (done: Function) => {
      const driver = await launchIndex();
      await driver.assertComponentExist(ON.id('GiftBoxContainer'));

      const button = await driver.findComponent(ON.id('HelloButton'));
      await button.click();
      await driver.delayMs(500);

      const openNow: boolean = await componentExists(driver, 'GiftBoxOpenMarker');
      expect(openNow).assertTrue();
      done();
    });

    it('giftBox_autoClosesAfterTap', 0, async (done: Function) => {
      const driver = await launchIndex();
      const button = await driver.findComponent(ON.id('HelloButton'));
      await button.click();
      await driver.delayMs(2000);

      const stillOpen: boolean = await componentExists(driver, 'GiftBoxOpenMarker');
      expect(stillOpen).assertFalse();
      await driver.assertComponentExist(ON.id('GiftBoxContainer'));
      done();
    });
```

- [ ] **Step 2: Run UI tests to verify they fail**

```bash
hvigorw assembleHap
hdc install <path-to-built-debug.hap>
hdc shell aa test -b com.terryma.wordmagicgame -m entry_test -s unittest OpenHarmonyTestRunner -w 120
```

Expected: `giftBox_opensOnTap` FAILS because `GiftBoxOpenMarker` is never rendered. `giftBox_autoClosesAfterTap` may trivially pass (marker never exists) but is in place to guard Task 4+.

- [ ] **Step 3: Extend `GiftBox` with open/close state and trigger watch**

Replace the `GiftBox` struct body in `entry/src/main/ets/components/GiftBox.ets` with:

```ts
const BOX_BODY_RED: string = '#E63946';
const BOX_RIBBON_GOLD: string = '#F4C430';
const AUTO_CLOSE_DELAY_MS: number = 1500;

@Component
export struct GiftBox {
  @Prop @Watch('onTriggerChanged') trigger: number = 0;

  @State private isOpen: boolean = false;
  @State private lidTy: number = 0;
  @State private lidRotate: number = 0;
  @State private boxScale: number = 1;

  private timers: number[] = [];

  aboutToDisappear(): void {
    this.clearAllTimers();
  }

  private clearAllTimers(): void {
    for (let i = 0; i < this.timers.length; i++) {
      clearTimeout(this.timers[i]);
    }
    this.timers = [];
  }

  private scheduleTimer(cb: () => void, delayMs: number): void {
    const id: number = setTimeout(() => {
      cb();
    }, delayMs);
    this.timers.push(id);
  }

  private onTriggerChanged(): void {
    // Cancel any in-flight cycle and restart from closed.
    this.clearAllTimers();
    this.isOpen = false;
    this.lidTy = 0;
    this.lidRotate = 0;
    this.boxScale = 1;
    this.startCycle();
  }

  private startCycle(): void {
    this.isOpen = true;

    // Scale bounce: 1 → 1.08 → 1 over 200 ms total.
    animateTo({ duration: 100, curve: Curve.EaseOut }, () => {
      this.boxScale = 1.08;
    });
    this.scheduleTimer(() => {
      animateTo({ duration: 100, curve: Curve.EaseIn }, () => {
        this.boxScale = 1;
      });
    }, 100);

    // Lid off.
    animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
      this.lidTy = -40;
      this.lidRotate = -15;
    });

    // Auto-close.
    this.scheduleTimer(() => {
      this.isOpen = false;
      animateTo({ duration: 180, curve: Curve.EaseInOut }, () => {
        this.lidTy = 0;
        this.lidRotate = 0;
      });
    }, AUTO_CLOSE_DELAY_MS);
  }

  build(): void {
    Stack() {
      // Body.
      Stack() {
        Column()
          .width(120)
          .height(80)
          .borderRadius(8)
          .backgroundColor(BOX_BODY_RED);
        Column()
          .width(8)
          .height(80)
          .backgroundColor(BOX_RIBBON_GOLD);
      }
      .width(120)
      .height(80)
      .alignContent(Alignment.Bottom);

      // Lid group.
      Stack() {
        Column()
          .width(132)
          .height(32)
          .borderRadius(6)
          .backgroundColor(BOX_BODY_RED);
        Row() {
          Column()
            .width(24)
            .height(10)
            .borderRadius(5)
            .backgroundColor(BOX_RIBBON_GOLD)
            .rotate({ angle: 25 });
          Column()
            .width(24)
            .height(10)
            .borderRadius(5)
            .backgroundColor(BOX_RIBBON_GOLD)
            .rotate({ angle: -25 });
        }
        .width(56)
        .justifyContent(FlexAlign.Center);
      }
      .id('GiftBoxLid')
      .width(132)
      .height(32)
      .offset({ x: 0, y: -64 })
      .translate({ x: 0, y: this.lidTy })
      .rotate({ angle: this.lidRotate });

      // Invisible marker node — stable hook for UI tests.
      if (this.isOpen) {
        Text('')
          .id('GiftBoxOpenMarker')
          .width(1)
          .height(1)
          .opacity(0);
      }
    }
    .id('GiftBoxContainer')
    .width(132)
    .height(120)
    .scale({ x: this.boxScale, y: this.boxScale });
  }
}
```

- [ ] **Step 4: Wire the button's `onClick` in `Index.ets` to increment `clickTick`**

In `entry/src/main/ets/pages/Index.ets`, update the existing button `onClick` (currently only plays the sound) to also bump the tick. Change:

```ts
.onClick((): void => {
  void this.playBundledNotificationSound();
})
```

to:

```ts
.onClick((): void => {
  this.clickTick += 1;
  void this.playBundledNotificationSound();
})
```

- [ ] **Step 5: Run build + UI tests to verify they pass**

```bash
hvigorw assembleHap
hdc install <path-to-built-debug.hap>
hdc shell aa test -b com.terryma.wordmagicgame -m entry_test -s unittest OpenHarmonyTestRunner -w 120
```

Expected: `clickHelloButton_shouldNotBlockUi`, `giftBox_initiallyClosed`, `giftBox_opensOnTap`, and `giftBox_autoClosesAfterTap` all PASS.

- [ ] **Step 6: Commit**

```bash
git add entry/src/main/ets/components/GiftBox.ets \
        entry/src/main/ets/pages/Index.ets \
        entry/src/ohosTest/ets/test/IndexPage.ui.test.ets
git commit -m "feat(giftbox): animate open/close cycle on button tap"
```

---

## Task 4: Ribbon burst (nested `GiftBoxRibbon` + radial fly-out and fade)

**Files:**
- Modify: `entry/src/main/ets/components/GiftBox.ets`
- Modify: `entry/src/ohosTest/ets/test/IndexPage.ui.test.ets`

Adds the ribbon burst: ~10 ribbons fly outward, fall, and fade out, cleared at 900 ms. Each ribbon runs its own transform animation so that under `ForEach` they animate reliably.

- [ ] **Step 1: Write the failing UI test**

Add a new `it` case inside the existing `describe('IndexPageUiTest', ...)` block, after `giftBox_autoClosesAfterTap`:

```ts
    it('giftBox_spawnsAndRetiresRibbons', 0, async (done: Function) => {
      const driver = await launchIndex();
      const button = await driver.findComponent(ON.id('HelloButton'));
      await button.click();
      await driver.delayMs(200);

      const ribbonPresent: boolean = await componentExists(driver, 'GiftBoxRibbon0');
      expect(ribbonPresent).assertTrue();

      await driver.delayMs(1200);
      const ribbonGone: boolean = await componentExists(driver, 'GiftBoxRibbon0');
      expect(ribbonGone).assertFalse();
      done();
    });
```

- [ ] **Step 2: Run UI tests to verify the new case fails**

```bash
hvigorw assembleHap
hdc install <path-to-built-debug.hap>
hdc shell aa test -b com.terryma.wordmagicgame -m entry_test -s unittest OpenHarmonyTestRunner -w 120
```

Expected: `giftBox_spawnsAndRetiresRibbons` FAILS — `GiftBoxRibbon0` never renders. Other cases still pass.

- [ ] **Step 3: Add the nested `GiftBoxRibbon` component and wire ribbon lifecycle into `GiftBox`**

Edit `entry/src/main/ets/components/GiftBox.ets`:

**(a)** Add these constants near the other `BOX_*` constants:

```ts
const RIBBON_COUNT: number = 10;
const RIBBON_FLY_RADIUS: number = 90;
const RIBBON_GRAVITY_DROP: number = 120;
const RIBBON_PHASE1_MS: number = 300;
const RIBBON_PHASE2_MS: number = 600;
const RIBBON_CLEAR_DELAY_MS: number = 900;
```

**(b)** Add the nested ribbon component *above* the existing `@Component export struct GiftBox` block (internal to this file, not exported):

```ts
@Component
struct GiftBoxRibbon {
  @Prop angleDeg: number = 0;
  @Prop color: string = '#E63946';
  @Prop index: number = 0;

  @State private tx: number = 0;
  @State private ty: number = 0;
  @State private opacityValue: number = 1;

  private phase2Timer: number = 0;

  aboutToAppear(): void {
    const angleRad: number = this.angleDeg * Math.PI / 180;
    const flyX: number = Math.cos(angleRad) * RIBBON_FLY_RADIUS;
    const flyY: number = Math.sin(angleRad) * RIBBON_FLY_RADIUS;

    animateTo({ duration: RIBBON_PHASE1_MS, curve: Curve.EaseOut }, () => {
      this.tx = flyX;
      this.ty = flyY;
    });

    this.phase2Timer = setTimeout(() => {
      animateTo({ duration: RIBBON_PHASE2_MS, curve: Curve.EaseIn }, () => {
        this.ty = flyY + RIBBON_GRAVITY_DROP;
        this.opacityValue = 0;
      });
    }, RIBBON_PHASE1_MS);
  }

  aboutToDisappear(): void {
    if (this.phase2Timer !== 0) {
      clearTimeout(this.phase2Timer);
      this.phase2Timer = 0;
    }
  }

  build(): void {
    Column()
      .id(`GiftBoxRibbon${this.index}`)
      .width(10)
      .height(18)
      .borderRadius(3)
      .backgroundColor(this.color)
      .translate({ x: this.tx, y: this.ty })
      .opacity(this.opacityValue);
  }
}
```

**(c)** Add a `@State ribbons: Ribbon[] = []` field to `GiftBox`. Update `onTriggerChanged` to clear ribbons on reset, update `startCycle` to spawn and later clear them, and update `build()` to render them:

Change the `GiftBox` struct state section from:

```ts
  @State private isOpen: boolean = false;
  @State private lidTy: number = 0;
  @State private lidRotate: number = 0;
  @State private boxScale: number = 1;
```

to:

```ts
  @State private isOpen: boolean = false;
  @State private lidTy: number = 0;
  @State private lidRotate: number = 0;
  @State private boxScale: number = 1;
  @State private ribbons: Ribbon[] = [];
```

Change `onTriggerChanged` from:

```ts
  private onTriggerChanged(): void {
    this.clearAllTimers();
    this.isOpen = false;
    this.lidTy = 0;
    this.lidRotate = 0;
    this.boxScale = 1;
    this.startCycle();
  }
```

to:

```ts
  private onTriggerChanged(): void {
    this.clearAllTimers();
    this.isOpen = false;
    this.lidTy = 0;
    this.lidRotate = 0;
    this.boxScale = 1;
    this.ribbons = [];
    this.startCycle();
  }
```

Change `startCycle` from (existing body with bounce + lid + auto-close) to include ribbon spawn/clear:

```ts
  private startCycle(): void {
    this.isOpen = true;

    animateTo({ duration: 100, curve: Curve.EaseOut }, () => {
      this.boxScale = 1.08;
    });
    this.scheduleTimer(() => {
      animateTo({ duration: 100, curve: Curve.EaseIn }, () => {
        this.boxScale = 1;
      });
    }, 100);

    animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
      this.lidTy = -40;
      this.lidRotate = -15;
    });

    // Spawn ribbons — each one animates itself in its own aboutToAppear.
    this.ribbons = generateRibbons(RIBBON_COUNT);

    // Retire ribbons after both animation phases complete.
    this.scheduleTimer(() => {
      this.ribbons = [];
    }, RIBBON_CLEAR_DELAY_MS);

    this.scheduleTimer(() => {
      this.isOpen = false;
      animateTo({ duration: 180, curve: Curve.EaseInOut }, () => {
        this.lidTy = 0;
        this.lidRotate = 0;
      });
    }, AUTO_CLOSE_DELAY_MS);
  }
```

Add a ribbon layer inside `build()`. Place this **immediately before** the closing `}` of the outermost `Stack()` (after the `if (this.isOpen) { Text('')... }` block, still inside the `GiftBoxContainer` stack):

```ts
      ForEach(
        this.ribbons,
        (r: Ribbon) => {
          GiftBoxRibbon({ angleDeg: r.angleDeg, color: r.color, index: r.id });
        },
        (r: Ribbon) => r.id.toString()
      );
```

- [ ] **Step 4: Run build + UI tests to verify they pass**

```bash
hvigorw assembleHap
hdc install <path-to-built-debug.hap>
hdc shell aa test -b com.terryma.wordmagicgame -m entry_test -s unittest OpenHarmonyTestRunner -w 120
```

Expected: all five UI cases plus the six local unit cases PASS:

```text
clickHelloButton_shouldNotBlockUi
giftBox_initiallyClosed
giftBox_opensOnTap
giftBox_autoClosesAfterTap
giftBox_spawnsAndRetiresRibbons
generateRibbons > returnsRequestedCount
generateRibbons > assignsUniqueIncrementingIds
generateRibbons > spreadsAnglesAcrossCircle
generateRibbons > colorsOnlyFromPalette
generateRibbons > isDeterministic
generateRibbons > handlesZeroCount
```

- [ ] **Step 5: Commit**

```bash
git add entry/src/main/ets/components/GiftBox.ets \
        entry/src/ohosTest/ets/test/IndexPage.ui.test.ets
git commit -m "feat(giftbox): burst ribbons radially when the box opens"
```

---

## Task 5: Rapid double-tap regression test

**Files:**
- Modify: `entry/src/ohosTest/ets/test/IndexPage.ui.test.ets`

A regression test to lock in the reset-on-repeat-tap behavior and teardown safety. No production code changes expected — if this fails, Task 3's reset logic is wrong and must be fixed before this task is considered complete.

- [ ] **Step 1: Write the regression test**

Add a new `it` case inside the existing `describe('IndexPageUiTest', ...)` block, after `giftBox_spawnsAndRetiresRibbons`:

```ts
    it('giftBox_rapidDoubleTapRestartsCleanly', 0, async (done: Function) => {
      const driver = await launchIndex();
      const button = await driver.findComponent(ON.id('HelloButton'));

      await button.click();
      await driver.delayMs(200);
      await button.click();

      // After the second tap, the cycle restarts: open marker must be present shortly.
      await driver.delayMs(500);
      const openMid: boolean = await componentExists(driver, 'GiftBoxOpenMarker');
      expect(openMid).assertTrue();

      // And it auto-closes ~1500ms after the second tap, so total ~2200ms from first tap is safe.
      await driver.delayMs(2000);
      const openLater: boolean = await componentExists(driver, 'GiftBoxOpenMarker');
      expect(openLater).assertFalse();

      // Container itself must still be alive — rules out a crash or teardown bug.
      await driver.assertComponentExist(ON.id('GiftBoxContainer'));
      done();
    });
```

- [ ] **Step 2: Run UI tests to verify it passes**

```bash
hvigorw assembleHap
hdc install <path-to-built-debug.hap>
hdc shell aa test -b com.terryma.wordmagicgame -m entry_test -s unittest OpenHarmonyTestRunner -w 120
```

Expected: the new case PASSES with no production-code changes. If it fails, inspect `onTriggerChanged` / `clearAllTimers` — the failure is almost certainly a stale timer firing after reset and prematurely closing the box.

- [ ] **Step 3: Commit**

```bash
git add entry/src/ohosTest/ets/test/IndexPage.ui.test.ets
git commit -m "test(giftbox): cover rapid double-tap reset behavior"
```

---

## Post-implementation self-check (for the implementer)

Before declaring the feature done, verify:

- `hvigorw assembleHap` succeeds with no warnings introduced by these files.
- `hvigorw -p module=entry@default test` — all six `generateRibbons` unit cases pass.
- `hdc shell aa test -b com.terryma.wordmagicgame -m entry_test -s unittest OpenHarmonyTestRunner -w 120` — all UI cases pass on device, and `OHOS_REPORT_CODE: 0`.
- Visual smoke test on device: tap button → box opens with bounce, ribbons fly out radially, fall + fade, box auto-closes by ~1.5s.
- Rapid double-tap smoke test: mash the button — no stale ribbons linger, no crashes, final state is closed.

## Spec ↔ plan coverage map

| Spec item | Task(s) |
|---|---|
| Box visible in closed state on page load | Task 2 |
| Tap plays sound (unchanged) + triggers open | Task 3 (sound) / Task 3 (trigger) |
| Open bounce (~200 ms) | Task 3 |
| Lid translate-up + rotate on open | Task 3 |
| 10 ribbons, radial fly-out (~300 ms) | Task 4 |
| Ribbon fall + fade (~600 ms) | Task 4 |
| Ribbons cleared at ~900 ms | Task 4 |
| Auto-close at ~1500 ms | Task 3 |
| Rapid-repeat tap → clean reset | Task 3 (impl) / Task 5 (regression test) |
| No new media assets | Task 2 / Task 3 / Task 4 |
| `generateRibbons` unit tests | Task 1 |
| `GiftBoxContainer` / `GiftBoxOpenMarker` / `GiftBoxRibbon{n}` ids | Task 2, 3, 4 |
| Timer teardown in `aboutToDisappear` | Task 3 (parent), Task 4 (child) |
