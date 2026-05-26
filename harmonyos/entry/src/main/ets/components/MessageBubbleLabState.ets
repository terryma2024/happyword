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
  shadowEnabled: boolean;
  shadowRadius: number;
  shadowOffsetY: number;
  selectedPreset: MessageBubbleTailPreset;
  tail: MessageBubbleTail;
}

export type MessageBubbleTailPointKey = 'baseStart' | 'baseEnd' | 'tip';
export type MessageBubbleAxisKey = 'x' | 'y';
export type MessageBubbleBoxValueKey =
  'widthVp' | 'heightVp' | 'paddingX' | 'paddingY' | 'radiusVp' | 'borderWidthVp';
export type MessageBubbleVisualValueKey = 'shadowRadius' | 'shadowOffsetY';
export type MessageBubbleColorKey = 'fillColor' | 'strokeColor';

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

const FILL_PALETTE: string[] = ['#EEE6FF', '#FFFDF6', '#E8F4FF', '#FCEAEA', '#E8F8EE'];
const STROKE_PALETTE: string[] = ['#8B5CF6', '#E7D7B6', '#4A90E2', '#E63946', '#2E8B57'];

function clampMin(value: number, minValue: number): number {
  return Math.max(minValue, value);
}

function adjustPoint(point: MessageBubbleTail, pointKey: MessageBubbleTailPointKey, axisKey: MessageBubbleAxisKey, delta: number): void {
  if (pointKey === 'baseStart') {
    if (axisKey === 'x') {
      point.baseStart.x += delta;
    } else {
      point.baseStart.y += delta;
    }
  } else if (pointKey === 'baseEnd') {
    if (axisKey === 'x') {
      point.baseEnd.x += delta;
    } else {
      point.baseEnd.y += delta;
    }
  } else if (axisKey === 'x') {
    point.tip.x += delta;
  } else {
    point.tip.y += delta;
  }
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
    shadowEnabled: state.shadowEnabled,
    shadowRadius: state.shadowRadius,
    shadowOffsetY: state.shadowOffsetY,
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
    shadowEnabled: true,
    shadowRadius: 12,
    shadowOffsetY: 4,
    selectedPreset: MessageBubbleTailPreset.BottomRight,
    tail: {
      baseStart: { x: 0, y: 0 },
      baseEnd: { x: 0, y: 0 },
      tip: { x: 0, y: 0 },
    },
  };
  return labStateApplyPreset(base, MessageBubbleTailPreset.BottomRight);
}

export function labStateAdjustTailCoordinate(
  state: MessageBubbleLabState,
  pointKey: MessageBubbleTailPointKey,
  axisKey: MessageBubbleAxisKey,
  delta: number,
): MessageBubbleLabState {
  const tail: MessageBubbleTail = {
    baseStart: { x: state.tail.baseStart.x, y: state.tail.baseStart.y },
    baseEnd: { x: state.tail.baseEnd.x, y: state.tail.baseEnd.y },
    tip: { x: state.tail.tip.x, y: state.tail.tip.y },
  };
  adjustPoint(tail, pointKey, axisKey, delta);
  return copyWithTail(state, state.selectedPreset, tail);
}

export function labStateAdjustBoxValue(
  state: MessageBubbleLabState,
  key: MessageBubbleBoxValueKey,
  delta: number,
): MessageBubbleLabState {
  const next: MessageBubbleLabState = copyWithTail(state, state.selectedPreset, state.tail);
  if (key === 'widthVp') {
    next.widthVp = clampMin(next.widthVp + delta, 40);
  } else if (key === 'heightVp') {
    next.heightVp = clampMin(next.heightVp + delta, 40);
  } else if (key === 'paddingX') {
    next.paddingX = clampMin(next.paddingX + delta, 0);
  } else if (key === 'paddingY') {
    next.paddingY = clampMin(next.paddingY + delta, 0);
  } else if (key === 'radiusVp') {
    next.radiusVp = clampMin(next.radiusVp + delta, 0);
  } else {
    next.borderWidthVp = clampMin(next.borderWidthVp + delta, 0);
  }
  return next;
}

export function labStateAdjustVisualValue(
  state: MessageBubbleLabState,
  key: MessageBubbleVisualValueKey,
  delta: number,
): MessageBubbleLabState {
  const next: MessageBubbleLabState = copyWithTail(state, state.selectedPreset, state.tail);
  if (key === 'shadowRadius') {
    next.shadowRadius = clampMin(next.shadowRadius + delta, 0);
  } else {
    next.shadowOffsetY = clampMin(next.shadowOffsetY + delta, -80);
  }
  return next;
}

export function labStateToggleShadow(state: MessageBubbleLabState): MessageBubbleLabState {
  const next: MessageBubbleLabState = copyWithTail(state, state.selectedPreset, state.tail);
  next.shadowEnabled = !state.shadowEnabled;
  return next;
}

export function labStateCycleColor(
  state: MessageBubbleLabState,
  key: MessageBubbleColorKey,
): MessageBubbleLabState {
  const next: MessageBubbleLabState = copyWithTail(state, state.selectedPreset, state.tail);
  if (key === 'fillColor') {
    const currentIndex: number = FILL_PALETTE.indexOf(next.fillColor);
    next.fillColor = FILL_PALETTE[(currentIndex + 1) % FILL_PALETTE.length];
  } else {
    const currentIndex: number = STROKE_PALETTE.indexOf(next.strokeColor);
    next.strokeColor = STROKE_PALETTE[(currentIndex + 1) % STROKE_PALETTE.length];
  }
  return next;
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
