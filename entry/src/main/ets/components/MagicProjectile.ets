import { UIContext } from '@kit.ArkUI';
import display from '@ohos.display';
import { BusinessError } from '@ohos.base';

/**
 * MagicProjectile renders a glowing magic ball that travels horizontally
 * across the battle scene from one character to the other.
 *
 * Direction is parameterised:
 *   - forward = true  -> mage on the left fires toward the monster on the right.
 *     Used on correct answers and on combo bursts (bigger / gold).
 *   - forward = false -> monster fires back at the mage.
 *     Used on wrong answers.
 *
 * BattlePage drives the projectile by bumping `projectilePulse`. Each
 * observed change runs the full timeline:
 *
 *   1. Spawn (80 ms): scale 0.4 -> 1, opacity 0 -> 1, glow ring fades in.
 *   2. Travel (240 ms): translateX moves from start -> end across the screen.
 *   3. Impact (140 ms): scale balloons to 2x and fades out so the ball
 *      "explodes" against the receiving character.
 *
 * The component is a pure visual effect — it never intercepts taps
 * (hitTestBehavior = None) and re-runs entirely from the watched pulse
 * counter so callers don't need to manage animation state.
 */

const SPAWN_MS: number = 80;
const TRAVEL_MS: number = 260;
const IMPACT_MS: number = 160;

@Component
export struct MagicProjectile {
  /** Monotonically-increasing trigger. BattlePage bumps it per shot. */
  @Prop @Watch('onPulseChanged') projectilePulse: number = 0;
  /** true: fire from mage (left) toward monster (right). */
  @Prop forward: boolean = true;
  /** 1 = normal shot, 2 = combo-burst shot (gold, bigger). */
  @Prop intensity: number = 1;

  @State private translateX: number = 0;
  @State private coreOpacity: number = 0;
  @State private coreScale: number = 0.4;
  @State private outerOpacity: number = 0;
  @State private outerScale: number = 0.5;

  private timers: number[] = [];
  /** Width of the screen in vp; resolved on mount, used to size travel. */
  private screenWidthVp: number = 720;

  aboutToAppear(): void {
    try {
      const d: display.Display = display.getDefaultDisplaySync();
      // display.width is reported in physical pixels; convert to vp so the
      // projectile's traversal matches ArkUI's layout units.
      this.screenWidthVp = px2vp(d.width);
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      console.error(`MagicProjectile: failed to read display: ${JSON.stringify(e)}`);
    }
  }

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

  private onPulseChanged(): void {
    if (this.projectilePulse <= 0) {
      return;
    }

    // The overlay is centred on the screen, so translate is measured
    // from the centre. 0.40 of half-width lands close to the inner edge
    // of each character card on landscape phones; tweaked empirically to
    // not hit the question prompt text in the middle column.
    const halfWidth: number = this.screenWidthVp / 2;
    const margin: number = halfWidth * 0.78;
    const startX: number = this.forward ? -margin : margin;
    const endX: number = this.forward ? margin : -margin;

    const ui: UIContext = this.getUIContext();

    // Snap to the spawn frame at the source character. Wrapping in
    // `animateTo({ duration: 0 })` is the canonical ArkUI "set without
    // transition" pattern — it batches the assignments into a single
    // render pass and signals to codelinter that these values
    // participate in the animation lifecycle rather than being
    // temporary calculations that should be local vars.
    ui.animateTo({ duration: 0 }, () => {
      this.translateX = startX;
      this.coreOpacity = 0;
      this.coreScale = 0.4;
      this.outerOpacity = 0;
      this.outerScale = 0.5;
    });
    // Phase 1: spawn at the source character.
    ui.animateTo({ duration: SPAWN_MS, curve: Curve.EaseOut }, () => {
      this.coreOpacity = 1;
      this.coreScale = 1;
      this.outerOpacity = 0.65;
      this.outerScale = 1;
    });

    // Phase 2: travel across the battle scene.
    this.scheduleTimer((): void => {
      this.getUIContext().animateTo({ duration: TRAVEL_MS, curve: Curve.EaseInOut }, () => {
        this.translateX = endX;
      });
    }, SPAWN_MS);

    // Phase 3: impact — explode against the target.
    this.scheduleTimer((): void => {
      this.getUIContext().animateTo({ duration: IMPACT_MS, curve: Curve.EaseOut }, () => {
        this.coreScale = 2.2;
        this.outerScale = 2.8;
        this.coreOpacity = 0;
        this.outerOpacity = 0;
      });
    }, SPAWN_MS + TRAVEL_MS);
  }

  /** Outer glow halo colour. */
  private glowColor(): string {
    if (this.intensity > 1) {
      return '#FFE56F';
    }
    return this.forward ? '#C5DBFF' : '#FFCBCB';
  }

  /** Bright projectile core colour. */
  private coreColor(): string {
    if (this.intensity > 1) {
      return '#FFD93D';
    }
    return this.forward ? '#7BA9FF' : '#FF6B6B';
  }

  /** Solid ring stroke for the core, keeps the orb readable in flight. */
  private ringColor(): string {
    if (this.intensity > 1) {
      return '#FF8A1E';
    }
    return this.forward ? '#3D6FD0' : '#B23A3A';
  }

  build(): void {
    Stack() {
      Stack() {
        // Outer glow halo — large, soft, follows the core.
        Circle({
          width: 64 * this.intensity,
          height: 64 * this.intensity,
        })
          .fill(this.glowColor())
          .opacity(this.outerOpacity)
          .scale({ x: this.outerScale, y: this.outerScale });

        // Bright core orb with a contrasting ring so it reads against
        // the pastel battle background.
        Circle({
          width: 30 * this.intensity,
          height: 30 * this.intensity,
        })
          .fill(this.coreColor())
          .stroke(this.ringColor())
          .strokeWidth(3)
          .opacity(this.coreOpacity)
          .scale({ x: this.coreScale, y: this.coreScale });
      }
      .id(this.forward ? 'MagicProjectileForward' : 'MagicProjectileBackward')
      .translate({ x: this.translateX, y: 0 });
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.Center)
    .hitTestBehavior(HitTestMode.None);
  }
}
