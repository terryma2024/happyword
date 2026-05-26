import { describe, it, expect } from '@ohos/hypium';
import {
  MessageBubbleLabState,
  createMessageBubbleLabState,
  messageBubbleLabTipActions,
  labStateAdjustBoxValue,
  labStateAdjustTailCoordinate,
  labStateAdjustVisualValue,
  labStateApplyPreset,
  labStateAdjustTip,
  labStateCycleColor,
  labStateOutput,
  labStateStepperValue,
  labStateToggleShadow,
  MessageBubbleLabTipAction,
} from '../main/ets/components/MessageBubbleLabState';
import { MessageBubbleTailPreset } from '../main/ets/components/MessageBubbleGeometry';

export default function messageBubbleLabStateTest() {
  describe('MessageBubbleLabState', () => {
    it('createsBottomRightDefaultStateWithVpOutput', 0, () => {
      const state: MessageBubbleLabState = createMessageBubbleLabState();
      const output: string = labStateOutput(state);

      expect(state.selectedPreset).assertEqual(MessageBubbleTailPreset.BottomRight);
      expect(state.widthVp).assertEqual(224);
      expect(state.heightVp).assertEqual(96);
      expect(state.borderWidthVp).assertEqual(1);
      expect(state.paddingX).assertEqual(10);
      expect(state.fillColor).assertEqual('#FFFDF6');
      expect(state.strokeColor).assertEqual('#E7D7B6');
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

    it('includesNegativeYTipActionForTheLabControls', 0, () => {
      const actions: MessageBubbleLabTipAction[] = messageBubbleLabTipActions();
      const tipYMinus: MessageBubbleLabTipAction | undefined =
        actions.find((action: MessageBubbleLabTipAction): boolean => action.id === 'MessageBubbleLabTipYMinus');

      expect(actions.length).assertEqual(4);
      expect(tipYMinus?.label).assertEqual('Tip Y -');
      expect(tipYMinus?.dx).assertEqual(0);
      expect(tipYMinus?.dy).assertEqual(-4);
    });

    it('adjustsAnyTailCoordinateByPointAndAxis', 0, () => {
      const state: MessageBubbleLabState = createMessageBubbleLabState();
      const changed: MessageBubbleLabState = labStateAdjustTailCoordinate(state, 'baseStart', 'x', 6);

      expect(changed.tail.baseStart.x).assertEqual(state.tail.baseStart.x + 6);
      expect(changed.tail.baseStart.y).assertEqual(state.tail.baseStart.y);
      expect(changed.tail.baseEnd.x).assertEqual(state.tail.baseEnd.x);
      expect(changed.tail.tip.x).assertEqual(state.tail.tip.x);
    });

    it('readsUpdatedStepperValuesFromCurrentState', 0, () => {
      const state: MessageBubbleLabState = createMessageBubbleLabState();
      const changed: MessageBubbleLabState = labStateAdjustTailCoordinate(state, 'tip', 'x', 6);

      expect(labStateStepperValue(state, 'tipX')).assertEqual(`${state.tail.tip.x}`);
      expect(labStateStepperValue(changed, 'tipX')).assertEqual(`${state.tail.tip.x + 6}`);
      expect(labStateStepperValue(changed, 'widthVp')).assertEqual(`${state.widthVp}`);
    });

    it('adjustsShadowXAsAVisibleStepperValue', 0, () => {
      const state: MessageBubbleLabState = createMessageBubbleLabState();
      const shifted: MessageBubbleLabState = labStateAdjustVisualValue(state, 'shadowOffsetX', -3);

      expect(state.shadowOffsetX).assertEqual(0);
      expect(shifted.shadowOffsetX).assertEqual(-3);
      expect(labStateStepperValue(shifted, 'shadowOffsetX')).assertEqual('-3');
      expect(labStateOutput(shifted).indexOf('offsetX: -3') >= 0).assertTrue();
    });

    it('adjustsBubbleBoxValuesWithLowerBounds', 0, () => {
      const state: MessageBubbleLabState = createMessageBubbleLabState();
      const wider: MessageBubbleLabState = labStateAdjustBoxValue(state, 'widthVp', 10);
      const tinyRadius: MessageBubbleLabState = labStateAdjustBoxValue(state, 'radiusVp', -999);
      const tinyPadding: MessageBubbleLabState = labStateAdjustBoxValue(state, 'paddingX', -999);

      expect(wider.widthVp).assertEqual(state.widthVp + 10);
      expect(tinyRadius.radiusVp).assertEqual(0);
      expect(tinyPadding.paddingX).assertEqual(0);
    });

    it('adjustsVisualValuesAndCyclesPalette', 0, () => {
      const state: MessageBubbleLabState = createMessageBubbleLabState();
      const shadowMoved: MessageBubbleLabState = labStateAdjustVisualValue(state, 'shadowOffsetY', 2);
      const noShadow: MessageBubbleLabState = labStateToggleShadow(state);
      const nextFill: MessageBubbleLabState = labStateCycleColor(state, 'fillColor');

      expect(shadowMoved.shadowOffsetY).assertEqual(state.shadowOffsetY + 2);
      expect(noShadow.shadowEnabled).assertFalse();
      expect(nextFill.fillColor === state.fillColor).assertFalse();
    });
  });
}
