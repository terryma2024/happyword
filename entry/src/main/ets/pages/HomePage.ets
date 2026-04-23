import { router } from '@kit.ArkUI';
import { BusinessError } from '@ohos.base';

@Entry
@Component
struct HomePage {
  build(): void {
    Stack() {
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

      Button('⚙')
        .id('HomeConfigButton')
        .type(ButtonType.Circle)
        .width(56)
        .height(56)
        .fontSize(28)
        .fontColor('#457B9D')
        .backgroundColor('#EAF2F8')
        .margin({ top: 16, right: 16 })
        .onClick((): void => {
          router.pushUrl({ url: 'pages/ConfigPage' }).catch((err: BusinessError) => {
            console.error(`HomePage: pushUrl ConfigPage failed: ${JSON.stringify(err)}`);
          });
        });
    }
    .alignContent(Alignment.TopEnd)
    .width('100%')
    .height('100%');
  }
}
