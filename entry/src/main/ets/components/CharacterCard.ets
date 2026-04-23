import { HpBar } from './HpBar';

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
          .fill('#4ECB71')
          .stroke('#2E8B57')
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
      if (this.kind === CharacterKind.Mage) {
        this.mageAvatar();
      } else {
        this.slimeAvatar();
      }

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
