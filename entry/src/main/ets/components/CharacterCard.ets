import { HpBar } from './HpBar';
import { UIContext } from '@kit.ArkUI';

/**
 * CharacterCard is the left/right column on the BattlePage.
 *
 * It renders three stacked pieces:
 *   1) An SVG portrait loaded from rawfile via `assetPath`.
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
  // Must be @Prop so the monster's name updates when BattlePage swaps in
  // the next MonsterEntry (e.g. "Slime" -> "Zombie" -> "Dragon" -> boss
  // as the player advances through the 5 slots of a region). A plain
  // field would be captured at construction and stay stale across
  // monster transitions.
  @Prop name: string = '';
  @Prop hp: number = 0;
  @Prop maxHp: number = 1;
  // Must be @Prop so updates from the parent (e.g. "Monster 2 / 5" after
  // the first monster is defeated) actually invalidate this component. A
  // plain property would be captured at construction and stay stale.
  @Prop sublabel: string = '';

  @Prop assetPath: string = '';

  /**
   * V0.4.8 — optional secondary portrait that lives in the avatar
   * Stack alongside the primary `assetPath`. Both Images mount at
   * construction so they decode once each (and only once); ArkUI
   * then toggles between them via `altActive`'s opacity binding.
   * Empty `altAssetPath` keeps the secondary layer absent so cards
   * that only ever render the idle pose (e.g. monsters) pay zero
   * extra layout cost.
   *
   * Prefer this over swapping `assetPath` mid-battle: a dynamic
   * `Image($rawfile(this.assetPath))` re-decodes synchronously
   * under `syncLoad(true)` and that 100+ KB SVG decode pause is
   * long enough to drop a tap on the emulator.
   */
  @Prop altAssetPath: string = '';
  @Prop altActive: boolean = false;

  /**
   * Optional "被攻击" (taking-a-hit) portrait. Mounted alongside
   * the idle and fight poses; activates automatically during the
   * hurt-pulse animation window (set true on hit, cleared after
   * the settle step) so callers only need to pass the asset path
   * — they do NOT bump a separate "active" flag. Empty path leaves
   * the layer absent (zero cost for monsters / cards that don't
   * have a beaten pose).
   */
  @Prop hurtAssetPath: string = '';

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
  /**
   * Tracks whether the "beaten" portrait should be visible. Driven by
   * the hurt-pulse lifecycle (true at impact, false at settle). Plain
   * `@State` because it must trigger a rebuild so the third image
   * layer's opacity binding picks the new value up.
   */
  @State private hurtPoseActive: boolean = false;

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

    // Swap to the "被攻击" pose for the duration of the hit animation.
    // No-op when `hurtAssetPath` is empty (the third Image layer is
    // gated on the same field below).
    this.hurtPoseActive = true;

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
    // Restore the idle pose once the settle animation completes
    // (270 ms shake tail + 130 ms settle = 400 ms). Done as a separate
    // scheduled callback rather than an animateTo binding because the
    // pose swap is a discrete opacity flip, not a tweened property.
    this.scheduleTimer((): void => {
      this.hurtPoseActive = false;
    }, 400);
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

  /**
   * Idle layer is hidden whenever a higher-priority pose (hurt or
   * alt/fight) is active and its asset is configured. Returns 0 in
   * that case so the secondary Image fully replaces it; otherwise 1.
   */
  private idlePoseOpacity(): number {
    if (this.hurtAssetPath.length > 0 && this.hurtPoseActive) {
      return 0;
    }
    if (this.altAssetPath.length > 0 && this.altActive) {
      return 0;
    }
    return 1;
  }

  // Shared avatar height — both mage and slime render into this vertical
  // footprint so the card can be given a single predictable content height
  // regardless of which character occupies it. 84vp is comfortable on both
  // tablet and phone landscape without letterboxing the HP bar below.
  private static readonly AVATAR_HEIGHT: number = 84;

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

        // Pose precedence (top wins): hurt > alt (fight) > idle.
        // The idle layer is only visible when neither the hurt nor
        // the alt pose is active — otherwise it would bleed through.
        Image($rawfile(this.assetPath))
          .objectFit(ImageFit.Contain)
          .width(96)
          .height(CharacterCard.AVATAR_HEIGHT)
          .syncLoad(true)
          .interpolation(ImageInterpolation.High)
          .opacity(this.idlePoseOpacity());

        // V0.4.8: stacked alt portrait for the player's mid-cast fight
        // pose. Mounted at construction so the SVG is decoded once;
        // toggled visible via opacity instead of swapping the primary
        // assetPath, which was forcing a synchronous decode pause that
        // dropped taps on the emulator.
        if (this.altAssetPath.length > 0) {
          Image($rawfile(this.altAssetPath))
            .objectFit(ImageFit.Contain)
            .width(96)
            .height(CharacterCard.AVATAR_HEIGHT)
            .syncLoad(true)
            .interpolation(ImageInterpolation.High)
            // Hide the fight pose during the hurt window so the beaten
            // pose isn't visually stacked behind it.
            .opacity(this.altActive && !this.hurtPoseActive ? 1 : 0)
            .hitTestBehavior(HitTestMode.None);
        }

        // "被攻击" pose. Same mount-once-toggle-opacity pattern as the
        // alt fight pose; gated on hurtPoseActive which the hurt-pulse
        // animation flips true on impact and false on settle.
        if (this.hurtAssetPath.length > 0) {
          Image($rawfile(this.hurtAssetPath))
            .objectFit(ImageFit.Contain)
            .width(96)
            .height(CharacterCard.AVATAR_HEIGHT)
            .syncLoad(true)
            .interpolation(ImageInterpolation.High)
            .opacity(this.hurtPoseActive ? 1 : 0)
            .hitTestBehavior(HitTestMode.None);
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
