import { router } from '@kit.ArkUI';

@Entry
@Component
struct ConfigPage {
  build(): void {
    Column({ space: 16 }) {
      Text('游戏设置')
        .id('ConfigTitle')
        .fontSize(24)
        .fontWeight(FontWeight.Bold);

      Text('TODO: configuration form')
        .fontSize(14)
        .opacity(0.6);

      Button('返回')
        .id('ConfigBackButton')
        .onClick(() => { router.back(); });
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center);
  }
}
