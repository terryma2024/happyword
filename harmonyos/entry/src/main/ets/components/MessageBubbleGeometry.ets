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
  tipInset?: number;
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

function horizontalTipX(preset: MessageBubbleTailPreset, box: MessageBubbleBox, baseStart: number): number {
  const tipInset: number = box.tipInset ?? 0;
  if (preset === MessageBubbleTailPreset.TopLeft ||
    preset === MessageBubbleTailPreset.BottomLeft) {
    return tipInset;
  }
  if (preset === MessageBubbleTailPreset.TopRight ||
    preset === MessageBubbleTailPreset.BottomRight) {
    return box.width - tipInset;
  }
  return baseStart + box.tailBase / 2;
}

function verticalTipY(preset: MessageBubbleTailPreset, box: MessageBubbleBox, baseStart: number): number {
  const tipInset: number = box.tipInset ?? 0;
  if (preset === MessageBubbleTailPreset.LeftTop ||
    preset === MessageBubbleTailPreset.RightTop) {
    return tipInset;
  }
  if (preset === MessageBubbleTailPreset.LeftBottom ||
    preset === MessageBubbleTailPreset.RightBottom) {
    return box.height - tipInset;
  }
  return baseStart + box.tailBase / 2;
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
      tip: { x: horizontalTipX(preset, box, startX), y: -box.tailLength },
    };
  }
  if (preset.indexOf('Bottom') === 0) {
    const startX: number = horizontalBaseStart(preset, box);
    return {
      baseStart: { x: startX, y: box.height },
      baseEnd: { x: startX + box.tailBase, y: box.height },
      tip: { x: horizontalTipX(preset, box, startX), y: box.height + box.tailLength },
    };
  }
  if (preset.indexOf('Left') === 0) {
    const startY: number = verticalBaseStart(preset, box);
    return {
      baseStart: { x: 0, y: startY },
      baseEnd: { x: 0, y: startY + box.tailBase },
      tip: { x: -box.tailLength, y: verticalTipY(preset, box, startY) },
    };
  }
  const startY: number = verticalBaseStart(preset, box);
  return {
    baseStart: { x: box.width, y: startY },
    baseEnd: { x: box.width, y: startY + box.tailBase },
    tip: { x: box.width + box.tailLength, y: verticalTipY(preset, box, startY) },
  };
}
