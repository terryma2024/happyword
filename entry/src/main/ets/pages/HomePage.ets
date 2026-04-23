import { router } from '@kit.ArkUI';
import { BusinessError } from '@ohos.base';

/**
 * HomePage is the entry screen of WordMagicGame.
 *
 * V0.1 scope (per spec §6.2):
 * - Show product title and a "Start" button.
 * - No battle state or question generation here.
 *
 * This is a placeholder for T2 (page routing skeleton). Visual polish, category
 * selection and child-friendly illustrations come later.
 */
@Entry
@Component
struct HomePage {
  build(): void {
    Column() {
      Text('Small Magician Word Adventure')
        .id('HomeTitle')
        .fontSize(36)
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 12 });

      Text('小魔法师单词冒险')
        .fontSize(22)
        .fontColor('#457B9D')
        .margin({ bottom: 32 });

      Text('点击开始，打败 5 个单词史莱姆吧！')
        .fontSize(18)
        .margin({ bottom: 40 });

      Button('开始游戏')
        .id('HomeStartButton')
        .fontSize(24)
        .width(220)
        .height(64)
        .backgroundColor('#E63946')
        .onClick((): void => {
          router.pushUrl({ url: 'pages/BattlePage' }).catch((err: BusinessError) => {
            console.error(`HomePage: pushUrl BattlePage failed: ${JSON.stringify(err)}`);
          });
        });
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center);
  }
}
