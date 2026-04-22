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

@Component
export struct GiftBox {
  // Parent increments on every tap. Reserved for Task 3.
  @Prop trigger: number = 0;

  build(): void {
    Stack() {
      // Body — rounded rectangle with a vertical gold stripe down its center.
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

      // Lid group — rectangle + bowtie.
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
      .offset({ x: 0, y: -64 });
    }
    .id('GiftBoxContainer')
    .width(132)
    .height(120);
  }
}
