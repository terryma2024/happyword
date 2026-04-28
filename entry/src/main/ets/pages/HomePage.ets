import { router } from '@kit.ArkUI';
import { BusinessError } from '@ohos.base';
import { common } from '@kit.AbilityKit';
import {
  GameConfig,
  GAME_CONFIG_STORAGE_KEY,
  GAME_MODE_NORMAL,
  GAME_MODE_REVIEW,
  GAME_MODE_TODAY,
  TODAY_PLAN_STORAGE_KEY,
  TODAY_LAST_COMPLETED_DAY_KEY,
  cloneGameConfig
} from '../models/GameConfig';
import { getLearningRecorder } from '../services/LearningRecorder';
import { WordRepository } from '../services/WordRepository';
import { TodayAdventureBuilder, localDayKey } from '../services/TodayAdventureBuilder';
import { ADVENTURE_REGIONS, DEFAULT_REGION_ID, getRegionById } from '../data/AdventureCatalog';
import { AdventureRegion, TodaySessionPlan, MonsterSlot } from '../models/AdventureRegion';
import { describeMonsterKind } from '../services/TodayAdventureBuilder';
import { CoinAccount, getCoinAccount } from '../services/CoinAccount';
import { CoinSnapshot } from '../models/CoinSnapshot';

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
  @State private todayCompleted: boolean = false;
  @State private todayRegion: AdventureRegion = ADVENTURE_REGIONS[0];
  @State private coinBalance: number = 0;
  private coins: CoinAccount = getCoinAccount();

  aboutToAppear(): void {
    const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    this.coins.init(ctx).then((): void => {
      this.coins.beginToday(Date.now());
      this.refreshBalance();
      this.refreshTodayState();
    }).catch((err: BusinessError): void => {
      console.error(`HomePage: CoinAccount.init failed: ${JSON.stringify(err)}`);
      this.refreshTodayState();
    });
    this.refreshWrongCount();
  }

  onPageShow(): void {
    // ArkUI re-invokes onPageShow when navigating back from a pushed
    // page, but not aboutToAppear; refreshing here makes the button
    // light up the instant the battle ends.
    this.coins.beginToday(Date.now());
    this.refreshBalance();
    this.refreshWrongCount();
    this.refreshTodayState();
  }

  private refreshBalance(): void {
    const snap: CoinSnapshot = this.coins.snapshot();
    this.coinBalance = snap.totalCoins - snap.spentCoins;
  }

  private refreshWrongCount(): void {
    this.recentWrongCount =
      getLearningRecorder().recentWrongIds(REVIEW_WINDOW_SIZE).length;
  }

  private refreshTodayState(): void {
    // Prefer the persisted coin-account flag when it's available;
    // fall back to AppStorage so a fresh boot before init() resolves
    // still gets a correct first-frame estimate.
    const todayKey: string = localDayKey(Date.now());
    if (this.coins.todayAdventureCompleted()) {
      this.todayCompleted = true;
    } else {
      const stored: string | undefined =
        AppStorage.get<string>(TODAY_LAST_COMPLETED_DAY_KEY);
      this.todayCompleted = stored !== undefined && stored === todayKey;
    }
    this.todayRegion = getRegionById(DEFAULT_REGION_ID);
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

  private enterTodayAdventure(): void {
    const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    const repo: WordRepository = new WordRepository();
    repo.loadFromRawfile(ctx).then((): void => {
      const builder: TodayAdventureBuilder = new TodayAdventureBuilder();
      const region: AdventureRegion = getRegionById(DEFAULT_REGION_ID);
      const recorder = getLearningRecorder();
      // Init ensures the recorder snapshot is hydrated so the
      // builder sees real review/learning words, not an empty list.
      recorder.init(ctx).then((): void => {
        // Use the persisted coin-account flag — it is the
        // authoritative record of whether the player has finished
        // today's adventure (BattlePage flips it on completion).
        const isFirstToday: boolean = !this.coins.todayAdventureCompleted();
        const plan: TodaySessionPlan =
          builder.build(region, repo, recorder, Date.now(), isFirstToday);
        AppStorage.setOrCreate<TodaySessionPlan>(TODAY_PLAN_STORAGE_KEY, plan);
        const storedCfg: GameConfig | undefined =
          AppStorage.get<GameConfig>(GAME_CONFIG_STORAGE_KEY);
        const cfg: GameConfig = cloneGameConfig(
          storedCfg !== undefined ? storedCfg : new GameConfig());
        cfg.mode = GAME_MODE_TODAY;
        AppStorage.setOrCreate<GameConfig>(GAME_CONFIG_STORAGE_KEY, cfg);
        router.pushUrl({ url: 'pages/BattlePage' }).catch((err: BusinessError): void => {
          console.error(`HomePage: pushUrl BattlePage (today) failed: ${JSON.stringify(err)}`);
        });
      }).catch((err: BusinessError): void => {
        console.error(`HomePage.enterTodayAdventure recorder.init failed: ${JSON.stringify(err)}`);
      });
    }).catch((err: BusinessError): void => {
      console.error(`HomePage.enterTodayAdventure loadFromRawfile failed: ${JSON.stringify(err)}`);
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
      // Two-column layout sized for landscape viewports: the new
      // AdventureCard sits on the left next to the title/subtitle
      // block, and the legacy Start / Review buttons stay on the
      // right where existing UI tests expect to find them on first
      // render. A Scroll wrapper handles smaller portrait viewports
      // (e.g. phones) by allowing the content to scroll vertically.
      Scroll() {
        Row({ space: 32 }) {
          Column() {
            Text('Small Magician Word Adventure')
              .id('HomeTitle')
              .fontSize(32)
              .fontWeight(FontWeight.Bold)
              .margin({ bottom: 8 });

            Text('小魔法师单词冒险')
              .fontSize(20)
              .fontColor('#457B9D')
              .margin({ bottom: 16 });

            this.adventureCard();
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Center);

          Column({ space: 16 }) {
            Text('点击开始，打败 5 个单词史莱姆吧！')
              .fontSize(16)
              .textAlign(TextAlign.Center);

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
          .width(280)
          .alignItems(HorizontalAlign.Center)
          .justifyContent(FlexAlign.Center);
        }
        .width('100%')
        .padding({ left: 24, right: 24, top: 100, bottom: 24 })
        .alignItems(VerticalAlign.Center);
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Auto);

      Row({ space: 12 }) {
        Text(`✨ ${this.coinBalance}`)
          .id('HomeCoinBalance')
          .fontSize(16)
          .fontColor('#FFB400')
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .backgroundColor('#FFF6E5')
          .borderRadius(20);

        Button('🪄')
          .id('HomeWishlistButton')
          .type(ButtonType.Circle)
          .width(56)
          .height(56)
          .fontSize(24)
          .fontColor('#E63946')
          .backgroundColor('#FCEAEA')
          .onClick((): void => {
            router.pushUrl({ url: 'pages/WishlistPage' }).catch((err: BusinessError): void => {
              console.error(`HomePage: pushUrl WishlistPage failed: ${JSON.stringify(err)}`);
            });
          });

        Button('🧪')
          .id('HomeTtsTestButton')
          .type(ButtonType.Circle)
          .width(56)
          .height(56)
          .fontSize(24)
          .fontColor('#457B9D')
          .backgroundColor('#EAF2F8')
          .onClick((): void => {
            router.pushUrl({ url: 'pages/TtsTestPage' }).catch((err: BusinessError): void => {
              console.error(`HomePage: pushUrl TtsTestPage failed: ${JSON.stringify(err)}`);
            });
          });

        Button('⚙')
          .id('HomeConfigButton')
          .type(ButtonType.Circle)
          .width(56)
          .height(56)
          .fontSize(28)
          .fontColor('#457B9D')
          .backgroundColor('#EAF2F8')
          .onClick((): void => {
            router.pushUrl({ url: 'pages/ConfigPage' }).catch((err: BusinessError) => {
              console.error(`HomePage: pushUrl ConfigPage failed: ${JSON.stringify(err)}`);
            });
          });
      }
      .margin({ top: 16, right: 16 });
    }
    .alignContent(Alignment.TopEnd)
    .width('100%')
    .height('100%');
  }

  /**
   * "今日冒险" preview card. Inlined as @Builder (formerly the
   * AdventureCard @Component) per codelinter
   * `avoid-overusing-custom-component-check`. Tests target ID
   * `AdventureCard` (the wrapping Column) and `AdventureCardCta`
   * (the start button), so those IDs must stay attached here.
   */
  @Builder
  private adventureCard() {
    Column({ space: 10 }) {
      Row() {
        Text(this.todayRegion.displayName)
          .id('AdventureCardTitle')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor('#3F2F1A');
        Blank();
        Text(this.todayCompleted ? '已完成' : '今日')
          .id('AdventureCardBadge')
          .fontSize(14)
          .fontColor(this.todayCompleted ? '#7B7B7B' : '#FFFFFF')
          .backgroundColor(this.todayCompleted ? '#E5E5E5' : '#E63946')
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .borderRadius(12);
      }
      .width('100%');

      Row({ space: 8 }) {
        ForEach(this.todayRegion.monsterPlan.slots, (slot: MonsterSlot): void => {
          Text(describeMonsterKind(slot.kind))
            .fontSize(13)
            .fontColor('#3F2F1A')
            .backgroundColor('#FFE7B5')
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .borderRadius(10);
        }, (slot: MonsterSlot, index: number): string => `slot-${index}-${slot.kind}`);
      }
      .width('100%');

      Text('今天的冒险包含 5 关卡，含拼写、复习与首领关')
        .fontSize(14)
        .fontColor('#5A4A35');

      Button(this.todayCompleted ? '再战一局' : '开始今日冒险')
        .id('AdventureCardCta')
        .fontSize(18)
        .width('100%')
        .height(48)
        .backgroundColor('#E63946')
        .fontColor('#FFFFFF')
        .onClick((): void => {
          this.enterTodayAdventure();
        });
    }
    .id('AdventureCard')
    .width('100%')
    .padding(16)
    .backgroundColor(this.todayRegion.bgPrimary)
    .borderRadius(20)
    .border({ width: 1, color: this.todayRegion.bgAccent });
  }
}
