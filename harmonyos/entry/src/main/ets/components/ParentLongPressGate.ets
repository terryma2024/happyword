const HOLD_DURATION_MS: number = 3000;
const TICK_MS: number = 33;
const PROGRESS_PER_TICK: number = TICK_MS / HOLD_DURATION_MS;
const RING_DIAMETER: number = 96;
const RING_CIRCUMFERENCE: number = Math.PI * RING_DIAMETER;

/**
 * ParentLongPressGate — circular progress dial that fires
 * `onConfirm` only after a continuous 3-second touch. Releasing
 * early resets progress to zero so accidental taps cannot
 * confirm. Visible label nudges the parent (the child should not
 * be able to clear the gate just by holding the button).
 */
@Component
export struct ParentLongPressGate {
  @Prop label: string = '长按 3 秒由家长确认';
  onConfirm: () => void = (): void => {};

  @State progress: number = 0;
  @State holding: boolean = false;
  private timer: number = -1;

  build(): void {
    Stack({ alignContent: Alignment.Center }) {
      Circle({ width: RING_DIAMETER, height: RING_DIAMETER })
        .fill('#FCEAEA');
      Circle({ width: RING_DIAMETER, height: RING_DIAMETER })
        .stroke('#E63946')
        .strokeWidth(6)
        .fillOpacity(0)
        .strokeDashArray([RING_CIRCUMFERENCE * this.progress, RING_CIRCUMFERENCE])
        .strokeLineCap(LineCapStyle.Round);
      Text(this.label)
        .id('ParentLongPressGateLabel')
        .fontSize(11)
        .fontColor('#E63946')
        .textAlign(TextAlign.Center)
        .padding(8);
    }
    .id('ParentLongPressGate')
    .width(RING_DIAMETER + 24)
    .height(RING_DIAMETER + 24)
    .onTouch((event: TouchEvent): void => {
      if (event.type === TouchType.Down) {
        this.startHold();
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.endHold();
      }
    });
  }

  aboutToDisappear(): void {
    this.clearTimer();
  }

  private startHold(): void {
    if (this.timer >= 0) {
      return;
    }
    this.holding = true;
    this.timer = setInterval((): void => {
      const next: number = this.progress + PROGRESS_PER_TICK;
      this.progress = next > 1 ? 1 : next;
      if (this.progress >= 1) {
        this.fireConfirm();
      }
    }, TICK_MS);
  }

  private endHold(): void {
    this.clearTimer();
    if (this.progress < 1) {
      this.progress = 0;
    }
    this.holding = false;
  }

  private fireConfirm(): void {
    this.clearTimer();
    this.holding = false;
    const cb: () => void = this.onConfirm;
    setTimeout((): void => {
      cb();
      this.progress = 0;
    }, 200);
  }

  private clearTimer(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }
}
