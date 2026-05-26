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

export interface MessageBubbleLabTipAction {
  id: string;
  label: string;
  dx: number;
  dy: number;
}

export function messageBubbleLabTipActions(): MessageBubbleLabTipAction[] {
  return [
    { id: 'MessageBubbleLabTipXMinus', label: 'Tip X -', dx: -4, dy: 0 },
    { id: 'MessageBubbleLabTipXPlus', label: 'Tip X +', dx: 4, dy: 0 },
    { id: 'MessageBubbleLabTipYMinus', label: 'Tip Y -', dx: 0, dy: -4 },
    { id: 'MessageBubbleLabTipYPlus', label: 'Tip Y +', dx: 0, dy: 4 },
  ];
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

function copyWithTail(
  state: MessageBubbleLabState,
  selectedPreset: MessageBubbleTailPreset,
  tail: MessageBubbleTail,
): MessageBubbleLabState {
  return {
    widthVp: state.widthVp,
    heightVp: state.heightVp,
    radiusVp: state.radiusVp,
    borderWidthVp: state.borderWidthVp,
    paddingX: state.paddingX,
    paddingY: state.paddingY,
    fillColor: state.fillColor,
    strokeColor: state.strokeColor,
    selectedPreset,
    tail,
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
  return copyWithTail(
    state,
    preset,
    buildMessageBubbleTailPreset(preset, messageBubbleLabBox(state)),
  );
}

export function labStateAdjustTip(
  state: MessageBubbleLabState,
  dx: number,
  dy: number,
): MessageBubbleLabState {
  return copyWithTail(
    state,
    state.selectedPreset,
    {
      baseStart: state.tail.baseStart,
      baseEnd: state.tail.baseEnd,
      tip: {
        x: state.tail.tip.x + dx,
        y: state.tail.tip.y + dy,
      },
    },
  );
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
