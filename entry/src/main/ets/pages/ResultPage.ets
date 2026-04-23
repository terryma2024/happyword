import { router } from '@kit.ArkUI';
import { BusinessError } from '@ohos.base';
import { BattleStatus } from '../models/BattleState';
import { SessionResult } from '../models/SessionResult';

/**
 * ResultPage shows the session summary and navigation back to home or a replay.
 *
 * V0.1 scope (per spec §6.4):
 * - Display win/lose, defeated monsters, accuracy, learned word count, stars.
 * - Offer "Play again" and "Back to home" actions.
 *
 * T8 wiring: the page reads a {@link SessionResult} off the router's param
 * bag. If the bag is missing or malformed (e.g. the user deep-links into
 * the page during development), we fall back to a default empty result so
 * the navigation buttons still render — the UX is a bit bare but never
 * broken. Per spec, we never recompute stats here.
 *
 * Uses replaceUrl so the result page is not stacked when users replay
 * repeatedly, matching the rest of the navigation flow.
 */
@Entry
@Component
struct ResultPage {
  @State private result: SessionResult = new SessionResult();

  aboutToAppear(): void {
    // router.getParams() returns unknown; reshape into a SessionResult
    // field-by-field so ArkTS strict mode is satisfied and any missing
    // property stays at the SessionResult default rather than undefined.
    const raw: Object = router.getParams() as Object;
    if (raw === null || raw === undefined) {
      return;
    }
    const incoming: SessionResult = raw as SessionResult;
    const merged: SessionResult = new SessionResult();
    merged.status = incoming.status !== undefined ? incoming.status : merged.status;
    merged.defeatedMonsters = incoming.defeatedMonsters !== undefined ? incoming.defeatedMonsters : merged.defeatedMonsters;
    merged.monstersTotal = incoming.monstersTotal !== undefined ? incoming.monstersTotal : merged.monstersTotal;
    merged.totalAnswers = incoming.totalAnswers !== undefined ? incoming.totalAnswers : merged.totalAnswers;
    merged.correctAnswers = incoming.correctAnswers !== undefined ? incoming.correctAnswers : merged.correctAnswers;
    merged.correctRate = incoming.correctRate !== undefined ? incoming.correctRate : merged.correctRate;
    merged.learnedWordCount = incoming.learnedWordCount !== undefined ? incoming.learnedWordCount : merged.learnedWordCount;
    merged.stars = incoming.stars !== undefined ? incoming.stars : merged.stars;
    this.result = merged;
  }

  private formatPercent(rate: number): string {
    // Round to nearest whole percent — kids don't need decimals and the
    // extra precision looks fussy in the summary.
    return `${Math.round(rate * 100)}%`;
  }

  private headlineText(): string {
    return this.result.status === BattleStatus.Won ? '胜利！' : '挑战失败';
  }

  private headlineColor(): string {
    return this.result.status === BattleStatus.Won ? '#2ECC71' : '#E74C3C';
  }

  /**
   * Render three star glyphs, the first `this.result.stars` filled gold
   * and the rest outlined. Using Text with unicode stars keeps the
   * dependency surface small (no image assets) and reads correctly at
   * tablet/phone sizes.
   */
  @Builder
  private starsRow() {
    Row() {
      ForEach([0, 1, 2], (i: number) => {
        Text(i < this.result.stars ? '★' : '☆')
          .fontSize(44)
          .fontColor(i < this.result.stars ? '#FFB400' : '#BDBDBD')
          .margin({ left: 4, right: 4 });
      }, (i: number) => i.toString());
    }
    .id('ResultStars')
    .justifyContent(FlexAlign.Center)
    .margin({ top: 4, bottom: 16 });
  }

  build(): void {
    Column() {
      Text(this.headlineText())
        .id('ResultTitle')
        .fontSize(32)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.headlineColor())
        .margin({ bottom: 12 });

      this.starsRow();

      Column() {
        Text(`击败怪物：${this.result.defeatedMonsters} / ${this.result.monstersTotal}`)
          .id('ResultDefeated')
          .fontSize(18)
          .margin({ bottom: 8 });
        Text(`答题数：${this.result.correctAnswers} / ${this.result.totalAnswers}`)
          .id('ResultAnswers')
          .fontSize(18)
          .margin({ bottom: 8 });
        Text(`正确率：${this.formatPercent(this.result.correctRate)}`)
          .id('ResultAccuracy')
          .fontSize(18)
          .margin({ bottom: 8 });
        Text(`学习单词：${this.result.learnedWordCount}`)
          .id('ResultLearned')
          .fontSize(18);
      }
      .alignItems(HorizontalAlign.Center)
      .margin({ bottom: 28 });

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
