# Gift Box Open Animation — Design

Date: 2026-04-22
Status: Draft (pending user review)
Scope: HarmonyOS NEXT (ArkTS) — `entry` module only

## Goal

Add a gift box animation above the existing "点击我" button on `entry/src/main/ets/pages/Index.ets`. Tapping the button plays the current notification sound *and* triggers a gift-box open animation: the lid pops off, a burst of colored ribbons flies out radially, the ribbons fall and fade, and the box auto-closes so subsequent taps can replay the effect.

## User-facing behavior

1. On page appear, a gift box is rendered above the button in its **closed** state.
2. On tap of "点击我":
   - The bundled notification sound plays (existing behavior, unchanged).
   - The box performs a brief scale bounce (~200ms) and transitions to the **open** state: the lid translates up and rotates slightly off the body.
   - ~10 small ribbon rectangles spawn at the box center, fly outward radially (~300ms), then fall + fade out (~600ms).
   - At t ≈ 1500ms from the tap, the lid animates back to the closed position.
3. Rapid repeat taps reset the cycle: any in-flight animation and pending timers are cancelled, the ribbon list is cleared, and the cycle starts over from the beginning. The sound plays on every tap as today.

## Non-goals

- No designer-produced art assets (Lottie, PNG frames, SVG files). The visuals are drawn entirely in ArkTS using built-in primitives. Art can be swapped in later by replacing a small, well-isolated set of sub-views.
- No changes to the existing notification-sound pipeline (`aboutToAppear`, `AVPlayer` setup, `playBundledNotificationSound`).
- No new third-party dependencies, no `oh-package.json5` changes.
- No persistence, no analytics, no multi-box variants.

## Architecture

### Files touched / added

- **New:** `entry/src/main/ets/components/GiftBox.ets` — self-contained component + a pure ribbon-generation helper.
- **Modified:** `entry/src/main/ets/pages/Index.ets` — import `GiftBox`, add a trigger-counter `@State`, render `GiftBox` above the button, increment the counter on button tap.
- **Modified:** `entry/src/ohosTest/ets/test/IndexPage.ui.test.ets` — extend with assertions for the gift-box lifecycle.
- **New (optional, if local unit tests are supported for this module):** `entry/src/test/**/GiftBox.test.ets` (or extend `List.test.ets`) — cover the pure ribbon-generation helper.

### Component: `GiftBox`

Single `@Component` struct. Public interface:

```ts
@Component
export struct GiftBox {
  // Parent increments on each tap. Any change (including value repeats via increment)
  // triggers a new cycle. Using a number instead of boolean guarantees @Watch fires
  // on every tap, not only on state transitions.
  @Prop @Watch('onTriggerChanged') trigger: number = 0;
}
```

Internal state:

- `@State private isOpen: boolean = false`
- `@State private boxScale: number = 1` — for the open-pop bounce.
- `@State private ribbons: Ribbon[] = []`
- `private timers: number[] = []` — all `setTimeout` ids, cleared on reset and teardown.

Internal helpers:

- `private onTriggerChanged(): void` — called by `@Watch`; cancels pending timers, resets state, starts cycle.
- `private startCycle(): void` — sequences: open → ribbon phase 1 → ribbon phase 2 → clear ribbons → close.
- `private scheduleTimer(cb: () => void, delayMs: number): void` — wraps `setTimeout`, records id.
- `aboutToDisappear(): void` — clear all timers, clear ribbons, reset `isOpen`.

### Pure helper: `generateRibbons`

Lives in the same file and is exported so it can be unit-tested without a UI:

```ts
export function generateRibbons(count: number): Ribbon[]
```

- Evenly spaced base angles: `i * (360 / count)` degrees.
- Small deterministic jitter derived from `i` (not `Math.random()`) so tests are stable. E.g. `jitter = ((i * 37) % 21) - 10` degrees.
- Colors cycle through a fixed palette: `['#E63946', '#F4C430', '#457B9D', '#F78DA7']`.
- `tx`, `ty` start at 0; `opacity` starts at 1.

### `Ribbon` data class

```ts
class Ribbon {
  id: number = 0;
  angleDeg: number = 0;
  color: string = '#E63946';
  tx: number = 0;
  ty: number = 0;
  opacity: number = 1;
}
```

## Visual layout

Container: `Stack` of 120 × 120 vp, centered horizontally above `HelloButton` using `RelativeContainer` `alignRules` (anchor its bottom to `HelloButton`'s top with a small margin).

Layers inside the stack (bottom-up):

1. **Body** — rounded rectangle, 120 × 80 vp, color `#E63946`, `borderRadius: 8`, aligned to bottom of stack. A narrow 8 vp wide `Column` with `backgroundColor: '#F4C430'` runs vertically down its center to evoke gift wrap.
2. **Lid group** — a `Column` composed of:
   - Lid rectangle: 132 × 32 vp, color `#E63946`, `borderRadius: 6`, overhanging the body by 6 vp on each side.
   - Bow: two 24 × 10 vp gold (`#F4C430`) rounded rectangles rotated `+25°` and `-25°`, overlapped to form a bowtie, placed on top of the lid center.
   - Transform binding:
     - Closed: `translateY(0) rotate(0deg)`
     - Open: `translateY(-40 vp) rotate(-15deg)` (values driven by `isOpen`)
3. **Ribbon layer** — absolute children of the same stack, each a `Column` of 10 × 18 vp with `borderRadius: 3`, colored per `Ribbon.color`, positioned at the stack center and offset by `translate({ x: tx, y: ty })` with `opacity`.

All numeric sizes above are in `vp`.

### IDs (for UI tests)

- `'GiftBoxContainer'` — the outer stack.
- `'GiftBoxLid'` — the lid group (always present; its transform reflects open/closed).
- `'GiftBoxOpenMarker'` — a zero-size invisible node rendered only when `isOpen === true`, used as a stable hook for UI tests to assert the open state.

## Animation details

All transitions use `animateTo` from ArkTS.

### Open (on tap)

- Scale bounce: `boxScale: 1 → 1.08` over 100ms `Curve.EaseOut`, then back to `1.0` over 100ms `Curve.EaseIn`.
- Lid transform: closed → open over 200ms `Curve.EaseOut`, run in parallel with the bounce.
- Set `isOpen = true` at cycle start.

### Ribbon burst

- **Phase 1 (fly out), 300ms, `Curve.EaseOut`:** inside an `animateTo` block, for each ribbon set `tx = cos(angleRad) * 90`, `ty = sin(angleRad) * 90`.
- **Phase 2 (fall + fade), 600ms, `Curve.EaseIn`:** scheduled 300ms after cycle start. Inside `animateTo`, for each ribbon add `ty += 120` and set `opacity = 0`.
- **Cleanup:** 900ms after cycle start, `this.ribbons = []`.

### Auto-close

- 1500ms after cycle start: `animateTo({ duration: 180, curve: Curve.EaseInOut })` → lid back to closed transform; `isOpen = false`; clear timer-id array.

### Timer schedule (in ms, relative to tap)

| Time   | Action                                    |
|--------|-------------------------------------------|
| 0      | Cancel previous, reset, bounce + open lid, spawn ribbons with tx/ty = 0 |
| ~1 RAF | Start Phase 1 animateTo (fly out)         |
| 300    | Start Phase 2 animateTo (fall + fade)     |
| 900    | Clear `ribbons`                           |
| 1500   | Close lid, `isOpen = false`               |

## Integration with `Index.ets`

```ts
import { GiftBox } from '../components/GiftBox';
```

Changes inside `struct Index`:

- Add `@State private clickTick: number = 0;`
- Inside the `RelativeContainer`, above the existing `Button('点击我')`, add:

```ts
GiftBox({ trigger: this.clickTick })
  .id('GiftBoxContainer')
  .alignRules({
    bottom: { anchor: 'HelloButton', align: VerticalAlign.Top },
    middle: { anchor: '__container__', align: HorizontalAlign.Center }
  })
  .margin({ bottom: 24 })
```

- In the button `onClick`, before the existing sound call:

```ts
this.clickTick += 1;
void this.playBundledNotificationSound();
```

The existing AVPlayer setup and teardown are untouched.

## Error handling & edge cases

- **Teardown mid-animation:** `aboutToDisappear` clears every recorded timer id and resets state. No references to the component are held by external code beyond the `trigger` prop, so there is nothing else to clean up.
- **Rapid repeat taps:** each `@Watch` invocation cancels all pending timers, resets `ribbons = []`, resets the lid to closed for one frame, then restarts the cycle. Users see a hard reset, which is acceptable and expected per the approved behavior (option D).
- **Animation running when page is backgrounded:** HarmonyOS pauses rendering; on resume, any timers that fired during the background will simply apply their state changes immediately. The worst visible outcome is the box snapping to closed. No crash risk.
- **Theme / dark mode:** colors are hard-coded literals in this spec. This is acceptable for now; a future refactor can move them to `$r('app.color.*')` resources without changing the component shape.

## Testing

### UI test — extend `entry/src/ohosTest/ets/test/IndexPage.ui.test.ets`

New cases (names illustrative):

1. **`giftBox_initiallyClosed`** — Launch the page; assert a node with id `'GiftBoxContainer'` exists and `'GiftBoxOpenMarker'` does **not** exist.
2. **`giftBox_opensOnTap`** — Tap the "点击我" button; within ~500ms assert `'GiftBoxOpenMarker'` exists.
3. **`giftBox_autoClosesAfterTap`** — After a tap, wait ~1800ms; assert `'GiftBoxOpenMarker'` no longer exists.

The tests do not assert exact timings or ribbon counts visually (fragile); they check observable lifecycle markers.

### Unit test — new or extended file under `entry/src/test`

Cover `generateRibbons`:

- `generateRibbons(10).length === 10`.
- Angle spread: the set of `angleDeg` values, normalized to [0, 360), covers at least 270° of range (sanity check for even distribution).
- Colors come only from the fixed palette.
- Output is deterministic across two calls with the same `count` (no `Math.random`).

If the existing unit-test wiring in this module does not conveniently support importing from `entry/src/main/ets/components/`, the helper will be validated via a UI-test-level assertion instead, and we will not block on adding a new unit-test setup.

## Risks and open considerations

- **`setTimeout` availability in ArkTS:** ArkTS exposes global `setTimeout` and `clearTimeout` in standard HarmonyOS NEXT; implementation will confirm at the first build step. If unavailable, fall back to a frame-based timer using `getUIContext().getFrameRateRange`-friendly scheduling or chained `animateTo` `onFinish` callbacks. This would affect the `GiftBox` internals only; the public API and visible behavior do not change.
- **`@Prop` vs `@Link` for `trigger`:** `@Prop` is sufficient because the child does not mutate it. `@Watch` works on `@Prop`. This will be confirmed against the ArkTS state-management rules during implementation; if it doesn't fire reliably, the fallback is to expose a callback via a parent-owned `@Provide`/`@Consume` pair or to pass an object ref.
- **vp sizing on very small screens:** 120 × 120 vp plus a 56 vp button and 80 vp bottom margin fits comfortably on standard HarmonyOS phone sizes. No responsive tier is planned for this iteration.

## Future work (out of scope)

- Swap the ArkTS-drawn box for real art (`Image($r('app.media.box_closed'))` / `box_open`).
- Replace the code-driven ribbons with a Lottie animation.
- Parameterize colors and durations via `$r('app.color.*')` / `$r('app.float.*')` resources.
- Add haptic feedback on open.
