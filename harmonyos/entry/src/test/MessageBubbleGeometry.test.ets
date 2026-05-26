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
