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
