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
const RIBBON_COUNT: number = 10;
const RIBBON_FLY_RADIUS: number = 90;
const RIBBON_GRAVITY_DROP: number = 120;
const RIBBON_PHASE1_MS: number = 300;
const RIBBON_PHASE2_MS: number = 600;
const RIBBON_CLEAR_DELAY_MS: number = 900;

@Component
struct GiftBoxRibbon {
  @Prop angleDeg: number = 0;
  @Prop color: string = '#E63946';
  @Prop index: number = 0;

  @State private tx: number = 0;
  @State private ty: number = 0;
  @State private opacityValue: number = 1;

  private phase2Timer: number = 0;

  aboutToAppear(): void {
    const angleRad: number = this.angleDeg * Math.PI / 180;
    const flyX: number = Math.cos(angleRad) * RIBBON_FLY_RADIUS;
    const flyY: number = Math.sin(angleRad) * RIBBON_FLY_RADIUS;

    animateTo({ duration: RIBBON_PHASE1_MS, curve: Curve.EaseOut }, () => {
      this.tx = flyX;
      this.ty = flyY;
    });

    this.phase2Timer = setTimeout(() => {
      animateTo({ duration: RIBBON_PHASE2_MS, curve: Curve.EaseIn }, () => {
        this.ty = flyY + RIBBON_GRAVITY_DROP;
        this.opacityValue = 0;
      });
    }, RIBBON_PHASE1_MS);
  }

  aboutToDisappear(): void {
    if (this.phase2Timer !== 0) {
      clearTimeout(this.phase2Timer);
      this.phase2Timer = 0;
    }
  }

  build(): void {
    Column()
      .id(`GiftBoxRibbon${this.index}`)
      .width(10)
      .height(18)
      .borderRadius(3)
      .backgroundColor(this.color)
      .translate({ x: this.tx, y: this.ty })
      .opacity(this.opacityValue);
  }
}

@Component
export struct GiftBox {
  @Prop @Watch('onTriggerChanged') trigger: number = 0;

  @State private isOpen: boolean = false;
  @State private lidTy: number = 0;
  @State private lidRotate: number = 0;
  @State private boxScale: number = 1;
  @State private ribbons: Ribbon[] = [];

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
    this.ribbons = [];
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

    // Spawn ribbons — each one animates itself in its own aboutToAppear.
    this.ribbons = generateRibbons(RIBBON_COUNT);

    // Retire ribbons after both animation phases complete.
    this.scheduleTimer(() => {
      this.ribbons = [];
    }, RIBBON_CLEAR_DELAY_MS);

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

      ForEach(
        this.ribbons,
        (r: Ribbon) => {
          GiftBoxRibbon({ angleDeg: r.angleDeg, color: r.color, index: r.id });
        },
        (r: Ribbon) => r.id.toString()
      );
    }
    .id('GiftBoxContainer')
    .width(132)
    .height(120)
    .scale({ x: this.boxScale, y: this.boxScale });
  }
}
