const SLOT_GAP: number = 8;
const SLOT_WIDTH: number = 36;
const SLOT_HEIGHT: number = 48;
const TEXT_COLOR_FILLED: string = '#1D3557';
const TEXT_COLOR_MISSING: string = '#E63946';
const BG_COLOR_MISSING: string = '#FCEAEA';

class LetterSlot {
  idx: number = 0;
  glyph: string = '';
  isMissing: boolean = false;
}

/**
 * LetterTemplate — display-only row of letters, with the missing
 * slot rendered as a coloured `_` over a faint pink background.
 *
 * Consumers pass the space-separated template ("a _ p l e") and the
 * 0-based missingIndex; the component splits and renders each token.
 */
@Component
export struct LetterTemplate {
  @Prop template: string = '';
  @Prop missingIndex: number = -1;

  build(): void {
    Row({ space: SLOT_GAP }) {
      ForEach(this.tokens(), (item: LetterSlot, _: number) => {
        Stack() {
          if (item.isMissing) {
            Column()
              .width(SLOT_WIDTH)
              .height(SLOT_HEIGHT)
              .backgroundColor(BG_COLOR_MISSING)
              .borderRadius(6);
            Text('_')
              .fontSize(28)
              .fontWeight(FontWeight.Bold)
              .fontColor(TEXT_COLOR_MISSING);
          } else {
            Text(item.glyph)
              .fontSize(32)
              .fontWeight(FontWeight.Bold)
              .fontColor(TEXT_COLOR_FILLED);
          }
        }
        .width(SLOT_WIDTH)
        .height(SLOT_HEIGHT)
        .alignContent(Alignment.Center);
      }, (item: LetterSlot, _: number) => `${item.idx}-${item.glyph}`);
    }
    .id('LetterTemplateRow')
    .width('100%')
    .justifyContent(FlexAlign.Center);
  }

  private tokens(): LetterSlot[] {
    const out: LetterSlot[] = [];
    if (this.template.length === 0) {
      return out;
    }
    const parts: string[] = this.template.split(' ');
    for (let i = 0; i < parts.length; i++) {
      const slot: LetterSlot = new LetterSlot();
      slot.idx = i;
      slot.glyph = parts[i];
      slot.isMissing = i === this.missingIndex || parts[i] === '_';
      out.push(slot);
    }
    return out;
  }
}
