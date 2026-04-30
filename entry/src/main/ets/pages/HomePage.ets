import { router } from '@kit.ArkUI';
import { BusinessError } from '@ohos.base';
import { common } from '@kit.AbilityKit';
import {
  GameConfig,
  GAME_CONFIG_STORAGE_KEY,
  GAME_MODE_REVIEW,
  GAME_MODE_TODAY,
  TODAY_PLAN_STORAGE_KEY,
  TODAY_LAST_COMPLETED_DAY_KEY,
  TODAY_REGION_ID_KEY,
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
import { getTodayPreferences, TodayPreferences } from '../services/TodayPreferences';

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
  /**
   * v0.3.6: when the locked review button is tapped (fewer than 3
   * recent wrong words), surface an inline toast instead of doing
   * nothing. `toastTimer` holds the active setTimeout handle so a
   * rapid second tap can reset the dismissal window cleanly, and
   * `aboutToDisappear` can cancel a pending callback before the
   * page is destroyed.
   */
  @State private reviewLockedToastVisible: boolean = false;
  private toastTimer: number = -1;
  private coins: CoinAccount = getCoinAccount();
  private todayPrefs: TodayPreferences = getTodayPreferences();

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
    this.todayPrefs.init(ctx).then((): void => {
      this.todayPrefs.loadRegionId().then((id: string): void => {
        AppStorage.setOrCreate<string>(TODAY_REGION_ID_KEY, id);
        this.refreshTodayState();
      }).catch((err: BusinessError): void => {
        console.error(`HomePage: TodayPreferences.loadRegionId failed: ${JSON.stringify(err)}`);
      });
    }).catch((err: BusinessError): void => {
      console.error(`HomePage: TodayPreferences.init failed: ${JSON.stringify(err)}`);
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

  aboutToDisappear(): void {
    if (this.toastTimer >= 0) {
      clearTimeout(this.toastTimer);
      this.toastTimer = -1;
    }
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
    const storedRegionId: string | undefined = AppStorage.get<string>(TODAY_REGION_ID_KEY);
    const id: string = storedRegionId !== undefined ? storedRegionId : DEFAULT_REGION_ID;
    this.todayRegion = getRegionById(id);
  }

  private reviewEnabled(): boolean {
    return this.recentWrongCount >= REVIEW_MIN_WRONG_IDS;
  }

  /**
   * Surface a transient inline toast at the top of HomePage when the
   * locked 📚 button is tapped. Self-dismisses after 1.5s; a rapid
   * follow-up tap resets the timer so the toast doesn't disappear
   * mid-message. The HomeReviewLockedToast id is the contract used
   * by HomeToolbarLocked.ui.test.
   */
  private showReviewLockedToast(): void {
    if (this.toastTimer >= 0) {
      clearTimeout(this.toastTimer);
    }
    this.reviewLockedToastVisible = true;
    this.toastTimer = setTimeout((): void => {
      this.reviewLockedToastVisible = false;
      this.toastTimer = -1;
    }, 1500);
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
      const region: AdventureRegion = this.todayRegion;
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

  build(): void {
    Stack() {
      // v0.3.6: single centred column. The legacy right-side
      // Start / Review pair is gone; HomeStartButton is now the
      // adventure-card CTA (see adventureCard() below) and the
      // review entry has moved to the top toolbar.
      Scroll() {
        Column({ space: 0 }) {
          Text('Small Magician Word Adventure')
            .id('HomeTitle')
            .fontSize(32)
            .fontWeight(FontWeight.Bold)
            .margin({ bottom: 24 });

          this.adventureCard();
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .padding({ left: 24, right: 24, top: 72, bottom: 24 });
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Auto);

      // v0.3.6: top-of-screen toast for a tap on the locked 📚 button.
      // Wrapped in a full-width Column with HorizontalAlign.Center so
      // it overrides the outer Stack's TopEnd alignment for this child
      // and lands centred under the toolbar.
      Column() {
        if (this.reviewLockedToastVisible) {
          Text('先答错几题再来复习吧')
            .id('HomeReviewLockedToast')
            .fontSize(14)
            .fontColor('#FFFFFF')
            .backgroundColor('#3A3A3ACC')
            .borderRadius(18)
            .padding({ left: 16, right: 16, top: 8, bottom: 8 });
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .margin({ top: 96 });

      Row({ space: 12 }) {
        Text(`✨ ${this.coinBalance}`)
          .id('HomeCoinBalance')
          .fontSize(16)
          .fontColor('#FFB400')
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .backgroundColor('#FFF6E5')
          .borderRadius(20);

        // V0.3.10: emoji text replaced by an inline Image child. The
        // Button() container syntax keeps the id / size / circular
        // shape / soft-pink background, while letting us render a
        // Recraft-generated rawfile SVG as the glyph. lock state
        // dimming is now handled via .opacity on the Image.
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          Image($rawfile('icons/review.svg'))
            .width(32)
            .height(32)
            .objectFit(ImageFit.Contain)
            .syncLoad(true)
            .opacity(this.reviewEnabled() ? 1.0 : 0.4);
        }
          .id('HomeReviewButton')
          .width(56)
          .height(56)
          .backgroundColor(this.reviewEnabled() ? '#FCEAEA' : '#EEEEEE')
          .onClick((): void => {
            if (this.reviewEnabled()) {
              this.enterReviewMode();
            } else {
              this.showReviewLockedToast();
            }
          });

        Button({ type: ButtonType.Circle, stateEffect: true }) {
          Image($rawfile('icons/codex.svg'))
            .width(32)
            .height(32)
            .objectFit(ImageFit.Contain)
            .syncLoad(true);
        }
          .id('HomeCodexButton')
          .width(56)
          .height(56)
          .backgroundColor('#FCEAEA')
          .onClick((): void => {
            router.pushUrl({ url: 'pages/MonsterCodexPage' }).catch((err: BusinessError): void => {
              console.error(`HomePage: pushUrl MonsterCodexPage failed: ${JSON.stringify(err)}`);
            });
          });

        // V0.4.4: today-plan visibility entry. Uses the 📋 emoji
        // glyph rather than a Recraft SVG to keep the V0.4 series
        // additive against the V0.3.10 icon set; promote to a
        // bespoke SVG in a follow-up if the toolbar needs a uniform
        // visual language.
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          Text('📋')
            .fontSize(28);
        }
          .id('HomePlanButton')
          .width(56)
          .height(56)
          .backgroundColor('#FCEAEA')
          .onClick((): void => {
            router.pushUrl({ url: 'pages/TodayPlanPage' }).catch((err: BusinessError): void => {
              console.error(`HomePage: pushUrl TodayPlanPage failed: ${JSON.stringify(err)}`);
            });
          });

        Button({ type: ButtonType.Circle, stateEffect: true }) {
          Image($rawfile('icons/wishlist.svg'))
            .width(32)
            .height(32)
            .objectFit(ImageFit.Contain)
            .syncLoad(true);
        }
          .id('HomeWishlistButton')
          .width(56)
          .height(56)
          .backgroundColor('#FCEAEA')
          .onClick((): void => {
            router.pushUrl({ url: 'pages/WishlistPage' }).catch((err: BusinessError): void => {
              console.error(`HomePage: pushUrl WishlistPage failed: ${JSON.stringify(err)}`);
            });
          });

        Button({ type: ButtonType.Circle, stateEffect: true }) {
          Image($rawfile('icons/gear.svg'))
            .width(32)
            .height(32)
            .objectFit(ImageFit.Contain)
            .syncLoad(true);
        }
          .id('HomeConfigButton')
          .width(56)
          .height(56)
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
   * `AdventureCard` (the wrapping Column) and `HomeStartButton`
   * (the adventure CTA — single primary entry point as of v0.3.6),
   * so those IDs must stay attached here.
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

      this.regionPicker();

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
        .id('HomeStartButton')
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
    .constraintSize({ maxWidth: 720 })
    .padding(16)
    .backgroundColor(this.todayRegion.bgPrimary)
    .borderRadius(20)
    .border({ width: 1, color: this.todayRegion.bgAccent });
  }

  @Builder
  private regionPicker() {
    // V0.4.6: 5 regions overflow narrow phone widths — wrap the chip
    // row in a horizontal Scroll so the picker scrolls cleanly to
    // surface every region while keeping each `RegionChip_*` id
    // tappable. Width budget: 5 × ~80 dp + 4 × 10 dp ≈ 440 dp.
    Scroll() {
      Row({ space: 10 }) {
        ForEach(ADVENTURE_REGIONS, (r: AdventureRegion): void => {
          Button(r.displayName)
            .id(`RegionChip_${r.id}`)
            .fontSize(13)
            .height(32)
            .padding({ left: 12, right: 12 })
            .backgroundColor(r.id === this.todayRegion.id ? '#E63946' : '#FFFFFF')
            .fontColor(r.id === this.todayRegion.id ? '#FFFFFF' : '#3F2F1A')
            .borderRadius(16)
            .border({ width: 1, color: r.id === this.todayRegion.id ? '#E63946' : '#DDDDDD' })
            .onClick((): void => {
              AppStorage.setOrCreate<string>(TODAY_REGION_ID_KEY, r.id);
              this.todayRegion = r;
              this.todayPrefs.saveRegionId(r.id);
            });
        }, (r: AdventureRegion): string => r.id);
      }
      .padding({ right: 4 });
    }
    .id('RegionPickerScroll')
    .width('100%')
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off);
  }
}
