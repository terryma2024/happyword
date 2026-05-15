/**
 * Shared top navigation chrome: circular leading back (← arrow glyph)
 * and an optional trailing builder for page actions (Save, filters,
 * etc.). Center title is optional.
 *
 * Default `pageGutterVp` (16) plus the inner row’s 8vp padding matches
 * MonsterCodexPage’s historical top-bar insets (back at 24vp from edge).
 * Main scroll/body horizontal + bottom inset below this chrome uses
 * `PAGE_BODY_EDGE_VP` in `constants/PageLayoutInsets.ets`.
 */
@Builder
function defaultPageTopTrailing(): void {
  Blank()
    .width(1)
    .height(1);
}

@Component
export struct PageTopChrome {
  /** UITest / accessibility id for the circular back control. */
  backButtonId: string = 'PageTopBack';
  /** Optional centered title between back and trailing. */
  title: string = '';
  /** When set, applied as the title Text component id (uitest). */
  titleId: string = '';
  /** Title line height; default matches other chrome pages. */
  titleFontSize: number = 18;
  /** Title text color (hex). */
  titleFontColor: string = '#1f2937';
  onBack: () => void = (): void => {};
  @BuilderParam trailing: () => void = defaultPageTopTrailing;
  /**
   * Outer inset (vp) before the inner chrome row padding. MonsterCodexPage
   * historically used 16vp here; set to 0 only when the parent page already
   * applied the same gutter (avoid double insets).
   */
  pageGutterVp: number = 16;

  build(): void {
    Column() {
      Row() {
        Button({ type: ButtonType.Circle }) {
          Text('←')
            .fontSize(22)
            .fontWeight(FontWeight.Medium)
            .fontColor('#1D3557');
        }
          .width(40)
          .height(40)
          .backgroundColor('#EAF2F8')
          .id(this.backButtonId)
          .onClick((): void => this.onBack());

        if (this.title.length > 0) {
          Text(this.title)
            .id(this.titleId.length > 0 ? this.titleId : 'PageTopChromeTitle')
            .layoutWeight(1)
            .fontSize(this.titleFontSize)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.titleFontColor)
            .textAlign(TextAlign.Center)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
        } else {
          Blank().layoutWeight(1);
        }

        Row() {
          this.trailing();
        }
        .justifyContent(FlexAlign.End)
        .alignItems(VerticalAlign.Center);
      }
      .width('100%')
      .padding({ left: 8, right: 8, top: 8, bottom: 8 })
      .alignItems(VerticalAlign.Center);
    }
    .width('100%')
    .padding({
      left: this.pageGutterVp,
      right: this.pageGutterVp,
      top: this.pageGutterVp,
      bottom: 0,
    });
  }
}
