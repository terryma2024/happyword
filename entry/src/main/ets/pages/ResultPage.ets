import { router } from '@kit.ArkUI';
import { BusinessError } from '@ohos.base';

/**
 * ResultPage shows the session summary and navigation back to home or a replay.
 *
 * V0.1 scope (per spec §6.4):
 * - Display win/lose, defeated monsters, accuracy, learned word count, stars.
 * - Offer "Play again" and "Back to home" actions.
 *
 * T2 skeleton: static placeholders only; real SessionResult wiring arrives in T8.
 * Uses replaceUrl so the result page is not stacked when users replay repeatedly.
 */
@Entry
@Component
struct ResultPage {
  build(): void {
    Column() {
      Text('Result')
        .id('ResultTitle')
        .fontSize(32)
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 12 });

      Text('本局结果（占位）')
        .fontSize(20)
        .fontColor('#457B9D')
        .margin({ bottom: 24 });

      Column() {
        Text('击败怪物：0 / 5').fontSize(16).margin({ bottom: 6 });
        Text('正确率：0%').fontSize(16).margin({ bottom: 6 });
        Text('学习单词：0').fontSize(16).margin({ bottom: 6 });
        Text('星级：☆☆☆').fontSize(16);
      }
      .margin({ bottom: 32 });

      Row() {
        Button('再来一局')
          .id('ResultRetryButton')
          .width(160)
          .height(52)
          .margin({ right: 16 })
          .onClick((): void => {
            router.replaceUrl({ url: 'pages/BattlePage' }).catch((err: BusinessError) => {
              console.error(`ResultPage: replaceUrl BattlePage failed: ${JSON.stringify(err)}`);
            });
          });

        Button('返回首页')
          .id('ResultHomeButton')
          .width(160)
          .height(52)
          .onClick((): void => {
            router.replaceUrl({ url: 'pages/HomePage' }).catch((err: BusinessError) => {
              console.error(`ResultPage: replaceUrl HomePage failed: ${JSON.stringify(err)}`);
            });
          });
      };
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center);
  }
}
