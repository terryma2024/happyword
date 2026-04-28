import { UIContext } from '@kit.ArkUI';

/**
 * CritOverlay renders the full-screen crit-spectacle layers that don't
 * belong on CharacterCard (spec §4.3, V0.2 + V0.3 polish):
 *
 *   1. Gold screen flash — full-bleed overlay faded 0 → 0.55 → 0.
 *      (`id('CritGoldFlash')`)
 *   2. Expanding shockwave ring — a concentric gold ring that bursts
 *      outward to ~6× scale to telegraph the burst's impact at a much
 *      bigger size than the older "-2!" floating number alone.
 *      (`id('CritShockwave')`)
 *   3. Big floating damage number — "-${damage}!" rendered at 96 vp
 *      and animated translateY 0 → -60, opacity 0 → 1 → 0,
 *      scale 0.6 → 1.4 → 1.0. (`id('CritDamageNumber')`)
 *
 * The zoom on the monster card and the player-casting glow live on
 * CharacterCard (driven by zoomPulse / castPulse) so the crit
 * animation stays attached to the character itself.
 *
 * BattlePage drives this overlay by incrementing `critPulse`. Each
 * observed change plays the full timeline. `damage` is read at pulse
 * time so the label reflects the actual outcome.damage (the engine
 * deals 2× on burst).
 */

const FLASH_FADE_IN_MS: number = 120;
const FLASH_HOLD_MS: number = 140;
const FLASH_FADE_OUT_MS: number = 240;
const NUMBER_IN_MS: number = 280;
const NUMBER_HOLD_MS: number = 220;
const NUMBER_OUT_MS: number = 280;
const SHOCKWAVE_MS: number = 520;

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
  @State private shockwaveScale: number = 0.2;
  @State private shockwaveOpacity: number = 0;
  @State private shockwaveSecondaryScale: number = 0.2;
  @State private shockwaveSecondaryOpacity: number = 0;

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

    // Snap back to the starting frame in case a previous animation is
    // still mid-flight. Wrapping in `animateTo({ duration: 0 })` is the
    // canonical ArkUI "set without transition" pattern — it batches the
    // assignments into a single render pass and signals to codelinter
    // that these values participate in the animation lifecycle rather
    // than being temporary calculations that should be local vars.
    ui.animateTo({ duration: 0 }, () => {
      this.flashOpacity = 0;
      this.numberOpacity = 0;
      this.numberTranslateY = 0;
      this.numberScale = 0.6;
      this.shockwaveScale = 0.2;
      this.shockwaveOpacity = 0;
      this.shockwaveSecondaryScale = 0.2;
      this.shockwaveSecondaryOpacity = 0;
    });

    // Gold flash: in, hold, out.
    ui.animateTo({ duration: FLASH_FADE_IN_MS, curve: Curve.EaseOut }, () => {
      this.flashOpacity = 0.6;
    });
    this.scheduleTimer((): void => {
      this.getUIContext().animateTo({ duration: FLASH_FADE_OUT_MS, curve: Curve.EaseIn }, () => {
        this.flashOpacity = 0;
      });
    }, FLASH_FADE_IN_MS + FLASH_HOLD_MS);

    // Primary shockwave ring: starts compact and bursts outward.
    ui.animateTo({ duration: 60, curve: Curve.EaseOut }, () => {
      this.shockwaveOpacity = 0.95;
      this.shockwaveScale = 0.4;
    });
    this.scheduleTimer((): void => {
      this.getUIContext().animateTo({ duration: SHOCKWAVE_MS, curve: Curve.EaseOut }, () => {
        this.shockwaveScale = 7.5;
        this.shockwaveOpacity = 0;
      });
    }, 60);

    // Secondary shockwave: kicks off slightly later and expands less,
    // creating a layered double-ring blast for visual weight.
    this.scheduleTimer((): void => {
      this.getUIContext().animateTo({ duration: 40, curve: Curve.EaseOut }, () => {
        this.shockwaveSecondaryOpacity = 0.85;
        this.shockwaveSecondaryScale = 0.5;
      });
    }, 100);
    this.scheduleTimer((): void => {
      this.getUIContext().animateTo({ duration: SHOCKWAVE_MS - 60, curve: Curve.EaseOut }, () => {
        this.shockwaveSecondaryScale = 5.2;
        this.shockwaveSecondaryOpacity = 0;
      });
    }, 140);

    // Big damage number: scale up + fade in, hold, float up + fade out.
    ui.animateTo({ duration: NUMBER_IN_MS, curve: Curve.EaseOut }, () => {
      this.numberOpacity = 1;
      this.numberScale = 1.4;
      this.numberTranslateY = -20;
    });
    this.scheduleTimer((): void => {
      this.getUIContext().animateTo({ duration: NUMBER_HOLD_MS, curve: Curve.EaseInOut }, () => {
        this.numberScale = 1.15;
        this.numberTranslateY = -50;
      });
    }, NUMBER_IN_MS);
    this.scheduleTimer((): void => {
      this.getUIContext().animateTo({ duration: NUMBER_OUT_MS, curve: Curve.EaseIn }, () => {
        this.numberOpacity = 0;
        this.numberTranslateY = -90;
      });
    }, NUMBER_IN_MS + NUMBER_HOLD_MS);
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
      //
      // hitTestBehavior(None) is applied to EVERY descendant: the
      // parent's Transparent only declares "self lets events through",
      // it does NOT propagate to children — a full-screen Column with
      // default mode would still swallow taps even at opacity 0,
      // which previously left the option buttons unresponsive after
      // a combo burst overlay was last triggered.
      Column()
        .id('CritGoldFlash')
        .width('100%')
        .height('100%')
        .backgroundColor('#FFB400')
        .opacity(this.flashOpacity)
        .hitTestBehavior(HitTestMode.None);

      // Expanding shockwave rings — primary (outer) burst and a
      // secondary inner ring for depth. Both centred and grow from
      // ~0.4 -> several times their base size.
      Stack() {
        Circle({ width: 120, height: 120 })
          .id('CritShockwave')
          .fill('#00000000')
          .stroke('#FFD93D')
          .strokeWidth(10)
          .opacity(this.shockwaveOpacity)
          .scale({ x: this.shockwaveScale, y: this.shockwaveScale })
          .hitTestBehavior(HitTestMode.None);
        Circle({ width: 90, height: 90 })
          .id('CritShockwaveInner')
          .fill('#00000000')
          .stroke('#FFFFFF')
          .strokeWidth(6)
          .opacity(this.shockwaveSecondaryOpacity)
          .scale({ x: this.shockwaveSecondaryScale, y: this.shockwaveSecondaryScale })
          .hitTestBehavior(HitTestMode.None);
      }
      .width('100%')
      .height('100%')
      .alignContent(Alignment.Center)
      .hitTestBehavior(HitTestMode.None);

      // Big floating damage number. Same always-mounted reasoning:
      // the opacity drops to 0 at rest so the big number is
      // imperceptible off-crit, but the id stays in the tree for
      // UiTest to assert on.
      Column() {
        Text(`-${this.damage}!`)
          .id('CritDamageNumber')
          .fontSize(96)
          .fontWeight(FontWeight.Bold)
          .fontColor('#E63946')
          .opacity(this.numberOpacity)
          .scale({ x: this.numberScale, y: this.numberScale })
          .translate({ x: 0, y: this.numberTranslateY })
          .hitTestBehavior(HitTestMode.None);
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .hitTestBehavior(HitTestMode.None);
    }
    // hitTestBehavior passthrough so the overlay never swallows taps
    // meant for the option buttons beneath it.
    .hitTestBehavior(HitTestMode.None)
    .width('100%')
    .height('100%');
  }
}
