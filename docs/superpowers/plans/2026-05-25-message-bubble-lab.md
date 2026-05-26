# Message Bubble Lab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a reusable HarmonyOS `MessageBubble` component and a debug-only Message Bubble Lab page for tuning free-triangle tail geometry before applying it to battle dialogue.

**Architecture:** Keep geometry logic pure and unit-tested in `MessageBubbleGeometry.ets`, render the ArkUI component in `MessageBubble.ets`, and host tuning controls in a new `MessageBubbleLabPage.ets` reachable from `DevMenuPage`. Tail geometry is always three absolute `vp` points; twelve presets are helpers that generate editable coordinates.

**Tech Stack:** HarmonyOS NEXT, ArkTS / ArkUI, Hypium local unit tests, Hvigor, CodeLinter, manual simulator screenshots.

---

## File Structure

- Create `harmonyos/entry/src/main/ets/components/MessageBubbleGeometry.ets`: pure types, preset enum, preset coordinate helper, output formatting helper.
- Create `harmonyos/entry/src/test/MessageBubbleGeometry.test.ets`: local unit tests for all twelve presets and manual config pass-through.
- Modify `harmonyos/entry/src/test/List.test.ets`: register the new local unit test.
- Create `harmonyos/entry/src/main/ets/components/MessageBubble.ets`: reusable ArkUI component that renders the bubble body and tail, with seam handling private to the component.
- Create `harmonyos/entry/src/main/ets/components/MessageBubbleLabState.ets`: pure Lab state helpers for preset selection, tip adjustment, and output formatting.
- Create `harmonyos/entry/src/test/MessageBubbleLabState.test.ets`: local unit tests for Lab state updates.
- Create `harmonyos/entry/src/main/ets/pages/MessageBubbleLabPage.ets`: debug-only page with preset controls, numeric controls, live preview, and config output.
- Modify `harmonyos/entry/src/main/resources/base/profile/main_pages.json`: register `pages/MessageBubbleLabPage`.
- Modify `harmonyos/entry/src/main/ets/pages/DevMenuPage.ets`: add a debug card/button to open Message Bubble Lab.

## Task 1: Geometry Types And Presets

**Files:**
- Create: `harmonyos/entry/src/main/ets/components/MessageBubbleGeometry.ets`
- Create: `harmonyos/entry/src/test/MessageBubbleGeometry.test.ets`
- Modify: `harmonyos/entry/src/test/List.test.ets`

- [ ] **Step 1: Write the failing unit tests**

Create `harmonyos/entry/src/test/MessageBubbleGeometry.test.ets`:

```ts
import { describe, it, expect } from '@ohos/hypium';
import {
  MessageBubblePoint,
  MessageBubbleTail,
  MessageBubbleBox,
  MessageBubbleTailPreset,
  buildMessageBubbleTailPreset,
  normalizeMessageBubbleTail,
} from '../main/ets/components/MessageBubbleGeometry';

function expectPoint(point: MessageBubblePoint, x: number, y: number): void {
  expect(point.x).assertEqual(x);
  expect(point.y).assertEqual(y);
}

export default function messageBubbleGeometryTest() {
  describe('MessageBubbleGeometry', () => {
    const box: MessageBubbleBox = {
      width: 240,
      height: 120,
      borderWidth: 4,
      tailBase: 36,
      tailLength: 44,
      inset: 28,
    };

    it('buildsBottomRightPresetWithVpCoordinates', 0, () => {
      const tail: MessageBubbleTail =
        buildMessageBubbleTailPreset(MessageBubbleTailPreset.BottomRight, box);

      expectPoint(tail.baseStart, 176, 120);
      expectPoint(tail.baseEnd, 212, 120);
      expectPoint(tail.tip, 240, 164);
    });

    it('buildsTopMiddlePresetWithTipAboveBody', 0, () => {
      const tail: MessageBubbleTail =
        buildMessageBubbleTailPreset(MessageBubbleTailPreset.TopMiddle, box);

      expectPoint(tail.baseStart, 102, 0);
      expectPoint(tail.baseEnd, 138, 0);
      expectPoint(tail.tip, 120, -44);
    });

    it('buildsLeftBottomPresetWithTipOutsideLeftBody', 0, () => {
      const tail: MessageBubbleTail =
        buildMessageBubbleTailPreset(MessageBubbleTailPreset.LeftBottom, box);

      expectPoint(tail.baseStart, 0, 56);
      expectPoint(tail.baseEnd, 0, 92);
      expectPoint(tail.tip, -44, 120);
    });

    it('buildsEveryPresetWithBaseOnRequestedSideAndTipOutside', 0, () => {
      const presets: MessageBubbleTailPreset[] = [
        MessageBubbleTailPreset.TopLeft,
        MessageBubbleTailPreset.TopMiddle,
        MessageBubbleTailPreset.TopRight,
        MessageBubbleTailPreset.BottomLeft,
        MessageBubbleTailPreset.BottomMiddle,
        MessageBubbleTailPreset.BottomRight,
        MessageBubbleTailPreset.LeftTop,
        MessageBubbleTailPreset.LeftMiddle,
        MessageBubbleTailPreset.LeftBottom,
        MessageBubbleTailPreset.RightTop,
        MessageBubbleTailPreset.RightMiddle,
        MessageBubbleTailPreset.RightBottom,
      ];

      for (let i: number = 0; i < presets.length; i++) {
        const preset: MessageBubbleTailPreset = presets[i];
        const tail: MessageBubbleTail = buildMessageBubbleTailPreset(preset, box);
        if (preset.indexOf('Top') === 0) {
          expect(tail.baseStart.y).assertEqual(0);
          expect(tail.baseEnd.y).assertEqual(0);
          expect(tail.tip.y < 0).assertTrue();
        } else if (preset.indexOf('Bottom') === 0) {
          expect(tail.baseStart.y).assertEqual(box.height);
          expect(tail.baseEnd.y).assertEqual(box.height);
          expect(tail.tip.y > box.height).assertTrue();
        } else if (preset.indexOf('Left') === 0) {
          expect(tail.baseStart.x).assertEqual(0);
          expect(tail.baseEnd.x).assertEqual(0);
          expect(tail.tip.x < 0).assertTrue();
        } else {
          expect(tail.baseStart.x).assertEqual(box.width);
          expect(tail.baseEnd.x).assertEqual(box.width);
          expect(tail.tip.x > box.width).assertTrue();
        }
      }
    });

    it('normalizesManualTailWithoutChangingVpCoordinates', 0, () => {
      const manual: MessageBubbleTail = {
        baseStart: { x: 188, y: 132 },
        baseEnd: { x: 226, y: 132 },
        tip: { x: 262, y: 194 },
      };

      const out: MessageBubbleTail = normalizeMessageBubbleTail(manual);

      expectPoint(out.baseStart, 188, 132);
      expectPoint(out.baseEnd, 226, 132);
      expectPoint(out.tip, 262, 194);
    });
  });
}
```

Modify `harmonyos/entry/src/test/List.test.ets` by importing and registering the test:

```ts
import messageBubbleGeometryTest from './MessageBubbleGeometry.test';

export default function testsuite() {
  // keep existing registrations
  messageBubbleGeometryTest();
}
```

- [ ] **Step 2: Run the unit test to verify it fails**

Run:

```bash
cd harmonyos && hvigorw -p module=entry@default test
```

Expected: FAIL because `../main/ets/components/MessageBubbleGeometry` does not exist.

- [ ] **Step 3: Implement the pure geometry helper**

Create `harmonyos/entry/src/main/ets/components/MessageBubbleGeometry.ets`:

```ts
export interface MessageBubblePoint {
  x: number;
  y: number;
}

export interface MessageBubbleTail {
  baseStart: MessageBubblePoint;
  baseEnd: MessageBubblePoint;
  tip: MessageBubblePoint;
}

export interface MessageBubbleBox {
  width: number;
  height: number;
  borderWidth: number;
  tailBase: number;
  tailLength: number;
  inset: number;
}

export enum MessageBubbleTailPreset {
  TopLeft = 'TopLeft',
  TopMiddle = 'TopMiddle',
  TopRight = 'TopRight',
  BottomLeft = 'BottomLeft',
  BottomMiddle = 'BottomMiddle',
  BottomRight = 'BottomRight',
  LeftTop = 'LeftTop',
  LeftMiddle = 'LeftMiddle',
  LeftBottom = 'LeftBottom',
  RightTop = 'RightTop',
  RightMiddle = 'RightMiddle',
  RightBottom = 'RightBottom',
}

function clampStart(start: number, length: number, base: number): number {
  if (start < 0) {
    return 0;
  }
  const maxStart: number = length - base;
  if (start > maxStart) {
    return maxStart;
  }
  return start;
}

function horizontalBaseStart(preset: MessageBubbleTailPreset, box: MessageBubbleBox): number {
  if (preset === MessageBubbleTailPreset.TopLeft ||
    preset === MessageBubbleTailPreset.BottomLeft) {
    return clampStart(box.inset, box.width, box.tailBase);
  }
  if (preset === MessageBubbleTailPreset.TopRight ||
    preset === MessageBubbleTailPreset.BottomRight) {
    return clampStart(box.width - box.inset - box.tailBase, box.width, box.tailBase);
  }
  return clampStart((box.width - box.tailBase) / 2, box.width, box.tailBase);
}

function verticalBaseStart(preset: MessageBubbleTailPreset, box: MessageBubbleBox): number {
  if (preset === MessageBubbleTailPreset.LeftTop ||
    preset === MessageBubbleTailPreset.RightTop) {
    return clampStart(box.inset, box.height, box.tailBase);
  }
  if (preset === MessageBubbleTailPreset.LeftBottom ||
    preset === MessageBubbleTailPreset.RightBottom) {
    return clampStart(box.height - box.inset - box.tailBase, box.height, box.tailBase);
  }
  return clampStart((box.height - box.tailBase) / 2, box.height, box.tailBase);
}

export function normalizeMessageBubbleTail(tail: MessageBubbleTail): MessageBubbleTail {
  return {
    baseStart: { x: tail.baseStart.x, y: tail.baseStart.y },
    baseEnd: { x: tail.baseEnd.x, y: tail.baseEnd.y },
    tip: { x: tail.tip.x, y: tail.tip.y },
  };
}

export function buildMessageBubbleTailPreset(
  preset: MessageBubbleTailPreset,
  box: MessageBubbleBox,
): MessageBubbleTail {
  if (preset.indexOf('Top') === 0) {
    const startX: number = horizontalBaseStart(preset, box);
    return {
      baseStart: { x: startX, y: 0 },
      baseEnd: { x: startX + box.tailBase, y: 0 },
      tip: { x: startX + box.tailBase / 2, y: -box.tailLength },
    };
  }
  if (preset.indexOf('Bottom') === 0) {
    const startX: number = horizontalBaseStart(preset, box);
    return {
      baseStart: { x: startX, y: box.height },
      baseEnd: { x: startX + box.tailBase, y: box.height },
      tip: { x: startX + box.tailBase / 2, y: box.height + box.tailLength },
    };
  }
  if (preset.indexOf('Left') === 0) {
    const startY: number = verticalBaseStart(preset, box);
    return {
      baseStart: { x: 0, y: startY },
      baseEnd: { x: 0, y: startY + box.tailBase },
      tip: { x: -box.tailLength, y: startY + box.tailBase / 2 },
    };
  }
  const startY: number = verticalBaseStart(preset, box);
  return {
    baseStart: { x: box.width, y: startY },
    baseEnd: { x: box.width, y: startY + box.tailBase },
    tip: { x: box.width + box.tailLength, y: startY + box.tailBase / 2 },
  };
}
```

- [ ] **Step 4: Run unit tests to verify green**

Run:

```bash
cd harmonyos && hvigorw -p module=entry@default test
```

Expected: PASS for `MessageBubbleGeometry`; no new warnings.

- [ ] **Step 5: Commit**

```bash
git add harmonyos/entry/src/main/ets/components/MessageBubbleGeometry.ets harmonyos/entry/src/test/MessageBubbleGeometry.test.ets harmonyos/entry/src/test/List.test.ets
git commit -m "feat(harmony): add message bubble geometry presets"
```

## Task 2: Reusable MessageBubble Component

**Files:**
- Create: `harmonyos/entry/src/main/ets/components/MessageBubble.ets`
- Create: `harmonyos/entry/src/test/MessageBubble.test.ets`
- Modify: `harmonyos/entry/src/test/List.test.ets`

- [ ] **Step 1: Write the failing component helper test**

Create `harmonyos/entry/src/test/MessageBubble.test.ets`:

```ts
import { describe, it, expect } from '@ohos/hypium';
import {
  MessageBubbleFrame,
  messageBubbleFrame,
  messageBubblePathCommands,
} from '../main/ets/components/MessageBubble';
import {
  MessageBubbleTail,
} from '../main/ets/components/MessageBubbleGeometry';

export default function messageBubbleTest() {
  describe('MessageBubble.path', () => {
    it('buildsBottomTailAsPartOfSingleClosedPath', 0, () => {
      const tail: MessageBubbleTail = {
        baseStart: { x: 176, y: 120 },
        baseEnd: { x: 212, y: 120 },
        tip: { x: 240, y: 164 },
      };

      const commands: string = messageBubblePathCommands(240, 120, 18, tail);

      expect(commands.indexOf('M 18 0') >= 0).assertTrue();
      expect(commands.indexOf('L 212 120') >= 0).assertTrue();
      expect(commands.indexOf('L 240 164') >= 0).assertTrue();
      expect(commands.indexOf('L 176 120') >= 0).assertTrue();
      expect(commands.endsWith('Z')).assertTrue();
    });

    it('buildsTopTailWithFrameOffsetSoNegativeVpStaysVisible', 0, () => {
      const tail: MessageBubbleTail = {
        baseStart: { x: 102, y: 0 },
        baseEnd: { x: 138, y: 0 },
        tip: { x: 120, y: -44 },
      };

      const frame: MessageBubbleFrame = messageBubbleFrame(240, 120, tail);
      const commands: string = messageBubblePathCommands(240, 120, 18, tail);

      expect(frame.offsetY).assertEqual(44);
      expect(frame.height).assertEqual(164);
      expect(commands.indexOf('L 102 44') >= 0).assertTrue();
      expect(commands.indexOf('L 120 0') >= 0).assertTrue();
      expect(commands.indexOf('L 138 44') >= 0).assertTrue();
    });

    it('buildsLeftAndRightTailPointsOnTheirOwnEdges', 0, () => {
      const leftTail: MessageBubbleTail = {
        baseStart: { x: 0, y: 28 },
        baseEnd: { x: 0, y: 64 },
        tip: { x: -44, y: 46 },
      };
      const rightTail: MessageBubbleTail = {
        baseStart: { x: 240, y: 28 },
        baseEnd: { x: 240, y: 64 },
        tip: { x: 284, y: 46 },
      };

      const leftCommands: string = messageBubblePathCommands(240, 120, 18, leftTail);
      const rightCommands: string = messageBubblePathCommands(240, 120, 18, rightTail);

      expect(leftCommands.indexOf('L 44 64') >= 0).assertTrue();
      expect(leftCommands.indexOf('L 0 46') >= 0).assertTrue();
      expect(leftCommands.indexOf('L 44 28') >= 0).assertTrue();
      expect(rightCommands.indexOf('L 240 28') >= 0).assertTrue();
      expect(rightCommands.indexOf('L 284 46') >= 0).assertTrue();
      expect(rightCommands.indexOf('L 240 64') >= 0).assertTrue();
    });

    it('buildsRoundedBodyPathWhenTailIsMissing', 0, () => {
      const commands: string = messageBubblePathCommands(240, 120, 18, undefined);

      expect(commands.indexOf('240 60') < 0).assertTrue();
      expect(commands.indexOf('Q 240 120 222 120') >= 0).assertTrue();
      expect(commands.endsWith('Z')).assertTrue();
    });
  });
}
```

Modify `harmonyos/entry/src/test/List.test.ets`:

```ts
import messageBubbleTest from './MessageBubble.test';

export default function testsuite() {
  // keep existing registrations
  messageBubbleTest();
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
cd harmonyos && hvigorw -p module=entry@default test
```

Expected: FAIL because `MessageBubble.ets` and `messageBubblePathCommands` do not exist.

- [ ] **Step 3: Implement minimal reusable component and path helper**

Create `harmonyos/entry/src/main/ets/components/MessageBubble.ets`:

```ts
import {
  MessageBubblePoint,
  MessageBubbleTail,
  normalizeMessageBubbleTail,
} from './MessageBubbleGeometry';

enum MessageBubbleTailSide {
  Top = 'top',
  Right = 'right',
  Bottom = 'bottom',
  Left = 'left',
}

export interface MessageBubblePadding {
  left: number;
  right: number;
  top: number;
  bottom: number;
}

export interface MessageBubbleShadow {
  radius: number;
  color: ResourceColor;
  offsetX: number;
  offsetY: number;
}

export interface MessageBubbleFrame {
  width: number;
  height: number;
  offsetX: number;
  offsetY: number;
}

function min3(a: number, b: number, c: number): number {
  return Math.min(a, Math.min(b, c));
}

function max3(a: number, b: number, c: number): number {
  return Math.max(a, Math.max(b, c));
}

export function messageBubbleFrame(
  width: number,
  height: number,
  tail?: MessageBubbleTail,
): MessageBubbleFrame {
  if (tail === undefined) {
    return { width, height, offsetX: 0, offsetY: 0 };
  }
  const t: MessageBubbleTail = normalizeMessageBubbleTail(tail);
  const minX: number = Math.min(0, min3(t.baseStart.x, t.baseEnd.x, t.tip.x));
  const minY: number = Math.min(0, min3(t.baseStart.y, t.baseEnd.y, t.tip.y));
  const maxX: number = Math.max(width, max3(t.baseStart.x, t.baseEnd.x, t.tip.x));
  const maxY: number = Math.max(height, max3(t.baseStart.y, t.baseEnd.y, t.tip.y));
  return {
    width: maxX - minX,
    height: maxY - minY,
    offsetX: -minX,
    offsetY: -minY,
  };
}

function shifted(point: MessageBubblePoint, frame: MessageBubbleFrame): MessageBubblePoint {
  return {
    x: point.x + frame.offsetX,
    y: point.y + frame.offsetY,
  };
}

function detectTailSide(width: number, height: number, tail: MessageBubbleTail): MessageBubbleTailSide {
  if (tail.baseStart.y === 0 && tail.baseEnd.y === 0) {
    return MessageBubbleTailSide.Top;
  }
  if (tail.baseStart.x === width && tail.baseEnd.x === width) {
    return MessageBubbleTailSide.Right;
  }
  if (tail.baseStart.y === height && tail.baseEnd.y === height) {
    return MessageBubbleTailSide.Bottom;
  }
  if (tail.baseStart.x === 0 && tail.baseEnd.x === 0) {
    return MessageBubbleTailSide.Left;
  }
  return MessageBubbleTailSide.Bottom;
}

export function messageBubblePathCommands(
  width: number,
  height: number,
  radius: number,
  tail?: MessageBubbleTail,
): string {
  const r: number = Math.min(radius, width / 2, height / 2);
  const frame: MessageBubbleFrame = messageBubbleFrame(width, height, tail);
  const x: number = frame.offsetX;
  const y: number = frame.offsetY;
  const side: MessageBubbleTailSide | undefined = tail === undefined
    ? undefined
    : detectTailSide(width, height, tail);
  const t: MessageBubbleTail | undefined = tail === undefined
    ? undefined
    : {
      baseStart: shifted(tail.baseStart, frame),
      baseEnd: shifted(tail.baseEnd, frame),
      tip: shifted(tail.tip, frame),
    };
  const parts: string[] = [
    `M ${x + r} ${y}`,
  ];

  if (side === MessageBubbleTailSide.Top && t !== undefined) {
    parts.push(`L ${t.baseStart.x} ${t.baseStart.y}`, `L ${t.tip.x} ${t.tip.y}`, `L ${t.baseEnd.x} ${t.baseEnd.y}`);
  }
  parts.push(
    `L ${x + width - r} ${y}`,
    `Q ${x + width} ${y} ${x + width} ${y + r}`,
  );

  if (side === MessageBubbleTailSide.Right && t !== undefined) {
    parts.push(`L ${t.baseStart.x} ${t.baseStart.y}`, `L ${t.tip.x} ${t.tip.y}`, `L ${t.baseEnd.x} ${t.baseEnd.y}`);
  }
  parts.push(
    `L ${x + width} ${y + height - r}`,
    `Q ${x + width} ${y + height} ${x + width - r} ${y + height}`,
  );

  if (side === MessageBubbleTailSide.Bottom && t !== undefined) {
    parts.push(
      `L ${t.baseEnd.x} ${t.baseEnd.y}`,
      `L ${t.tip.x} ${t.tip.y}`,
      `L ${t.baseStart.x} ${t.baseStart.y}`,
    );
  }
  parts.push(
    `L ${x + r} ${y + height}`,
    `Q ${x} ${y + height} ${x} ${y + height - r}`,
  );

  if (side === MessageBubbleTailSide.Left && t !== undefined) {
    parts.push(
      `L ${t.baseEnd.x} ${t.baseEnd.y}`,
      `L ${t.tip.x} ${t.tip.y}`,
      `L ${t.baseStart.x} ${t.baseStart.y}`,
    );
  }
  parts.push(
    `L ${x} ${y + r}`,
    `Q ${x} ${y} ${x + r} ${y}`,
    'Z',
  );
  return parts.join(' ');
}

@Component
export struct MessageBubble {
  widthVp: number = 240;
  heightVp: number = 120;
  radiusVp: number = 18;
  borderWidthVp: number = 2;
  fillColor: ResourceColor = '#FFFDF6';
  strokeColor: ResourceColor = '#E7D7B6';
  padding: MessageBubblePadding = { left: 16, right: 16, top: 12, bottom: 12 };
  tail?: MessageBubbleTail;
  bubbleShadow?: MessageBubbleShadow;
  @BuilderParam content: () => void = this.defaultContent;

  @Builder
  defaultContent() {}

  build() {
    const frame: MessageBubbleFrame = messageBubbleFrame(this.widthVp, this.heightVp, this.tail);
    Stack() {
      Path()
        .width(frame.width)
        .height(frame.height)
        .commands(messageBubblePathCommands(
          this.widthVp,
          this.heightVp,
          this.radiusVp,
          this.tail,
        ))
        .fill(this.fillColor)
        .stroke(this.strokeColor)
        .strokeWidth(this.borderWidthVp)
        .shadow(this.bubbleShadow === undefined
          ? { radius: 0, color: '#00000000', offsetX: 0, offsetY: 0 }
          : this.bubbleShadow);
      Column() {
        this.content();
      }
      .width(this.widthVp)
      .height(this.heightVp)
      .position({ x: frame.offsetX, y: frame.offsetY })
      .padding({
        left: this.padding.left,
        right: this.padding.right,
        top: this.padding.top,
        bottom: this.padding.bottom,
      });
    }
    .width(frame.width)
    .height(frame.height)
    .hitTestBehavior(HitTestMode.None);
  }
}
```

- [ ] **Step 4: Run unit tests to verify green**

Run:

```bash
cd harmonyos && hvigorw -p module=entry@default test
```

Expected: PASS for geometry and component helper tests.

- [ ] **Step 5: Commit**

```bash
git add harmonyos/entry/src/main/ets/components/MessageBubble.ets harmonyos/entry/src/test/MessageBubble.test.ets harmonyos/entry/src/test/List.test.ets
git commit -m "feat(harmony): add reusable message bubble component"
```

## Task 3: Message Bubble Lab Page

**Files:**
- Create: `harmonyos/entry/src/main/ets/components/MessageBubbleLabState.ets`
- Create: `harmonyos/entry/src/test/MessageBubbleLabState.test.ets`
- Modify: `harmonyos/entry/src/test/List.test.ets`
- Create: `harmonyos/entry/src/main/ets/pages/MessageBubbleLabPage.ets`
- Modify: `harmonyos/entry/src/main/resources/base/profile/main_pages.json`
- Modify: `harmonyos/entry/src/main/ets/pages/DevMenuPage.ets`

The repo's HarmonyOS UI automation rules exclude DevMenu and the version-label triple-tap path, so this task uses local unit tests for Lab state and leaves DevMenu navigation to manual simulator verification in Task 4.

- [ ] **Step 1: Write the failing Lab state unit tests**

Create `harmonyos/entry/src/test/MessageBubbleLabState.test.ets`:

```ts
import { describe, it, expect } from '@ohos/hypium';
import {
  MessageBubbleLabState,
  createMessageBubbleLabState,
  labStateApplyPreset,
  labStateAdjustTip,
  labStateOutput,
} from '../main/ets/components/MessageBubbleLabState';
import { MessageBubbleTailPreset } from '../main/ets/components/MessageBubbleGeometry';

export default function messageBubbleLabStateTest() {
  describe('MessageBubbleLabState', () => {
    it('createsBottomRightDefaultStateWithVpOutput', 0, () => {
      const state: MessageBubbleLabState = createMessageBubbleLabState();
      const output: string = labStateOutput(state);

      expect(state.selectedPreset).assertEqual(MessageBubbleTailPreset.BottomRight);
      expect(output.indexOf('preset: BottomRight') >= 0).assertTrue();
      expect(output.indexOf('unit: vp') >= 0).assertTrue();
      expect(output.indexOf('baseStart') >= 0).assertTrue();
    });

    it('appliesPresetByReplacingTailCoordinates', 0, () => {
      const state: MessageBubbleLabState =
        labStateApplyPreset(createMessageBubbleLabState(), MessageBubbleTailPreset.TopMiddle);

      expect(state.selectedPreset).assertEqual(MessageBubbleTailPreset.TopMiddle);
      expect(state.tail.baseStart.y).assertEqual(0);
      expect(state.tail.baseEnd.y).assertEqual(0);
      expect(state.tail.tip.y < 0).assertTrue();
    });

    it('adjustsTipWithoutChangingBaseCoordinates', 0, () => {
      const state: MessageBubbleLabState = createMessageBubbleLabState();
      const changed: MessageBubbleLabState = labStateAdjustTip(state, 4, -8);

      expect(changed.tail.baseStart.x).assertEqual(state.tail.baseStart.x);
      expect(changed.tail.baseEnd.x).assertEqual(state.tail.baseEnd.x);
      expect(changed.tail.tip.x).assertEqual(state.tail.tip.x + 4);
      expect(changed.tail.tip.y).assertEqual(state.tail.tip.y - 8);
    });
  });
}
```

Modify `harmonyos/entry/src/test/List.test.ets`:

```ts
import messageBubbleLabStateTest from './MessageBubbleLabState.test';

export default function testsuite() {
  // keep existing registrations
  messageBubbleLabStateTest();
}
```

- [ ] **Step 2: Run the unit test to verify it fails**

Run:

```bash
cd harmonyos && hvigorw -p module=entry@default test
```

Expected: FAIL because `MessageBubbleLabState.ets` does not exist.

- [ ] **Step 3: Implement pure Lab state**

Create `harmonyos/entry/src/main/ets/components/MessageBubbleLabState.ets`:

```ts
import {
  MessageBubbleBox,
  MessageBubbleTail,
  MessageBubbleTailPreset,
  buildMessageBubbleTailPreset,
} from './MessageBubbleGeometry';

export interface MessageBubbleLabState {
  widthVp: number;
  heightVp: number;
  radiusVp: number;
  borderWidthVp: number;
  paddingX: number;
  paddingY: number;
  fillColor: string;
  strokeColor: string;
  selectedPreset: MessageBubbleTailPreset;
  tail: MessageBubbleTail;
}

export function messageBubbleLabBox(state: MessageBubbleLabState): MessageBubbleBox {
  return {
    width: state.widthVp,
    height: state.heightVp,
    borderWidth: state.borderWidthVp,
    tailBase: 56,
    tailLength: 56,
    inset: 38,
  };
}

export function createMessageBubbleLabState(): MessageBubbleLabState {
  const base: MessageBubbleLabState = {
    widthVp: 270,
    heightVp: 148,
    radiusVp: 18,
    borderWidthVp: 4,
    paddingX: 28,
    paddingY: 24,
    fillColor: '#EEE6FF',
    strokeColor: '#8B5CF6',
    selectedPreset: MessageBubbleTailPreset.BottomRight,
    tail: {
      baseStart: { x: 0, y: 0 },
      baseEnd: { x: 0, y: 0 },
      tip: { x: 0, y: 0 },
    },
  };
  return labStateApplyPreset(base, MessageBubbleTailPreset.BottomRight);
}

export function labStateApplyPreset(
  state: MessageBubbleLabState,
  preset: MessageBubbleTailPreset,
): MessageBubbleLabState {
  return {
    ...state,
    selectedPreset: preset,
    tail: buildMessageBubbleTailPreset(preset, messageBubbleLabBox(state)),
  };
}

export function labStateAdjustTip(
  state: MessageBubbleLabState,
  dx: number,
  dy: number,
): MessageBubbleLabState {
  return {
    ...state,
    tail: {
      baseStart: state.tail.baseStart,
      baseEnd: state.tail.baseEnd,
      tip: {
        x: state.tail.tip.x + dx,
        y: state.tail.tip.y + dy,
      },
    },
  };
}

export function labStateOutput(state: MessageBubbleLabState): string {
  return `preset: ${state.selectedPreset}
unit: vp
tail: {
  baseStart: { x: ${state.tail.baseStart.x}, y: ${state.tail.baseStart.y} },
  baseEnd: { x: ${state.tail.baseEnd.x}, y: ${state.tail.baseEnd.y} },
  tip: { x: ${state.tail.tip.x}, y: ${state.tail.tip.y} }
}`;
}
```

- [ ] **Step 4: Run unit tests to verify green**

Run:

```bash
cd harmonyos && hvigorw -p module=entry@default test
```

Expected: PASS for geometry, component helper, and Lab state tests.

- [ ] **Step 5: Implement MessageBubbleLabPage**

Create `harmonyos/entry/src/main/ets/pages/MessageBubbleLabPage.ets`:

```ts
import {
  MessageBubble,
  MessageBubblePadding,
} from '../components/MessageBubble';
import {
  MessageBubbleTailPreset,
} from '../components/MessageBubbleGeometry';
import {
  MessageBubbleLabState,
  createMessageBubbleLabState,
  labStateAdjustTip,
  labStateApplyPreset,
  labStateOutput,
} from '../components/MessageBubbleLabState';
import { requestPageOrientation } from '../utils/orientation';
import { common } from '@kit.AbilityKit';

const LAB_PRESETS: MessageBubbleTailPreset[] = [
  MessageBubbleTailPreset.TopLeft,
  MessageBubbleTailPreset.TopMiddle,
  MessageBubbleTailPreset.TopRight,
  MessageBubbleTailPreset.BottomLeft,
  MessageBubbleTailPreset.BottomMiddle,
  MessageBubbleTailPreset.BottomRight,
  MessageBubbleTailPreset.LeftTop,
  MessageBubbleTailPreset.LeftMiddle,
  MessageBubbleTailPreset.LeftBottom,
  MessageBubbleTailPreset.RightTop,
  MessageBubbleTailPreset.RightMiddle,
  MessageBubbleTailPreset.RightBottom,
];

@Entry
@Component
struct MessageBubbleLabPage {
  @State private state: MessageBubbleLabState = createMessageBubbleLabState();

  aboutToAppear(): void {
    requestPageOrientation(
      this.getUIContext().getHostContext() as common.UIAbilityContext,
      'MessageBubbleLabPage',
      (px: number): number => this.getUIContext().px2vp(px),
    );
  }

  private padding(): MessageBubblePadding {
    return {
      left: this.state.paddingX,
      right: this.state.paddingX,
      top: this.state.paddingY,
      bottom: this.state.paddingY,
    };
  }

  private applyPreset(preset: MessageBubbleTailPreset): void {
    this.state = labStateApplyPreset(this.state, preset);
  }

  private adjustTip(dx: number, dy: number): void {
    this.state = labStateAdjustTip(this.state, dx, dy);
  }

  private goBack(): void {
    this.getUIContext().getRouter().back();
  }

  @Builder
  private presetGrid() {
    Grid() {
      ForEach(LAB_PRESETS, (preset: MessageBubbleTailPreset) => {
        GridItem() {
          Button(preset)
            .id(`MessageBubbleLabPreset${preset}`)
            .fontSize(11)
            .height(34)
            .backgroundColor(this.state.selectedPreset === preset ? '#8B5CF6' : '#F5F0FF')
            .fontColor(this.state.selectedPreset === preset ? '#FFFFFF' : '#5B36D6')
            .onClick((): void => this.applyPreset(preset));
        }
      }, (preset: MessageBubbleTailPreset) => preset);
    }
    .columnsTemplate('1fr 1fr 1fr')
    .columnsGap(8)
    .rowsGap(8);
  }

  @Builder
  private preview() {
    Stack() {
      MessageBubble({
        widthVp: this.state.widthVp,
        heightVp: this.state.heightVp,
        radiusVp: this.state.radiusVp,
        borderWidthVp: this.state.borderWidthVp,
        fillColor: this.state.fillColor,
        strokeColor: this.state.strokeColor,
        padding: this.padding(),
        tail: this.state.tail,
        bubbleShadow: { radius: 12, color: '#22000000', offsetX: 0, offsetY: 4 },
      }) {
        Column({ space: 6 }) {
          Text('Fern Lizard')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor('#4B2E83');
          Text('My green clue darts away.')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor('#1D3557')
            .maxLines(2);
          Text('我的绿色线索飞跑。')
            .fontSize(13)
            .fontColor('#6E5F54');
        }
        .alignItems(HorizontalAlign.Center)
        .justifyContent(FlexAlign.Center)
        .width('100%')
        .height('100%');
      }
      .id('MessageBubbleLabPreview');
    }
    .width(420)
    .height(300)
    .borderRadius(16)
    .backgroundColor('#FAF8FF');
  }

  build() {
    Column({ space: 16 }) {
      Row() {
        Button('Back')
          .id('MessageBubbleLabBackButton')
          .height(36)
          .fontSize(14)
          .backgroundColor('#FFFFFF')
          .fontColor('#1D3557')
          .borderWidth(1)
          .borderColor('#B8D7F6')
          .onClick((): void => this.goBack());
        Text('Message Bubble Lab')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1D3557')
          .layoutWeight(1)
          .textAlign(TextAlign.Center);
        Blank().width(72);
      }
      .width('100%');

      Row({ space: 18 }) {
        this.preview();
        Column({ space: 12 }) {
          Text('Presets')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1D3557');
          this.presetGrid();
          Row({ space: 8 }) {
            Button('Tip X -')
              .id('MessageBubbleLabTipXMinus')
              .onClick((): void => this.adjustTip(-4, 0));
            Button('Tip X +')
              .id('MessageBubbleLabTipXPlus')
              .onClick((): void => this.adjustTip(4, 0));
            Button('Tip Y +')
              .id('MessageBubbleLabTipYPlus')
              .onClick((): void => this.adjustTip(0, 4));
          }
          .width('100%');
          Text(labStateOutput(this.state))
            .id('MessageBubbleLabOutput')
            .fontSize(12)
            .fontColor('#3B2A65')
            .fontFamily('monospace')
            .padding(12)
            .backgroundColor('#F4F0FF')
            .borderRadius(10)
            .width('100%');
        }
        .layoutWeight(1);
      }
      .width('100%')
      .layoutWeight(1);
    }
    .id('MessageBubbleLabPage')
    .width('100%')
    .height('100%')
    .padding(24)
    .backgroundColor('#FFFFFF');
  }
}
```

- [ ] **Step 6: Register the page route**

Modify `harmonyos/entry/src/main/resources/base/profile/main_pages.json` to include:

```json
"pages/MessageBubbleLabPage"
```

Place it after `"pages/DevMenuPage"` so debug-only routes stay grouped.

- [ ] **Step 7: Add DevMenu entry**

In `harmonyos/entry/src/main/ets/pages/DevMenuPage.ets`, add a private method:

```ts
private openMessageBubbleLab(): void {
  this.getUIContext().getRouter().pushUrl({ url: 'pages/MessageBubbleLabPage' })
    .catch((err: BusinessError): void => {
      console.error(`DevMenuPage.openMessageBubbleLab failed: ${JSON.stringify(err)}`);
    });
}
```

Add a button in the existing debug controls area:

```ts
Button('Message Bubble Lab')
  .id('DevMenuMessageBubbleLabButton')
  .height(44)
  .fontSize(16)
  .fontWeight(FontWeight.Bold)
  .fontColor('#1D3557')
  .backgroundColor('#F4F0FF')
  .borderRadius(12)
  .onClick((): void => this.openMessageBubbleLab());
```

- [ ] **Step 8: Run build and local tests to verify green**

Run:

```bash
cd harmonyos && hvigorw assembleHap
cd harmonyos && hvigorw -p module=entry@default test
```

Expected:

- HAP build succeeds with no `ArkTS:WARN` lines.
- Local unit tests pass, including `MessageBubbleLabState`.

- [ ] **Step 9: Commit**

```bash
git add harmonyos/entry/src/main/ets/components/MessageBubbleLabState.ets harmonyos/entry/src/test/MessageBubbleLabState.test.ets harmonyos/entry/src/test/List.test.ets harmonyos/entry/src/main/ets/pages/MessageBubbleLabPage.ets harmonyos/entry/src/main/resources/base/profile/main_pages.json harmonyos/entry/src/main/ets/pages/DevMenuPage.ets
git commit -m "feat(harmony): add message bubble lab page"
```

## Task 4: Visual Verification And Hardening

**Files:**
- Modify only if visual verification reveals build or layout issues:
  - `harmonyos/entry/src/main/ets/components/MessageBubble.ets`
  - `harmonyos/entry/src/main/ets/pages/MessageBubbleLabPage.ets`

- [ ] **Step 1: Install the app on simulator**

Run:

```bash
hdc install harmonyos/entry/build/default/outputs/default/entry-default-signed.hap
```

Expected: `install bundle successfully`.

- [ ] **Step 2: Open the Lab manually**

Use the app:

1. Launch app.
2. Triple-tap the version label to open Developer Options.
3. Tap `Message Bubble Lab`.
4. Tap `BottomRight`, `TopRight`, `LeftMiddle`, and `RightBottom`.
5. Tap `Tip X +` and `Tip Y +`.

- [ ] **Step 3: Capture simulator screenshot**

Run:

```bash
hdc shell "snapshot_display -f /data/local/tmp/message_bubble_lab.jpeg"
hdc file recv /data/local/tmp/message_bubble_lab.jpeg /private/tmp/message_bubble_lab.jpeg
```

Expected: `/private/tmp/message_bubble_lab.jpeg` shows the Lab page, live preview, presets, and output panel.

- [ ] **Step 4: Fix visual issues with a failing check first when possible**

If a visual issue is pure geometry, add or update a unit test in `MessageBubble.test.ets` before changing implementation. Example for a missing tail point:

```ts
it('includesRightSideTailPointsInPath', 0, () => {
  const tail: MessageBubbleTail = {
    baseStart: { x: 240, y: 28 },
    baseEnd: { x: 240, y: 64 },
    tip: { x: 284, y: 46 },
  };

  const commands: string = messageBubblePathCommands(240, 120, 18, tail);

  expect(commands.indexOf('L 240 64') >= 0).assertTrue();
  expect(commands.indexOf('L 284 46') >= 0).assertTrue();
  expect(commands.indexOf('L 240 28') >= 0).assertTrue();
});
```

Run:

```bash
cd harmonyos && hvigorw -p module=entry@default test
```

Expected: new test fails before the implementation change and passes after.

- [ ] **Step 5: Run final verification**

Run:

```bash
cd harmonyos && hvigorw assembleHap
cd harmonyos && codelinter -c ./code-linter.json5 . --fix
cd harmonyos && hvigorw -p module=entry@default test
git diff --check
```

Expected:

- Build succeeds.
- CodeLinter reports no defects.
- Local unit tests pass.
- `git diff --check` has no output.

- [ ] **Step 6: Commit final hardening if needed**

If Task 4 changed files:

```bash
git add harmonyos/entry/src/main/ets/components/MessageBubble.ets harmonyos/entry/src/main/ets/pages/MessageBubbleLabPage.ets harmonyos/entry/src/test/MessageBubble.test.ets
git commit -m "fix(harmony): polish message bubble lab rendering"
```

If Task 4 made no changes, do not create an empty commit.

## Execution Notes

- Run HarmonyOS build/test/install commands with sandbox escalation so DevEco SDK, `hdc`, local caches, and simulator access work.
- Keep the emulator running after install for human confirmation.
- Do not apply `MessageBubble` to `BattlePage` in this plan. That is a follow-up after the Lab makes the target shape easy to tune.
- If `hvigorw -p module=entry@default test` hangs because `oh_modules` is missing, run `cd harmonyos && ohpm install`, then rerun the test.
