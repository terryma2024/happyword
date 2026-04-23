import { router } from '@kit.ArkUI';
import { BusinessError } from '@ohos.base';
import { CharacterCard, CharacterKind } from '../components/CharacterCard';
import { ChoiceButton, ChoiceState } from '../components/ChoiceButton';

/**
 * BattlePage is the core gameplay screen.
 *
 * T5 scope (spec §6.3 / §9.1):
 * - Static landscape layout: player card | question area | monster card.
 * - Header with combo counter and remaining-time readout.
 * - Three large ChoiceButtons at the bottom, uniform style.
 * - Shape-based avatars via CharacterCard (no asset pipeline needed in V0.1).
 *
 * T5 is intentionally UI-only: there is no BattleEngine, no timer, and no
 * answer handling yet. All displayed values are static placeholders whose
 * exact strings match what the ohosTest UI tests assert, so tests continue
 * to pass without edits. Real behaviour lands in T6 / T7.
 *
 * The dev-only "end battle" affordance is retained so UI tests can exercise
 * the Battle → Result route until T6 adds real win/lose/timeout transitions.
 * It is styled as a small corner link, not a primary button, so it reads as
 * a debug tool rather than part of gameplay.
 */
@Entry
@Component
struct BattlePage {
  // Static placeholder values — T6 will replace these with @State values
  // driven by BattleState. Kept as member fields (not @State) so it's
  // obvious to future maintainers that nothing here is dynamic yet.
  private readonly playerName: string = 'Magician';
  private readonly playerHp: number = 5;
  private readonly playerMaxHp: number = 5;
  private readonly monsterName: string = 'Word Slime';
  private readonly monsterHp: number = 3;
  private readonly monsterMaxHp: number = 3;
  private readonly monsterIndex: number = 1;
  private readonly monsterTotal: number = 5;
  private readonly comboCount: number = 0;
  private readonly remainingSeconds: number = 300;
  private readonly prompt: string = '中文提示会显示在这里';
  private readonly options: string[] = ['Option A', 'Option B', 'Option C'];
  private readonly optionIds: string[] = ['BattleOptionA', 'BattleOptionB', 'BattleOptionC'];

  private formatTime(totalSeconds: number): string {
    const mins: number = Math.floor(totalSeconds / 60);
    const secs: number = totalSeconds % 60;
    const mm: string = mins < 10 ? `0${mins}` : `${mins}`;
    const ss: string = secs < 10 ? `0${secs}` : `${secs}`;
    return `${mm}:${ss}`;
  }

  @Builder
  private header() {
    Row() {
      Text(`Combo: ${this.comboCount}`)
        .id('BattleComboLabel')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor('#1D3557');
      Blank()
        .layoutWeight(1);
      Text('Battle')
        .id('BattleTitle')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1D3557');
      Blank()
        .layoutWeight(1);
      Text(`Time ${this.formatTime(this.remainingSeconds)}`)
        .id('BattleTimerLabel')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor('#1D3557');
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 12, bottom: 12 });
  }

  @Builder
  private questionArea() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
        Text('Question')
          .fontSize(14)
          .fontColor('#457B9D');
        // Chinese prompt — large and centred so it is unmistakably the
        // primary thing to read on the screen.
        Text(this.prompt)
          .id('BattlePrompt')
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1D3557')
          .margin({ top: 16 });
        // Feedback slot kept empty in T5; T6 will show "正确！" / "正确答案
        // 是 …" here. Declared now so the layout does not jump when T6
        // starts populating it.
        Text(' ')
          .id('BattleFeedback')
          .fontSize(16)
          .fontColor('#2ECC71')
          .margin({ top: 16 });
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center);

      // Dev-only affordance: small, low-contrast, tucked into the corner.
      // Lets UI tests and manual smoke tests reach the ResultPage before the
      // real win/lose/timeout routing lands in T6. Remove when T6 ships.
      Text('[debug] end battle')
        .id('BattleFinishButton')
        .fontSize(12)
        .fontColor('#888888')
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .onClick((): void => {
          router.replaceUrl({ url: 'pages/ResultPage' }).catch((err: BusinessError) => {
            console.error(`BattlePage: replaceUrl ResultPage failed: ${JSON.stringify(err)}`);
          });
        });
    }
    .id('QuestionArea')
    .layoutWeight(2)
    .height('100%')
    .padding(12);
  }

  @Builder
  private optionsRow() {
    // Row-level horizontal space(4) combines with each ChoiceButton's own
    // symmetric margin(8) to give a comfortable ~20vp gap between adjacent
    // option buttons without the buttons visually touching the screen edges.
    Row({ space: 4 }) {
      ChoiceButton({
        text: this.options[0],
        choiceId: this.optionIds[0],
        state: ChoiceState.Idle,
        onTap: (_text: string): void => {
          // T6 will wire this to BattleEngine.submitAnswer(...).
        },
      });
      ChoiceButton({
        text: this.options[1],
        choiceId: this.optionIds[1],
        state: ChoiceState.Idle,
        onTap: (_text: string): void => {
          // T6 will wire this to BattleEngine.submitAnswer(...).
        },
      });
      ChoiceButton({
        text: this.options[2],
        choiceId: this.optionIds[2],
        state: ChoiceState.Idle,
        onTap: (_text: string): void => {
          // T6 will wire this to BattleEngine.submitAnswer(...).
        },
      });
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 16, bottom: 20 });
  }

  build(): void {
    Column() {
      this.header();

      // Row-level space(16) creates consistent horizontal gutters between
      // Player | Question | Monster so each zone has clear breathing room
      // against its neighbours. alignItems(Center) vertically centres the
      // content-sized cards relative to the taller question column.
      Row({ space: 16 }) {
        // Left: player card. The wrapper fills the Row height and centres
        // the content-sized CharacterCard vertically, so mage and slime
        // cards of different natural heights both appear visually centred.
        Column() {
          CharacterCard({
            kind: CharacterKind.Mage,
            name: this.playerName,
            hp: this.playerHp,
            maxHp: this.playerMaxHp,
            sublabel: '',
          });
        }
        .id('PlayerArea')
        .layoutWeight(1)
        .height('100%')
        .justifyContent(FlexAlign.Center);

        // Center: question + debug exit.
        this.questionArea();

        // Right: monster card. The sublabel "Monster X / Y" preserves the
        // exact UI-test text assertion.
        Column() {
          CharacterCard({
            kind: CharacterKind.Slime,
            name: this.monsterName,
            hp: this.monsterHp,
            maxHp: this.monsterMaxHp,
            sublabel: `Monster ${this.monsterIndex} / ${this.monsterTotal}`,
          });
        }
        .id('MonsterArea')
        .layoutWeight(1)
        .height('100%')
        .justifyContent(FlexAlign.Center);
      }
      .width('100%')
      .layoutWeight(1)
      .alignItems(VerticalAlign.Center)
      .padding({ left: 20, right: 20, top: 4, bottom: 4 });

      this.optionsRow();
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F8F9FA');
  }
}
