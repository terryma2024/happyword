export const RIBBON_COLORS: string[] = ['#E63946', '#F4C430', '#457B9D', '#F78DA7'];

export class Ribbon {
  id: number = 0;
  angleDeg: number = 0;
  color: string = '#E63946';
}

/**
 * Deterministic — no Math.random(). Same `count` always produces the same output
 * so that unit tests are stable.
 *
 * Angles are evenly spaced around the circle (i * 360/count) with a small
 * deterministic jitter derived from `i`. Colors cycle through RIBBON_COLORS.
 */
export function generateRibbons(count: number): Ribbon[] {
  const out: Ribbon[] = [];
  if (count <= 0) {
    return out;
  }
  const step: number = 360 / count;
  for (let i = 0; i < count; i++) {
    const jitter: number = ((i * 37) % 21) - 10;
    const r: Ribbon = new Ribbon();
    r.id = i;
    r.angleDeg = i * step + jitter;
    r.color = RIBBON_COLORS[i % RIBBON_COLORS.length];
    out.push(r);
  }
  return out;
}

const BOX_BODY_RED: string = '#E63946';
const BOX_RIBBON_GOLD: string = '#F4C430';
const AUTO_CLOSE_DELAY_MS: number = 1500;

@Component
export struct GiftBox {
  @Prop @Watch('onTriggerChanged') trigger: number = 0;

  @State private isOpen: boolean = false;
  @State private lidTy: number = 0;
  @State private lidRotate: number = 0;
  @State private boxScale: number = 1;

  private timers: number[] = [];

  aboutToDisappear(): void {
    this.clearAllTimers();
  }

  private clearAllTimers(): void {
    for (let i = 0; i < this.timers.length; i++) {
      clearTimeout(this.timers[i]);
    }
    this.timers = [];
  }

  private scheduleTimer(cb: () => void, delayMs: number): void {
    const id: number = setTimeout(() => {
      cb();
    }, delayMs);
    this.timers.push(id);
  }

  private onTriggerChanged(): void {
    // Cancel any in-flight cycle and restart from closed.
    this.clearAllTimers();
    this.isOpen = false;
    this.lidTy = 0;
    this.lidRotate = 0;
    this.boxScale = 1;
    this.startCycle();
  }

  private startCycle(): void {
    this.isOpen = true;

    // Scale bounce: 1 -> 1.08 -> 1 over 200 ms total.
    animateTo({ duration: 100, curve: Curve.EaseOut }, () => {
      this.boxScale = 1.08;
    });
    this.scheduleTimer(() => {
      animateTo({ duration: 100, curve: Curve.EaseIn }, () => {
        this.boxScale = 1;
      });
    }, 100);

    // Lid off.
    animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
      this.lidTy = -40;
      this.lidRotate = -15;
    });

    // Auto-close.
    this.scheduleTimer(() => {
      this.isOpen = false;
      animateTo({ duration: 180, curve: Curve.EaseInOut }, () => {
        this.lidTy = 0;
        this.lidRotate = 0;
      });
    }, AUTO_CLOSE_DELAY_MS);
  }

  build(): void {
    Stack() {
      // Body.
      Stack() {
        Column()
          .width(120)
          .height(80)
          .borderRadius(8)
          .backgroundColor(BOX_BODY_RED);
        Column()
          .width(8)
          .height(80)
          .backgroundColor(BOX_RIBBON_GOLD);
      }
      .width(120)
      .height(80)
      .alignContent(Alignment.Bottom);

      // Lid group.
      Stack() {
        Column()
          .width(132)
          .height(32)
          .borderRadius(6)
          .backgroundColor(BOX_BODY_RED);
        Row() {
          Column()
            .width(24)
            .height(10)
            .borderRadius(5)
            .backgroundColor(BOX_RIBBON_GOLD)
            .rotate({ angle: 25 });
          Column()
            .width(24)
            .height(10)
            .borderRadius(5)
            .backgroundColor(BOX_RIBBON_GOLD)
            .rotate({ angle: -25 });
        }
        .width(56)
        .justifyContent(FlexAlign.Center);
      }
      .id('GiftBoxLid')
      .width(132)
      .height(32)
      .offset({ x: 0, y: -64 })
      .translate({ x: 0, y: this.lidTy })
      .rotate({ angle: this.lidRotate });

      // Invisible marker node — stable hook for UI tests.
      if (this.isOpen) {
        Text('')
          .id('GiftBoxOpenMarker')
          .width(1)
          .height(1)
          .opacity(0);
      }
    }
    .id('GiftBoxContainer')
    .width(132)
    .height(120)
    .scale({ x: this.boxScale, y: this.boxScale });
  }
}
