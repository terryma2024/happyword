/**
 * HpBar renders a labelled horizontal bar with a numeric "current / max" readout.
 *
 * Exposed as a reusable component per spec §7.3 so that both player and
 * monster character cards (and potentially other callers) share one visual
 * language. The bar colour shifts green → yellow → red as HP drops so a child
 * can read their state at a glance without counting numbers.
 *
 * The component is purely presentational — it owns no state and performs no
 * clamping side-effects on its inputs. Callers are responsible for supplying
 * non-negative values; defensive clamping here would just hide bugs upstream.
 */
@Component
export struct HpBar {
  @Prop current: number = 0;
  @Prop max: number = 1;
  label: string = 'HP';

  // Three colour tiers: full/medium/low. Thresholds chosen so the bar turns
  // yellow once the player has lost about a third of their HP and red once
  // they are near death.
  private static readonly COLOR_FULL: string = '#2ECC71';
  private static readonly COLOR_MID: string = '#F1C40F';
  private static readonly COLOR_LOW: string = '#E74C3C';
  private static readonly COLOR_TRACK: string = '#E0E0E0';

  private fillRatio(): number {
    if (this.max <= 0) {
      return 0;
    }
    const ratio: number = this.current / this.max;
    if (ratio < 0) {
      return 0;
    }
    if (ratio > 1) {
      return 1;
    }
    return ratio;
  }

  private barColor(): string {
    const ratio: number = this.fillRatio();
    if (ratio >= 0.6) {
      return HpBar.COLOR_FULL;
    }
    if (ratio >= 0.3) {
      return HpBar.COLOR_MID;
    }
    return HpBar.COLOR_LOW;
  }

  build() {
    Column() {
      // Numeric readout — exposes the exact strings that UI tests assert
      // (e.g. "HP 5 / 5"), decoupled from the visual bar so tests never need
      // to inspect fill widths or colours.
      Text(`${this.label} ${this.current} / ${this.max}`)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor('#1D3557');

      // Visual bar: a full-width track with a coloured fill clipped to the
      // current ratio. Using percentage width on the fill keeps the bar
      // responsive to its parent without hard-coding pixel sizes.
      Stack({ alignContent: Alignment.Start }) {
        Row()
          .width('100%')
          .height(10)
          .backgroundColor(HpBar.COLOR_TRACK)
          .borderRadius(5);
        Row()
          .width(`${this.fillRatio() * 100}%`)
          .height(10)
          .backgroundColor(this.barColor())
          .borderRadius(5);
      }
      .width('100%')
      .height(10)
      .margin({ top: 4 });
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start);
  }
}
