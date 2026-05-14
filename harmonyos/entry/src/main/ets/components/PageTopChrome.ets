/**
 * Shared top navigation chrome: circular leading back (chevron only,
 * no text) and an optional trailing builder for page actions
 * (Save, filters, etc.). Center title is optional.
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
  onBack: () => void = (): void => {};
  @BuilderParam trailing: () => void = defaultPageTopTrailing;

  build(): void {
    Row() {
      Button({ type: ButtonType.Circle }) {
        Text('‹')
          .fontSize(24)
          .fontWeight(FontWeight.Medium)
          .fontColor('#1D3557')
          .margin({ right: 2 });
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
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1f2937')
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
}
