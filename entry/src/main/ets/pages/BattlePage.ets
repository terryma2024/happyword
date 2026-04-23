import { router } from '@kit.ArkUI';
import { BusinessError } from '@ohos.base';

/**
 * BattlePage is the core gameplay screen.
 *
 * V0.1 scope (per spec §6.3 and §9.1):
 * - Three-segment landscape layout: player card | question area | monster card.
 * - Three option buttons below the question.
 *
 * T2 skeleton: only the layout and a stub "finish battle" button that jumps to
 * ResultPage. Real question rendering, HP bars and combo feedback land in
 * later sprints (T5/T6/T7).
 */
@Entry
@Component
struct BattlePage {
  build(): void {
    Column() {
      Text('Battle')
        .id('BattleTitle')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .margin({ top: 12, bottom: 12 });

      Row() {
        // Left: player card placeholder.
        Column() {
          Text('Player')
            .fontSize(20)
            .fontWeight(FontWeight.Bold);
          Text('HP 5 / 5')
            .fontSize(16)
            .margin({ top: 8 });
        }
        .id('PlayerArea')
        .layoutWeight(1)
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor('#F1FAEE');

        // Center: question area placeholder.
        Column() {
          Text('Question')
            .fontSize(18)
            .fontColor('#1D3557');
          Text('中文提示会显示在这里')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .margin({ top: 12 });
          Text('Combo: 0')
            .fontSize(14)
            .margin({ top: 8 });
          // T2 placeholder: real gameplay (T6) will auto-route on win/lose/timeout.
          // Placed in the central column so the button is always visible on both
          // landscape tablet and portrait phone emulators, where a bottom-row
          // button can be clipped by the navigation bar.
          Button('结束战斗（占位）')
            .id('BattleFinishButton')
            .height(44)
            .margin({ top: 24 })
            .onClick((): void => {
              router.replaceUrl({ url: 'pages/ResultPage' }).catch((err: BusinessError) => {
                console.error(`BattlePage: replaceUrl ResultPage failed: ${JSON.stringify(err)}`);
              });
            });
        }
        .id('QuestionArea')
        .layoutWeight(2)
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center);

        // Right: monster card placeholder.
        Column() {
          Text('Monster 1 / 5')
            .fontSize(20)
            .fontWeight(FontWeight.Bold);
          Text('HP 3 / 3')
            .fontSize(16)
            .margin({ top: 8 });
        }
        .id('MonsterArea')
        .layoutWeight(1)
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor('#FCE4EC');
      }
      .width('100%')
      .layoutWeight(1);

      // Three option buttons — text is placeholder until QuestionGenerator lands.
      Row() {
        Button('Option A')
          .id('BattleOptionA')
          .layoutWeight(1)
          .height(56)
          .margin({ left: 8, right: 8 });
        Button('Option B')
          .id('BattleOptionB')
          .layoutWeight(1)
          .height(56)
          .margin({ left: 8, right: 8 });
        Button('Option C')
          .id('BattleOptionC')
          .layoutWeight(1)
          .height(56)
          .margin({ left: 8, right: 8 });
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 16 });
    }
    .width('100%')
    .height('100%');
  }
}
