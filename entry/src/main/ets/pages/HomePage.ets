import { router } from '@kit.ArkUI';
import { BusinessError } from '@ohos.base';
import {
  GameConfig,
  GAME_CONFIG_STORAGE_KEY,
  GAME_MODE_NORMAL,
  GAME_MODE_REVIEW,
  cloneGameConfig
} from '../models/GameConfig';
import { getLearningRecorder } from '../services/LearningRecorder';

/**
 * Review-mode gating threshold. Mirrors spec §15 Track D: kids need at
 * least a handful of stored mistakes before a "review" button is
 * meaningful — showing it over an empty store would be frustrating.
 */
const REVIEW_MIN_WRONG_IDS: number = 3;
const REVIEW_WINDOW_SIZE: number = 12;

@Entry
@Component
struct HomePage {
  /**
   * Count of recent wrong wordIds available to review. Refreshed every
   * time the page becomes visible so that navigating back from a
   * finished battle lights up the review button as soon as the player
   * has accrued 3+ wrong answers.
   */
  @State private recentWrongCount: number = 0;

  aboutToAppear(): void {
    this.refreshWrongCount();
  }

  onPageShow(): void {
    // ArkUI re-invokes onPageShow when navigating back from a pushed
    // page, but not aboutToAppear; refreshing here makes the button
    // light up the instant the battle ends.
    this.refreshWrongCount();
  }

  private refreshWrongCount(): void {
    this.recentWrongCount =
      getLearningRecorder().recentWrongIds(REVIEW_WINDOW_SIZE).length;
  }

  private reviewEnabled(): boolean {
    return this.recentWrongCount >= REVIEW_MIN_WRONG_IDS;
  }

  /**
   * Mutate the stored GameConfig to flip into review mode before we
   * route to BattlePage. BattlePage reads `cfg.mode` in aboutToAppear
   * and resets it to normal after the battle ends.
   */
  private enterReviewMode(): void {
    const storedCfg: GameConfig | undefined =
      AppStorage.get<GameConfig>(GAME_CONFIG_STORAGE_KEY);
    const cfg: GameConfig = cloneGameConfig(
      storedCfg !== undefined ? storedCfg : new GameConfig());
    cfg.mode = GAME_MODE_REVIEW;
    AppStorage.setOrCreate<GameConfig>(GAME_CONFIG_STORAGE_KEY, cfg);
    router.pushUrl({ url: 'pages/BattlePage' }).catch((err: BusinessError): void => {
      console.error(`HomePage: pushUrl BattlePage (review) failed: ${JSON.stringify(err)}`);
    });
  }

  private enterNormalMode(): void {
    const storedCfg: GameConfig | undefined =
      AppStorage.get<GameConfig>(GAME_CONFIG_STORAGE_KEY);
    const cfg: GameConfig = cloneGameConfig(
      storedCfg !== undefined ? storedCfg : new GameConfig());
    // Defensive: if someone returned to Home without going through
    // ResultPage, stale review-mode could still be set. Reset here so
    // the primary play button always starts a normal battle.
    cfg.mode = GAME_MODE_NORMAL;
    AppStorage.setOrCreate<GameConfig>(GAME_CONFIG_STORAGE_KEY, cfg);
    router.pushUrl({ url: 'pages/BattlePage' }).catch((err: BusinessError): void => {
      console.error(`HomePage: pushUrl BattlePage failed: ${JSON.stringify(err)}`);
    });
  }

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
          .onClick((): void => this.enterNormalMode());

        Button(this.reviewEnabled() ? '复习错题' : '先答错几题再来复习吧')
          .id('HomeReviewButton')
          .fontSize(this.reviewEnabled() ? 20 : 14)
          .width(260)
          .height(56)
          .margin({ top: 16 })
          .backgroundColor(this.reviewEnabled() ? '#FFB400' : '#CCCCCC')
          .fontColor(this.reviewEnabled() ? '#FFFFFF' : '#666666')
          .enabled(this.reviewEnabled())
          .onClick((): void => {
            if (!this.reviewEnabled()) {
              return;
            }
            this.enterReviewMode();
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
