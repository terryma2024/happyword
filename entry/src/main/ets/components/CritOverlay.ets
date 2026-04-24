import { UIContext } from '@kit.ArkUI';

/**
 * CritOverlay renders the two full-screen crit-spectacle layers that
 * don't belong on CharacterCard (spec §4.3 V0.2):
 *
 *   1. Gold screen flash — a full-bleed overlay faded 0 → 0.55 → 0
 *      over 450 ms (`id('CritGoldFlash')`).
 *   2. Big floating damage number — "-${damage}!" at 72 vp, anchored
 *      above the monster card and animated translateY 0 → -60,
 *      opacity 0 → 1 → 0, scale 0.6 → 1.2 → 1.0 over 700 ms
 *      (`id('CritDamageNumber')`).
 *
 * The zoom on the monster card and the player-casting glow live on
 * CharacterCard (driven by zoomPulse / castPulse) so the crit
 * animation stays attached to the character itself.
 *
 * BattlePage drives this overlay by incrementing `critPulse`. Each
 * observed change plays the full 700 ms timeline. `damage` is read at
 * pulse time so the label reflects the actual outcome.damage (the
 * engine deals 2× on burst).
 */

const FLASH_FADE_IN_MS: number = 120;
const FLASH_HOLD_MS: number = 120;
const FLASH_FADE_OUT_MS: number = 210;
const NUMBER_IN_MS: number = 260;
const NUMBER_HOLD_MS: number = 180;
const NUMBER_OUT_MS: number = 260;

@Component
export struct CritOverlay {
  /** Monotonically-increasing trigger. BattlePage bumps it on crit. */
  @Prop @Watch('onCritPulseChanged') critPulse: number = 0;
  /** Damage number to render inside `-${damage}!` — read at pulse time. */
  @Prop damage: number = 2;

  @State private flashOpacity: number = 0;
  @State private numberOpacity: number = 0;
  @State private numberTranslateY: number = 0;
  @State private numberScale: number = 0.6;
  @State private visible: boolean = false;

  private timers: number[] = [];

  aboutToDisappear(): void {
    for (let i = 0; i < this.timers.length; i++) {
      clearTimeout(this.timers[i]);
    }
    this.timers = [];
  }

  private scheduleTimer(cb: () => void, delayMs: number): void {
    const id: number = setTimeout(cb, delayMs);
    this.timers.push(id);
  }

  private onCritPulseChanged(): void {
    if (this.critPulse <= 0) {
      return;
    }
    const ui: UIContext = this.getUIContext();

    // Reset everything to the starting frame — in case a previous
    // animation is still mid-flight we snap back to zero before the
    // new animateTo queue begins.
    this.flashOpacity = 0;
    this.numberOpacity = 0;
    this.numberTranslateY = 0;
    this.numberScale = 0.6;
    this.visible = true;

    // Gold flash: in, hold, out.
    ui.animateTo({ duration: FLASH_FADE_IN_MS, curve: Curve.EaseOut }, () => {
      this.flashOpacity = 0.55;
    });
    this.scheduleTimer((): void => {
      this.getUIContext().animateTo({ duration: FLASH_FADE_OUT_MS, curve: Curve.EaseIn }, () => {
        this.flashOpacity = 0;
      });
    }, FLASH_FADE_IN_MS + FLASH_HOLD_MS);

    // Big damage number: scale up + fade in, hold, float up + fade out.
    ui.animateTo({ duration: NUMBER_IN_MS, curve: Curve.EaseOut }, () => {
      this.numberOpacity = 1;
      this.numberScale = 1.2;
      this.numberTranslateY = -20;
    });
    this.scheduleTimer((): void => {
      this.getUIContext().animateTo({ duration: NUMBER_HOLD_MS, curve: Curve.EaseInOut }, () => {
        this.numberScale = 1.0;
        this.numberTranslateY = -40;
      });
    }, NUMBER_IN_MS);
    this.scheduleTimer((): void => {
      this.getUIContext().animateTo({ duration: NUMBER_OUT_MS, curve: Curve.EaseIn }, () => {
        this.numberOpacity = 0;
        this.numberTranslateY = -60;
      });
    }, NUMBER_IN_MS + NUMBER_HOLD_MS);

    // Tear down the visible marker after the full timeline. Keeps the
    // overlay absent from the a11y tree at rest so UI tests can assert
    // "no CritGoldFlash id while idle" unambiguously.
    const total: number = NUMBER_IN_MS + NUMBER_HOLD_MS + NUMBER_OUT_MS;
    this.scheduleTimer((): void => {
      this.visible = false;
    }, total + 40);
  }

  build(): void {
    Stack() {
      // Full-bleed gold flash. Always mounted (opacity 0 at rest) so
      // the `CritGoldFlash` id is addressable by UiTest as soon as the
      // crit animation begins — ArkUI's visibility matcher treats a
      // conditionally-mounted Column (via `if (visible)`) as "not
      // visible" during the brief window UiTest samples, even though
      // the node exists in the frame buffer. Opacity alone is enough
      // to hide it at rest visually.
      Column()
        .id('CritGoldFlash')
        .width('100%')
        .height('100%')
        .backgroundColor('#FFB400')
        .opacity(this.flashOpacity);

      // Big floating damage number. Same always-mounted reasoning:
      // the opacity drops to 0 at rest so the big number is
      // imperceptible off-crit, but the id stays in the tree for
      // UiTest to assert on.
      Column() {
        Text(`-${this.damage}!`)
          .id('CritDamageNumber')
          .fontSize(72)
          .fontWeight(FontWeight.Bold)
          .fontColor('#E63946')
          .opacity(this.numberOpacity)
          .scale({ x: this.numberScale, y: this.numberScale })
          .translate({ x: 0, y: this.numberTranslateY });
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center);
    }
    // hitTestBehavior passthrough so the overlay never swallows taps
    // meant for the option buttons beneath it.
    .hitTestBehavior(HitTestMode.Transparent)
    .width('100%')
    .height('100%');
  }
}
