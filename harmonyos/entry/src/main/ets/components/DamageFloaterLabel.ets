import { UIContext } from '@kit.ArkUI';

/** Visual tokens for a single HP damage floater (V0.8.3 §6.5). */
export class DamageFloaterStyle {
  text: string = '-1';
  color: string = '#F87171';
  fontSize: number = 18;
  hasStroke: boolean = true;
  shadowRadius: number = 0;
  shadowColor: string = '#00000000';
}

const FLOATER_DURATION_MS: number = 450;

export function pickFloaterStyle(amount: number): DamageFloaterStyle {
  const style: DamageFloaterStyle = new DamageFloaterStyle();
  if (amount === 2) {
    style.text = '-2';
    style.color = '#7F1D1D';
    style.fontSize = 20;
    style.hasStroke = false;
    style.shadowRadius = 2;
    style.shadowColor = '#00000066';
    return style;
  }
  style.text = '-1';
  style.color = '#F87171';
  style.fontSize = 18;
  style.hasStroke = true;
  style.shadowRadius = 0;
  style.shadowColor = '#00000000';
  return style;
}

/**
 * Short-lived "-1" / "-2" label that rises above a battle character card.
 * Parent owns queueing; this component only animates and calls onDispose.
 */
@Component
export struct DamageFloaterLabel {
  @Prop amount: number = 1;
  /** Extra upward offset when multiple floaters stack on one side. */
  @Prop stackOffsetVp: number = 0;
  /** Stable id for UiTest; parent assigns the topmost floater's id. */
  @Prop labelId: string = 'DamageFloaterLabelText';
  onDispose: () => void = (): void => {};

  @State private labelOpacity: number = 0;
  @State private labelTranslateY: number = 0;

  private timers: number[] = [];

  aboutToAppear(): void {
    this.playAnimation();
  }

  aboutToDisappear(): void {
    for (let i: number = 0; i < this.timers.length; i++) {
      clearTimeout(this.timers[i]);
    }
    this.timers = [];
  }

  private scheduleTimer(cb: () => void, delayMs: number): void {
    const id: number = setTimeout(cb, delayMs);
    this.timers.push(id);
  }

  private playAnimation(): void {
    const ui: UIContext = this.getUIContext();
    const halfMs: number = Math.floor(FLOATER_DURATION_MS / 2);

    ui.animateTo({ duration: 0 }, () => {
      this.labelOpacity = 0;
      this.labelTranslateY = 0;
    });

    ui.animateTo({ duration: halfMs, curve: Curve.EaseOut }, () => {
      this.labelOpacity = 1;
      this.labelTranslateY = -14 - this.stackOffsetVp;
    });

    this.scheduleTimer((): void => {
      this.getUIContext().animateTo({ duration: FLOATER_DURATION_MS - halfMs, curve: Curve.EaseOut }, () => {
        this.labelOpacity = 0;
        this.labelTranslateY = -28 - this.stackOffsetVp;
      });
    }, halfMs);

    this.scheduleTimer((): void => {
      this.onDispose();
    }, FLOATER_DURATION_MS);
  }

  private resolvedStyle(): DamageFloaterStyle {
    return pickFloaterStyle(this.amount);
  }

  build() {
    Column() {
      Text(this.resolvedStyle().text)
        .id(this.labelId)
        .fontSize(this.resolvedStyle().fontSize)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.resolvedStyle().color)
        .opacity(this.labelOpacity)
        .translate({ y: this.labelTranslateY })
        .textShadow({
          radius: this.resolvedStyle().hasStroke ? 1 : this.resolvedStyle().shadowRadius,
          color: this.resolvedStyle().hasStroke ? '#FFFFFF' : this.resolvedStyle().shadowColor,
          offsetX: 0,
          offsetY: this.resolvedStyle().hasStroke ? 0 : 1,
        });
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .hitTestBehavior(HitTestMode.None);
  }
}
