import { router } from '@kit.ArkUI';
import { BusinessError } from '@ohos.base';

/**
 * WishlistPage — V0.3 stub route. Phase C fleshes this out with the
 * WishlistStore-backed wish list, the parental long-press confirm
 * gate, and the magic-coin balance header. For now we ship a
 * placeholder so HomePage and ResultPage can navigate here without
 * breaking the build.
 */
@Entry
@Component
struct WishlistPage {
  build(): void {
    Column({ space: 20 }) {
      Text('魔法心愿单')
        .id('WishlistTitle')
        .fontSize(28)
        .fontWeight(FontWeight.Bold);
      Text('Phase C 即将上线 — 现在来一局今日冒险攒攒金币吧!')
        .id('WishlistPlaceholder')
        .fontSize(16)
        .fontColor('#5A4A35');
      Button('返回')
        .id('WishlistBackButton')
        .fontSize(18)
        .width(180)
        .height(48)
        .backgroundColor('#457B9D')
        .fontColor('#FFFFFF')
        .onClick((): void => {
          try {
            router.back();
          } catch (err) {
            console.error(`WishlistPage.back failed: ${JSON.stringify(err as BusinessError)}`);
          }
        });
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center);
  }
}
