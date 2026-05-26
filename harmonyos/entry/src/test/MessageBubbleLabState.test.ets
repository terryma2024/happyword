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
