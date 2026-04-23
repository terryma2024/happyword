import { router } from '@kit.ArkUI';

@Entry
@Component
struct CustomWordsPage {
  build(): void {
    Column({ space: 16 }) {
      Text('自定义词表')
        .id('CustomWordsTitle')
        .fontSize(24)
        .fontWeight(FontWeight.Bold);

      Text('TODO: text area for custom words')
        .fontSize(14)
        .opacity(0.6);

      Button('返回')
        .id('CustomWordsBackButton')
        .onClick(() => { router.back(); });
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center);
  }
}
