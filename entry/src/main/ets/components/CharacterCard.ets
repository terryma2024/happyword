import { HpBar } from './HpBar';
import { UIContext } from '@kit.ArkUI';

/**
 * CharacterCard is the left/right column on the BattlePage.
 *
 * It renders three stacked pieces:
 *   1) A shape-based avatar (the "mage" on the left, the "slime" on the
 *      right). Using plain ArkUI shapes avoids shipping image assets in
 *      V0.1 while keeping a consistent cartoon look across devices — emoji
 *      rendering is font-dependent and can't be styled per-pixel.
 *   2) A name line for the character.
 *   3) An optional sublabel (e.g. "Monster 1 / 5") rendered above the HP bar.
 *   4) An HpBar so children can read health at a glance.
 *
 * All data comes in as @Prop values; the card owns no game state. This keeps
 * the spec's §7.3 "UI 只消费状态" boundary crisp.
 *
 * V0.2 pulse props (spec §4.3):
 *   - hurtPulse: incremented by BattlePage each time THIS card takes a
 *     hit (monster on a correct answer, player on a wrong answer). On
 *     each increment the card plays a 150 ms scale 1.0 → 0.95 → 1.0
 *     with a short red overlay flash. Triggered via @Watch so the
 *     parent only needs to bump a counter — no animation state leaks
 *     into BattlePage.
 *   - nudgePulse: incremented by BattlePage on the PLAYER card for
 *     every correct answer (non-crit). Plays a 120 ms translateX
 *     0 → 6 → 0 forward lunge.
 *   - zoomPulse / castPulse: reserved for the T11 crit spectacle —
 *     declared here so one @Prop wiring covers both animation tiers.
 */
export enum CharacterKind {
  Mage = 'mage',
  Slime = 'slime',
}

@Component
export struct CharacterCard {
  kind: CharacterKind = CharacterKind.Mage;
  name: string = '';
  @Prop hp: number = 0;
  @Prop maxHp: number = 1;
  // Must be @Prop so updates from the parent (e.g. "Monster 2 / 5" after
  // the first monster is defeated) actually invalidate this component. A
  // plain property would be captured at construction and stay stale.
  @Prop sublabel: string = '';

  // Per-monster theming colors used by slimeAvatar(). Defaults equal
  // the hex literals slimeAvatar painted before this prop existed, so
  // any caller that doesn't pass them gets the V0.2 slime green look
  // (mageAvatar never reads these — they're scoped to the slime body).
  @Prop bodyFill: string = '#4ECB71';
  @Prop bodyStroke: string = '#2E8B57';

  /**
   * Monotonically-increasing counters. Each observed change plays a
   * short animation and returns to rest; BattlePage never has to
   * reset the counter. Zero is the initial "no hit yet" value.
   */
  @Prop @Watch('onHurtPulseChanged') hurtPulse: number = 0;
  @Prop @Watch('onNudgePulseChanged') nudgePulse: number = 0;
  @Prop @Watch('onZoomPulseChanged') zoomPulse: number = 0;
  @Prop @Watch('onCastPulseChanged') castPulse: number = 0;

  /** Animation drivers — @State so ArkUI re-renders on each frame. */
  @State private avatarScale: number = 1;
  @State private avatarTranslateX: number = 0;
  @State private hurtOverlayOpacity: number = 0;
  @State private castGlowOpacity: number = 0;
  @State private castRotate: number = 0;

  /** Timers scheduled by onXxxPulseChanged — cleared on teardown. */
  private pulseTimers: number[] = [];

  aboutToDisappear(): void {
    for (let i = 0; i < this.pulseTimers.length; i++) {
      clearTimeout(this.pulseTimers[i]);
    }
    this.pulseTimers = [];
  }

  private scheduleTimer(cb: () => void, delayMs: number): void {
    const id: number = setTimeout(cb, delayMs);
    this.pulseTimers.push(id);
  }

  /**
   * Hurt animation: squash + red overlay flash + side-to-side shake to
   * sell the impact. The shake fires the same direction as the incoming
   * projectile (mage struck from the right pushes left, monster struck
   * from the left pushes right) before settling back to centre over
   * three diminishing oscillations. Skipped on the very first @Watch
   * callback that fires when the parent initialises the prop (value
   * still at default 0 for a freshly spawned card).
   */
  private onHurtPulseChanged(): void {
    if (this.hurtPulse <= 0) {
      return;
    }
    const ui: UIContext = this.getUIContext();
    // Initial impact direction: characters get pushed AWAY from the
    // attacker. Mage (left side) is hit by a projectile coming from the
    // right -> recoils to the left (-X). Slime (right side) is hit by
    // one coming from the left -> recoils to the right (+X).
    const recoil: number = this.kind === CharacterKind.Mage ? -12 : 12;

    ui.animateTo({ duration: 60, curve: Curve.EaseOut }, () => {
      this.avatarScale = 0.92;
      this.hurtOverlayOpacity = 0.7;
      this.avatarTranslateX = recoil;
    });
    // Shake step 1: bounce to the opposite side, slightly smaller.
    this.scheduleTimer((): void => {
      this.getUIContext().animateTo({ duration: 70, curve: Curve.EaseInOut }, () => {
        this.avatarTranslateX = -recoil * 0.7;
      });
    }, 60);
    // Shake step 2: damp back across centre.
    this.scheduleTimer((): void => {
      this.getUIContext().animateTo({ duration: 70, curve: Curve.EaseInOut }, () => {
        this.avatarTranslateX = recoil * 0.4;
      });
    }, 130);
    // Shake step 3: smaller wobble.
    this.scheduleTimer((): void => {
      this.getUIContext().animateTo({ duration: 70, curve: Curve.EaseInOut }, () => {
        this.avatarTranslateX = -recoil * 0.2;
      });
    }, 200);
    // Settle: clear scale, overlay, and translate together.
    this.scheduleTimer((): void => {
      this.getUIContext().animateTo({ duration: 130, curve: Curve.EaseOut }, () => {
        this.avatarScale = 1;
        this.hurtOverlayOpacity = 0;
        this.avatarTranslateX = 0;
      });
    }, 270);
  }

  /**
   * Player nudge: forward lunge. Direction depends on which side of
   * the screen the card sits on — mage is on the left and lunges
   * right (+6), slime is on the right and would lunge left (-6).
   */
  private onNudgePulseChanged(): void {
    if (this.nudgePulse <= 0) {
      return;
    }
    const direction: number = this.kind === CharacterKind.Mage ? 6 : -6;
    const ui: UIContext = this.getUIContext();
    ui.animateTo({ duration: 60, curve: Curve.EaseOut }, () => {
      this.avatarTranslateX = direction;
    });
    this.scheduleTimer((): void => {
      this.getUIContext().animateTo({ duration: 80, curve: Curve.EaseIn }, () => {
        this.avatarTranslateX = 0;
      });
    }, 80);
  }

  /**
   * T11 crit path: slow zoom on the monster card. 1.0 → 1.12 over
   * 220 ms ease-out, hold 120 ms, 1.12 → 1.0 over 160 ms ease-in.
   * Only drives this card's avatarScale because the crit layer runs
   * after T10's short hurt pulse has already relaxed (crit path
   * skips T10, so there's no animation crosstalk).
   */
  private onZoomPulseChanged(): void {
    if (this.zoomPulse <= 0) {
      return;
    }
    const ui: UIContext = this.getUIContext();
    ui.animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
      this.avatarScale = 1.12;
    });
    this.scheduleTimer((): void => {
      this.getUIContext().animateTo({ duration: 160, curve: Curve.EaseIn }, () => {
        this.avatarScale = 1;
      });
    }, 340);
  }

  /**
   * T11 crit path: player casting — 500 ms rotate + scale + glow ring.
   * More theatrical than the T10 nudge so burst damage feels earned.
   */
  private onCastPulseChanged(): void {
    if (this.castPulse <= 0) {
      return;
    }
    const ui: UIContext = this.getUIContext();
    ui.animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
      this.avatarScale = 1.15;
      this.castRotate = -10;
      this.castGlowOpacity = 0.9;
    });
    this.scheduleTimer((): void => {
      this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseInOut }, () => {
        this.castRotate = 10;
      });
    }, 180);
    this.scheduleTimer((): void => {
      this.getUIContext().animateTo({ duration: 140, curve: Curve.EaseIn }, () => {
        this.avatarScale = 1;
        this.castRotate = 0;
        this.castGlowOpacity = 0;
      });
    }, 360);
  }

  // Background tint for the whole card — a medium-light pastel with enough
  // saturation that the card edge reads clearly against the page background
  // (#F8F9FA). Earlier picks (#EAF4FD / #FDECEC) were close enough to the
  // page bg that the rounded corners faded into it, making the HP bar look
  // like it was drawn outside the card.
  private backgroundForKind(): string {
    return this.kind === CharacterKind.Mage ? '#D5E6F7' : '#F9D5D5';
  }

  // Accent colour used for the card's outer border — a darker shade of the
  // background so the card edge is unambiguous without looking heavy.
  private borderForKind(): string {
    return this.kind === CharacterKind.Mage ? '#A9C9EC' : '#E8A5A5';
  }

  // Shared avatar height — both mage and slime render into this vertical
  // footprint so the card can be given a single predictable content height
  // regardless of which character occupies it. 84vp is comfortable on both
  // tablet and phone landscape without letterboxing the HP bar below.
  private static readonly AVATAR_HEIGHT: number = 84;

  @Builder
  private mageAvatar() {
    // Stack layers the wizard's hat above a round purple body, with two
    // white eyes overlaid on the body so the character reads as a face.
    // Sized to fit within AVATAR_HEIGHT: hat 26 + brim 4 (net 2 after
    // margin -2) + body 54 + margin 2 ≈ 84vp.
    Column() {
      Polygon({ width: 44, height: 26 })
        .points([[22, 0], [0, 26], [44, 26]])
        .fill('#4A2577')
        .stroke('#2E1753')
        .strokeWidth(2);
      Rect({ width: 54, height: 4 })
        .fill('#2E1753')
        .margin({ top: -2 });
      Stack() {
        Circle({ width: 54, height: 54 })
          .fill('#8E5EC8')
          .stroke('#4A2577')
          .strokeWidth(2);
        Row() {
          Circle({ width: 10, height: 10 }).fill('#FFFFFF');
          Circle({ width: 10, height: 10 }).fill('#FFFFFF').margin({ left: 10 });
        }
        .offset({ y: -3 });
      }
      .width(54)
      .height(54)
      .margin({ top: 2 });
    }
    .height(CharacterCard.AVATAR_HEIGHT)
    .justifyContent(FlexAlign.End)
    .alignItems(HorizontalAlign.Center);
  }

  @Builder
  private slimeAvatar() {
    // A green half-ellipse body with two eyes. The masking Rect hides the
    // bottom half so the body reads as a dome; the dome is 42vp tall and
    // sits at the bottom of AVATAR_HEIGHT so the baseline aligns with the
    // mage's body baseline for a tidy visual row.
    Column() {
      Stack() {
        Ellipse({ width: 80, height: 72 })
          .fill(this.bodyFill)
          .stroke(this.bodyStroke)
          .strokeWidth(2);
        Rect({ width: 84, height: 36 })
          .fill(this.backgroundForKind())
          .offset({ y: 20 });
        Row() {
          Stack() {
            Circle({ width: 14, height: 14 }).fill('#FFFFFF');
            Circle({ width: 6, height: 6 }).fill('#1D3557');
          }
          Stack() {
            Circle({ width: 14, height: 14 }).fill('#FFFFFF');
            Circle({ width: 6, height: 6 }).fill('#1D3557');
          }
          .margin({ left: 10 });
        }
        .offset({ y: -8 });
      }
      .width(88)
      .height(72);
    }
    .height(CharacterCard.AVATAR_HEIGHT)
    .justifyContent(FlexAlign.End)
    .alignItems(HorizontalAlign.Center);
  }

  build() {
    // Height budget (must fit the parent Row on phone landscape, ~248vp):
    //   padding top  12
    //   avatar       84 (AVATAR_HEIGHT)
    //   space         8
    //   name+sub     ~38 (16 name + 2 gap + ~14 sublabel, sublabel optional)
    //   space         8
    //   HP bar       ~32 (14 text + 4 gap + 10 bar + 4 spare)
    //   padding bot  12
    //   total       ~194vp max, well within the 248vp Row.
    // Keeping the card content-sized (no height('100%')) means the card's
    // background is exactly the content rectangle and the HP bar always
    // sits cleanly inside the rounded border.
    Column({ space: 8 }) {
      // Avatar wrapper carries the hurt/nudge/zoom/cast transforms and a
      // red hit overlay + gold casting glow, both full-bleed behind the
      // avatar shapes. The overlays are rendered unconditionally (just
      // opacity 0 at rest) so the Stack's child list never changes and
      // the animation doesn't race with a layout pass.
      Stack() {
        Column() {
          Circle({ width: 96, height: 96 })
            .id(this.kind === CharacterKind.Mage ? 'CritCastGlow' : 'HurtGlowSlime')
            .fill('#FFDA3D')
            .opacity(this.castGlowOpacity);
        }
        .width(96)
        .height(96)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center);

        if (this.kind === CharacterKind.Mage) {
          this.mageAvatar();
        } else {
          this.slimeAvatar();
        }

        // Red damage overlay — sits above the avatar shapes, fades to
        // opacity 0 at rest. When hurtPulse fires we animate it up to
        // 0.55 for the brief squash window.
        Column()
          .id(this.kind === CharacterKind.Slime ? 'MonsterHurtOverlay' : 'PlayerHurtOverlay')
          .width(96)
          .height(96)
          .backgroundColor('#E63946')
          .opacity(this.hurtOverlayOpacity)
          .borderRadius(48);
      }
      .width(96)
      .height(CharacterCard.AVATAR_HEIGHT)
      .scale({ x: this.avatarScale, y: this.avatarScale })
      .translate({ x: this.avatarTranslateX, y: 0 })
      .rotate({ angle: this.castRotate });

      Column({ space: 2 }) {
        Text(this.name)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1D3557');

        if (this.sublabel.length > 0) {
          Text(this.sublabel)
            .fontSize(13)
            .fontColor('#555555');
        }
      }
      .alignItems(HorizontalAlign.Center);

      Column() {
        HpBar({ current: this.hp, max: this.maxHp, label: 'HP' });
      }
      .width('88%');
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 12, bottom: 12 })
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(this.backgroundForKind())
    .borderRadius(14)
    .border({ width: 1, color: this.borderForKind() });
  }
}
