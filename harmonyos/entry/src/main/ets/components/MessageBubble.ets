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

export function scaleMessageBubbleTail(tail: MessageBubbleTail | undefined, scale: number): MessageBubbleTail | undefined {
  if (tail === undefined) {
    return undefined;
  }
  return {
    baseStart: { x: tail.baseStart.x * scale, y: tail.baseStart.y * scale },
    baseEnd: { x: tail.baseEnd.x * scale, y: tail.baseEnd.y * scale },
    tip: { x: tail.tip.x * scale, y: tail.tip.y * scale },
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
    parts.push(
      `L ${t.baseStart.x} ${t.baseStart.y}`,
      `L ${t.tip.x} ${t.tip.y}`,
      `L ${t.baseEnd.x} ${t.baseEnd.y}`,
    );
  }
  parts.push(
    `L ${x + width - r} ${y}`,
    `Q ${x + width} ${y} ${x + width} ${y + r}`,
  );

  if (side === MessageBubbleTailSide.Right && t !== undefined) {
    parts.push(
      `L ${t.baseStart.x} ${t.baseStart.y}`,
      `L ${t.tip.x} ${t.tip.y}`,
      `L ${t.baseEnd.x} ${t.baseEnd.y}`,
    );
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
  @Prop widthVp: number = 240;
  @Prop heightVp: number = 120;
  @Prop radiusVp: number = 18;
  @Prop borderWidthVp: number = 2;
  @Prop fillColor: ResourceColor = '#FFFDF6';
  @Prop strokeColor: ResourceColor = '#E7D7B6';
  @Prop contentPadding: MessageBubblePadding = { left: 16, right: 16, top: 12, bottom: 12 };
  @Prop tail: MessageBubbleTail | undefined = undefined;
  @Prop bubbleShadow: MessageBubbleShadow = { radius: 0, color: '#00000000', offsetX: 0, offsetY: 0 };
  @BuilderParam content: () => void = this.defaultContent;

  @Builder
  defaultContent() {}

  private frame(): MessageBubbleFrame {
    return messageBubbleFrame(this.widthVp, this.heightVp, this.tail);
  }

  private pathCommands(): string {
    const scale: number = this.getUIContext().vp2px(1);
    return messageBubblePathCommands(
      this.widthVp * scale,
      this.heightVp * scale,
      this.radiusVp * scale,
      scaleMessageBubbleTail(this.tail, scale),
    );
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Path()
        .width(this.frame().width)
        .height(this.frame().height)
        .commands(this.pathCommands())
        .fill(this.fillColor)
        .stroke(this.strokeColor)
        .strokeWidth(this.borderWidthVp)
        .shadow(this.bubbleShadow)
        .position({ x: 0, y: 0 });
      Column() {
        this.content();
      }
      .width(this.widthVp)
      .height(this.heightVp)
      .position({ x: this.frame().offsetX, y: this.frame().offsetY })
      .padding({
        left: this.contentPadding.left,
        right: this.contentPadding.right,
        top: this.contentPadding.top,
        bottom: this.contentPadding.bottom,
      });
    }
    .width(this.frame().width)
    .height(this.frame().height)
    .hitTestBehavior(HitTestMode.None);
  }
}
