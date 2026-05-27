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
  TODAY_ACTIVE_PACK_KEY,
  cloneGameConfig
} from '../models/GameConfig';
import { getLearningRecorder } from '../services/LearningRecorder';
import { WordRepository } from '../services/WordRepository';
import { WordPackBootstrapper, BootstrapDeps } from '../services/WordPackBootstrapper';
import { TodayAdventureBuilder, localDayKey, regionFromPack } from '../services/TodayAdventureBuilder';
import {
  DailyLearningState,
  DailyLearningStateService,
  HomeDailyStatus,
  decideHomeDailyStatus,
  getDailyLearningStateService,
} from '../services/DailyLearningStateService';
import { ADVENTURE_REGIONS, DEFAULT_REGION_ID, getRegionById } from '../data/AdventureCatalog';
import { AdventureRegion, TodaySessionPlan, MonsterSlot } from '../models/AdventureRegion';
import { Pack } from '../models/Pack';
import { WordEntry } from '../models/WordEntry';
import { describeMonsterKind } from '../services/TodayAdventureBuilder';
import { persistGameConfigBestEffort } from '../services/GameConfigPersistence';
import {
  anyWordSupportsQuestionTypes,
  sanitizeEnabledQuestionTypes,
} from '../services/BattleQuestionTypePolicy';
import { CoinAccount, getCoinAccount } from '../services/CoinAccount';
import { CoinSnapshot } from '../models/CoinSnapshot';
import { getTodayPreferences, TodayPreferences } from '../services/TodayPreferences';
import { CloudCredentials, CloudCredentialsSnapshot } from '../services/CloudCredentials';
import BuildProfile from 'BuildProfile';
import { VersionTripleTap } from '../services/VersionTripleTap';
import { formatVersionLabel, readVersionInfo, VersionInfo } from '../services/BuildInfo';
import { isDebugBuild } from '../services/ReleaseGate';
import {
  hasPrivacyConsent,
  savePrivacyConsent,
  PRIVACY_POLICY_URL,
  TERMS_OF_SERVICE_URL,
} from '../services/CompliancePolicy';
import { openUrlInAppBrowser } from '../services/SystemBrowser';
import { requestPageOrientation } from '../utils/orientation';
import {
  HomeIntegrationBundle,
  fallbackPacks,
  loadHomeIntegration,
  resolveActivePacks,
  resolveTodayAdventurePack,
} from '../services/PackHomeIntegration';

/**
 * Route params bag for `pages/DevMenuPage`. ArkTS strict mode rejects
 * inline object literals (arkts-no-untyped-obj-literals), so we use
 * a small class with default-initialised public fields and pass an
 * instance — same pattern as LessonReviewRouteParams elsewhere.
 */
class DevMenuRouteParams {
  presetEnv: string = '';
}

@Entry
@Component
struct HomePage {
  @State private todayCompleted: boolean = false;
  @State private dailyStatusLabel: string = '请选择一个场景加战斗';
  @State private dailyReviewRemainingCount: number = 0;
  @State private dailyReviewCountBadgeVisible: boolean = false;
  /**
   * V0.6.5.1: the chip row's currently-selected Pack. `todayRegion` is
   * derived from this on every render so the legacy region-shaped UI
   * fields (bgPrimary, bgAccent, monsterPlan, bossName) keep working.
   * Initial value is the first bundled fallback Pack (Fruit Forest);
   * `loadHomeIntegration` swaps in the real PackLibrary asynchronously.
   */
  @State private chipPacks: Pack[] = fallbackPacks();
  @State private todayPack: Pack = fallbackPacks()[0];
  @State private todayRegion: AdventureRegion = ADVENTURE_REGIONS[0];
  /**
   * Bumped on every successful loadHomeIntegration / setActiveIds /
   * togglePin / pruneAgainstLibrary call. ArkUI does not track through
   * helper methods, so the @Builder closures read this field to force
   * a re-render after async chip-set changes (including adventure card copy).
   */
  @State private packLibraryVersion: number = 0;
  private homeIntegration: HomeIntegrationBundle = new HomeIntegrationBundle();
  @State private coinBalance: number = 0;
  /**
   * v0.3.6: when the locked review button is tapped (no recent wrong
   * words), surface an inline toast instead of doing
   * nothing. `toastTimer` holds the active setTimeout handle so a
   * rapid second tap can reset the dismissal window cleanly, and
   * `aboutToDisappear` can cancel a pending callback before the
   * page is destroyed.
   */
  @State private reviewLockedToastVisible: boolean = false;
  private toastTimer: number = -1;
  @State private battleBlockedToastText: string = '';
  private battleBlockedToastTimer: number = -1;
  private coins: CoinAccount = getCoinAccount();
  private todayPrefs: TodayPreferences = getTodayPreferences();
  private dailyStateService: DailyLearningStateService = getDailyLearningStateService();
  // V0.6.2: top-right child badge ("<avatarEmoji> <nickname>") when the device
  // is bound to a parent account. Emoji matches CloudCredentials (same as
  // BoundDeviceInfoPage). Refreshed on aboutToAppear/onPageShow.
  @State private boundChildNickname: string = '';
  @State private boundChildAvatarEmoji: string = '🦄';
  private cloudCreds: CloudCredentials = new CloudCredentials();
  // Debug-only top-left version label. Empty in release builds — the
  // hydration call in aboutToAppear is gated on BuildProfile.BUILD_MODE_NAME.
  @State private versionLabel: string = '';
  private versionTap: VersionTripleTap = new VersionTripleTap();
  @State private privacyConsentVisible: boolean = false;
  private privacyConsentSaving: boolean = false;

  private applyOrientationPolicy(): void {
    requestPageOrientation(
      this.getUIContext().getHostContext() as common.UIAbilityContext,
      'HomePage',
      (px: number): number => this.getUIContext().px2vp(px),
    );
  }

  aboutToAppear(): void {
    this.applyOrientationPolicy();
    const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
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
    this.cloudCreds.init(ctx).then((): Promise<void> => this.refreshBoundChild())
      .catch((err: BusinessError): void => {
        console.error(`HomePage: CloudCredentials.init failed: ${JSON.stringify(err)}`);
      });
    hasPrivacyConsent(ctx).then((accepted: boolean): void => {
      this.privacyConsentVisible = !accepted;
    }).catch((err: BusinessError): void => {
      console.error(`HomePage: hasPrivacyConsent failed: ${JSON.stringify(err)}`);
      this.privacyConsentVisible = true;
    });
    // V0.6.5.1: load the unified PackLibrary + selection on first
    // appearance. The chip row falls back to the bundled
    // ADVENTURE_REGIONS until this resolves so the first paint is
    // never empty.
    loadHomeIntegration(ctx).then((bundle: HomeIntegrationBundle): void => {
      this.homeIntegration = bundle;
      this.applyActivePacks();
      this.refreshDailyLearningState(ctx);
    }).catch((err: BusinessError): void => {
      console.error(`HomePage: loadHomeIntegration failed: ${JSON.stringify(err)}`);
    });
    if (isDebugBuild(BuildProfile.BUILD_MODE_NAME)) {
      readVersionInfo().then((v: VersionInfo): void => {
        this.versionLabel = formatVersionLabel(v);
      }).catch((err: BusinessError): void => {
        console.error(`HomePage.readVersionInfo failed: ${JSON.stringify(err)}`);
      });
    }
  }

  private async refreshBoundChild(): Promise<void> {
    const snap: CloudCredentialsSnapshot = await this.cloudCreds.load();
    if (snap.isBound()) {
      this.boundChildNickname = snap.nickname.length > 0 ? snap.nickname : '宝贝';
      this.boundChildAvatarEmoji = snap.avatarEmoji.length > 0 ? snap.avatarEmoji : '🦄';
    } else {
      this.boundChildNickname = '';
      this.boundChildAvatarEmoji = '🦄';
    }
  }

  private openComplianceUrl(url: string): void {
    openUrlInAppBrowser(this.getUIContext(), url).catch((err: Error): void => {
      console.error(`HomePage.openComplianceUrl failed: ${err.message}`);
    });
  }

  private acceptPrivacyConsent(): void {
    if (this.privacyConsentSaving) {
      return;
    }
    this.privacyConsentSaving = true;
    const ctx: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    savePrivacyConsent(ctx).then((ok: boolean): void => {
      if (ok) {
        this.privacyConsentVisible = false;
      }
      this.privacyConsentSaving = false;
    }).catch((err: BusinessError): void => {
      console.error(`HomePage.acceptPrivacyConsent failed: ${JSON.stringify(err)}`);
      this.privacyConsentSaving = false;
    });
  }

  onPageShow(): void {
    this.applyOrientationPolicy();
    // ArkUI re-invokes onPageShow when navigating back from a pushed
    // page, but not aboutToAppear; refreshing here makes the button
    // light up the instant the battle ends.
    this.coins.beginToday(Date.now());
    this.refreshBalance();
    this.refreshTodayState();
    this.refreshBoundChild().catch((err: BusinessError): void => {
      console.error(`HomePage: refreshBoundChild failed: ${JSON.stringify(err)}`);
    });
    // V0.6.5.1: ConfigPage / PackManagerPage may have changed the
    // active set or pinned a pack while we were away. Re-apply on
    // every page-show so the chip row reflects the latest selection.
    //
    // V0.6.7.4: PackManagerPage / ConfigPage build their own
    // `loadHomeIntegration` bundle, so the `selection` instance
    // they mutate is *not* the same `PackSelectionService` HomePage
    // cached in `aboutToAppear`. Calling `applyActivePacks()` alone
    // would read stale activeIds and toggling packs in the manager
    // would have no visible effect on the chip row or AdventureCard.
    // Reload the bundle on every onPageShow — `loadHomeIntegration`
    // re-reads the (typically warm) PackLibrary plus a single
    // preferences blob via PackSelectionService.init, so the cost is
    // small but the propagation guarantee is now correct.
    const ctxShow: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    loadHomeIntegration(ctxShow).then((bundle: HomeIntegrationBundle): void => {
      this.homeIntegration = bundle;
      this.applyActivePacks();
      this.refreshDailyLearningState(ctxShow);
    }).catch((err: BusinessError): void => {
      console.error(`HomePage: loadHomeIntegration on show failed: ${JSON.stringify(err)}`);
    });
  }

  aboutToDisappear(): void {
    if (this.toastTimer >= 0) {
      clearTimeout(this.toastTimer);
      this.toastTimer = -1;
    }
    if (this.battleBlockedToastTimer >= 0) {
      clearTimeout(this.battleBlockedToastTimer);
      this.battleBlockedToastTimer = -1;
    }
  }

  private refreshBalance(): void {
    const snap: CoinSnapshot = this.coins.snapshot();
    this.coinBalance = snap.totalCoins - snap.spentCoins;
  }

  private refreshDailyLearningState(ctx: common.UIAbilityContext): void {
    const recorder = getLearningRecorder();
    recorder.init(ctx).then(async (): Promise<void> => {
      await this.dailyStateService.init(ctx);
      const words: WordEntry[] = this.activePackWords();
      const selectedIds: string[] = [];
      for (let i = 0; i < this.todayPack.words.length; i++) {
        selectedIds.push(this.todayPack.words[i].id);
      }
      const state: DailyLearningState = await this.dailyStateService.ensureForDay(
        words,
        recorder.allStats(),
        Date.now(),
        selectedIds,
      );
      this.applyDailyStatus(state);
    }).catch((err: BusinessError): void => {
      console.error(`HomePage.refreshDailyLearningState failed: ${JSON.stringify(err)}`);
    });
  }

  private activePackWords(): WordEntry[] {
    const out: WordEntry[] = [];
    const seen: string[] = [];
    for (let i = 0; i < this.chipPacks.length; i++) {
      const words: WordEntry[] = this.chipPacks[i].words;
      for (let j = 0; j < words.length; j++) {
        if (words[j].id.length > 0 && seen.indexOf(words[j].id) < 0) {
          seen.push(words[j].id);
          out.push(words[j]);
        }
      }
    }
    return out;
  }

  private applyDailyStatus(state: DailyLearningState): void {
    const status: HomeDailyStatus = decideHomeDailyStatus(state);
    this.dailyStatusLabel = status.label;
    this.dailyReviewRemainingCount = status.remainingReviewCount;
    this.dailyReviewCountBadgeVisible = status.dailyCheckInCompleted && status.remainingReviewCount > 0;
    this.todayCompleted = status.todayAdventureCompleted;
  }

  /**
   * V0.6.7.5: HomePage labels — the `AdventureCardTitle` heading and
   * the chip row — follow PackManagerPage's English convention
   * (V0.6.7 spec: 词包名字用英文). `region.displayName` is sourced
   * from `pack.name` via `regionFromPack`.
   */
  private regionLabel(region: AdventureRegion): string {
    return region.displayName;
  }

  /**
   * Prefer `Pack.scene.storyZh` from the active chip whose id matches
   * `region.id` (global / family packs hydrated from server JSON).
   */
  private regionStory(region: AdventureRegion): string {
    for (let i = 0; i < this.chipPacks.length; i++) {
      if (this.chipPacks[i].id === region.id) {
        const zh: string | undefined = this.chipPacks[i].scene.storyZh;
        if (zh !== undefined && zh.length > 0) {
          return zh;
        }
        break;
      }
    }
    return '今天的冒险包含 5 关卡，含拼写、复习与首领关';
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
    // V0.6.5.1: persisted region id is now a pack id. Keep the legacy
    // AdventureRegion lookup as a render fallback before
    // loadHomeIntegration resolves; once it does, applyActivePacks
    // overwrites todayPack / todayRegion with the canonical Pack.
    const storedRegionId: string | undefined = AppStorage.get<string>(TODAY_REGION_ID_KEY);
    const id: string = storedRegionId !== undefined ? storedRegionId : DEFAULT_REGION_ID;
    this.todayRegion = getRegionById(id);
  }

  /**
   * Recompute `chipPacks` (the active subset) and `todayPack` /
   * `todayRegion` from the home-integration bundle. Idempotent — safe
   * to call from `aboutToAppear`, `onPageShow`, or after a chip tap.
   * Bumps `packLibraryVersion` so @Builder closures re-render.
   */
  private applyActivePacks(): void {
    const active: Pack[] = resolveActivePacks(this.homeIntegration);
    if (active.length === 0) {
      // Library not yet loaded or selection is empty after a delete.
      // Fall back to the bundled regions so the chip row never empties.
      this.chipPacks = fallbackPacks();
    } else {
      this.chipPacks = active;
    }
    const persistedId: string | undefined = AppStorage.get<string>(TODAY_REGION_ID_KEY);
    let chosen: Pack = this.chipPacks[0];
    if (persistedId !== undefined) {
      for (let i = 0; i < this.chipPacks.length; i++) {
        if (this.chipPacks[i].id === persistedId) {
          chosen = this.chipPacks[i];
          break;
        }
      }
    }
    this.todayPack = chosen;
    this.todayRegion = regionFromPack(chosen);
    this.packLibraryVersion = this.packLibraryVersion + 1;
  }

  private reviewEnabled(): boolean {
    return this.dailyReviewRemainingCount > 0;
  }

  /**
   * Surface a transient inline toast at the top of HomePage when the
   * locked 📚 button is tapped. Self-dismisses after 1.5s; a rapid
   * follow-up tap resets the timer so the toast doesn't disappear
   * mid-message. The HomeReviewEmptyToast id is the contract used
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

  private showBattleBlockedToast(text: string): void {
    if (this.battleBlockedToastTimer >= 0) {
      clearTimeout(this.battleBlockedToastTimer);
    }
    this.battleBlockedToastText = text;
    this.battleBlockedToastTimer = setTimeout((): void => {
      this.battleBlockedToastText = '';
      this.battleBlockedToastTimer = -1;
    }, 1800);
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
    persistGameConfigBestEffort(this.getUIContext().getHostContext() as common.UIAbilityContext, cfg);
    this.getUIContext().getRouter().pushUrl({ url: 'pages/BattlePage' }).catch((err: BusinessError): void => {
      console.error(`HomePage: pushUrl BattlePage (review) failed: ${JSON.stringify(err)}`);
    });
  }

  private enterTodayAdventure(): void {
    const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const router = this.getUIContext().getRouter();
    const recorder = getLearningRecorder();
    const storedCfgForTypes: GameConfig | undefined =
      AppStorage.get<GameConfig>(GAME_CONFIG_STORAGE_KEY);
    const selectedQuestionTypes: string[] = sanitizeEnabledQuestionTypes(
      storedCfgForTypes !== undefined
        ? storedCfgForTypes.enabledQuestionTypes
        : new GameConfig().enabledQuestionTypes
    );
    recorder.init(ctx).then(async (): Promise<void> => {
      let pack: Pack = this.todayPack;
      if (pack.words.length === 0) {
        const refreshed: HomeIntegrationBundle = await loadHomeIntegration(ctx);
        this.homeIntegration = refreshed;
        this.applyActivePacks();
        const persistedId: string | undefined = AppStorage.get<string>(TODAY_REGION_ID_KEY);
        pack = resolveTodayAdventurePack(refreshed, this.todayPack, persistedId);
        if (pack.words.length > 0) {
          this.todayPack = pack;
          this.todayRegion = regionFromPack(pack);
          this.packLibraryVersion = this.packLibraryVersion + 1;
        }
      }
      const builder: TodayAdventureBuilder = new TodayAdventureBuilder();
      const isFirstToday: boolean = !this.coins.todayAdventureCompleted();
      let plan: TodaySessionPlan;
      let activePack: Pack | undefined = undefined;
      if (pack.words.length > 0) {
        if (!anyWordSupportsQuestionTypes(pack.words, selectedQuestionTypes)) {
          this.showBattleBlockedToast('Current pack has no words for selected question types');
          return;
        }
        // V0.6.5.1 happy path: pack carries its own words (any of the
        // 5 builtins, or a global / family pack with words). Build
        // the plan straight from the pack so BattlePage can resolve
        // every word id against `pack.words`.
        plan = builder.buildFromPack(pack, recorder, Date.now(), isFirstToday, selectedQuestionTypes);
        activePack = pack;
      } else {
        // Synthetic fallback Pack (no words) — happens if a chip is
        // tapped before loadHomeIntegration resolves. Fall back to
        // the legacy region+repo path so the battle still launches.
        const deps: BootstrapDeps = await WordPackBootstrapper.forContext(ctx);
        const repo: WordRepository = await new WordPackBootstrapper().bootstrap(deps);
        const region: AdventureRegion = this.todayRegion;
        if (!anyWordSupportsQuestionTypes(repo.all(), selectedQuestionTypes)) {
          this.showBattleBlockedToast('Current pack has no words for selected question types');
          return;
        }
        plan = builder.build(region, repo, recorder, Date.now(), isFirstToday, selectedQuestionTypes);
      }
      AppStorage.setOrCreate<TodaySessionPlan>(TODAY_PLAN_STORAGE_KEY, plan);
      if (activePack !== undefined) {
        AppStorage.setOrCreate<Pack>(TODAY_ACTIVE_PACK_KEY, activePack);
      } else {
        // Clear any stale value so BattlePage doesn't read a previous
        // session's pack when we're on the legacy fallback path.
        AppStorage.delete(TODAY_ACTIVE_PACK_KEY);
      }
      const storedCfg: GameConfig | undefined =
        AppStorage.get<GameConfig>(GAME_CONFIG_STORAGE_KEY);
      const cfg: GameConfig = cloneGameConfig(
        storedCfg !== undefined ? storedCfg : new GameConfig());
      cfg.mode = GAME_MODE_TODAY;
      AppStorage.setOrCreate<GameConfig>(GAME_CONFIG_STORAGE_KEY, cfg);
      persistGameConfigBestEffort(ctx, cfg);
      router.pushUrl({ url: 'pages/BattlePage' }).catch((err: BusinessError): void => {
        console.error(`HomePage: pushUrl BattlePage (today) failed: ${JSON.stringify(err)}`);
      });
    }).catch((err: BusinessError): void => {
      console.error(`HomePage.enterTodayAdventure recorder.init failed: ${JSON.stringify(err)}`);
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
            .margin({ bottom: 8 });

          this.adventureCard();
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        // Extra top inset so HomeTitle clears notch / status bar in landscape.
        .padding({ left: 24, right: 24, top: 96, bottom: 24 });
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
          Text('今天没有待复习单词')
            .id('HomeReviewEmptyToast')
            .fontSize(14)
            .fontColor('#FFFFFF')
            .backgroundColor('#E63A3A3A')
            .borderRadius(18)
            .padding({ left: 16, right: 16, top: 8, bottom: 8 });
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .margin({ top: 96 });

      Column() {
        if (this.battleBlockedToastText.length > 0) {
          Text(this.battleBlockedToastText)
            .id('HomeQuestionTypeBlockedToast')
            .fontSize(14)
            .fontColor('#FFFFFF')
            .backgroundColor('#E63A3A3A')
            .borderRadius(18)
            .padding({ left: 16, right: 16, top: 8, bottom: 8 });
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .margin({ top: 144 });

      Row({ space: 12 }) {
        if (this.boundChildNickname.length > 0) {
          // V0.6.9: tapping the badge jumps to BoundDeviceInfoPage
          // (孩子档案), where the kid can edit the nickname. Same
          // route ConfigPage's "孩子档案" entry uses, so back-nav
          // and refresh-on-show behave identically.
          Text(`${this.boundChildAvatarEmoji} ${this.boundChildNickname}`)
            .id('HomeBoundChildBadge')
            .fontSize(14)
            .fontColor('#0369A1')
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .backgroundColor('#E0F2FE')
            .borderRadius(20)
            .onClick((): void => {
              this.getUIContext().getRouter().pushUrl({ url: 'pages/BoundDeviceInfoPage' }).catch((err: BusinessError): void => {
                console.error(`HomePage: pushUrl BoundDeviceInfoPage failed: ${JSON.stringify(err)}`);
              });
            });
        }
        Text(`✨ ${this.coinBalance}`)
          .id('HomeCoinBalance')
          .fontSize(16)
          .fontColor('#B45309')
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .backgroundColor('#FFF6E5')
          .borderRadius(20);

        // V0.3.10: emoji text replaced by an inline Image child. The
        // Button() container syntax keeps the id / size / circular
        // shape / soft-pink background, while letting us render a
        // Recraft-generated rawfile glyph. lock state dimming is
        // handled via .opacity on the Image.
        //
        // V0.5 follow-up: the four toolbar icons were originally
        // rawfile SVGs (58–141 KB / ~120 paths each). Even with
        // syncLoad(true) the SVG rasterizer would occasionally yield
        // a placeholder square on remount (back-nav from any pushed
        // page), which the user reads as the icon "reverting to an
        // emoji". Pre-rasterized 96×96 PNGs decode reliably and stay
        // stable across remounts; the original SVGs are kept on
        // disk as the design source.
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          Stack() {
            Image($rawfile('icons/review.png'))
              .width(32)
              .height(32)
              .objectFit(ImageFit.Contain)
              .syncLoad(true)
              .opacity(this.reviewEnabled() ? 1.0 : 0.4);
            if (this.dailyReviewCountBadgeVisible) {
              Text(`${this.dailyReviewRemainingCount}`)
                .id('HomeReviewCountBadge')
                .fontSize(11)
                .fontColor('#FFFFFF')
                .backgroundColor('#E63946')
                .borderRadius(9)
                .padding({ left: 5, right: 5, top: 2, bottom: 2 })
                .align(Alignment.TopEnd);
            }
          }
          .width(40)
          .height(40);
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
          Image($rawfile('icons/codex.png'))
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
            this.getUIContext().getRouter().pushUrl({ url: 'pages/MonsterCodexPage' }).catch((err: BusinessError): void => {
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
            this.getUIContext().getRouter().pushUrl({ url: 'pages/TodayPlanPage' }).catch((err: BusinessError): void => {
              console.error(`HomePage: pushUrl TodayPlanPage failed: ${JSON.stringify(err)}`);
            });
          });

        Button({ type: ButtonType.Circle, stateEffect: true }) {
          Image($rawfile('icons/wishlist.png'))
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
            this.getUIContext().getRouter().pushUrl({ url: 'pages/WishlistPage' }).catch((err: BusinessError): void => {
              console.error(`HomePage: pushUrl WishlistPage failed: ${JSON.stringify(err)}`);
            });
          });

        Button({ type: ButtonType.Circle, stateEffect: true }) {
          Image($rawfile('icons/gear.png'))
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
            this.getUIContext().getRouter().pushUrl({ url: 'pages/ConfigPage' }).catch((err: BusinessError): void => {
              console.error(`HomePage: pushUrl ConfigPage failed: ${JSON.stringify(err)}`);
            });
          });
      }
      .margin({ top: 16, right: 16 });

      // Debug-only version label, top-left. Wrapped in a
      // Column().alignItems(HorizontalAlign.Start).width('100%') so it
      // ignores the outer Stack's TopEnd alignment and anchors left.
      // Triple-tap (≤1000ms window) navigates to DevMenuPage with the
      // PREVIEW environment pre-selected. Production / release builds
      // never render or hydrate this — see aboutToAppear gate.
      if (isDebugBuild(BuildProfile.BUILD_MODE_NAME)) {
        Column() {
          Text(this.versionLabel)
            .id('HomeVersionLabel')
            .fontSize(11)
            .fontColor('#999999')
            .padding({ left: 16, top: 16, right: 16, bottom: 8 })
            .onClick((): void => {
              if (this.versionTap.onTap(Date.now())) {
                const params: DevMenuRouteParams = new DevMenuRouteParams();
                params.presetEnv = 'preview';
                this.getUIContext().getRouter().pushUrl({
                  url: 'pages/DevMenuPage',
                  params: params,
                }).catch((err: BusinessError): void => {
                  console.error(`HomePage: pushUrl DevMenuPage (triple-tap) failed: ${JSON.stringify(err)}`);
                });
              }
            });
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%');
      }

      if (this.privacyConsentVisible) {
        this.privacyConsentOverlay();
      }
    }
    .alignContent(Alignment.TopEnd)
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM,
      SafeAreaEdge.START, SafeAreaEdge.END]);
  }

  @Builder
  private privacyConsentOverlay() {
    Column() {
      Column({ space: 12 }) {
        Text('请阅读并同意隐私政策')
          .id('PrivacyConsentTitle')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1F2937');
        Text('魔法背单词会在家长绑定、学习同步、课本图片导入和愿望兑换时处理必要信息。继续使用前，请阅读《用户协议》和《隐私政策》。')
          .id('PrivacyConsentBody')
          .fontSize(15)
          .fontColor('#374151')
          .lineHeight(22);
        Row({ space: 12 }) {
          Button('用户协议')
            .id('PrivacyConsentTermsButton')
            .height(40)
            .backgroundColor('#EAF2F8')
            .fontColor('#1D4ED8')
            .onClick((): void => this.openComplianceUrl(TERMS_OF_SERVICE_URL));
          Button('隐私政策')
            .id('PrivacyConsentPolicyButton')
            .height(40)
            .backgroundColor('#EAF2F8')
            .fontColor('#1D4ED8')
            .onClick((): void => this.openComplianceUrl(PRIVACY_POLICY_URL));
        }
        .justifyContent(FlexAlign.Center)
        .width('100%');
        Button('同意并继续')
          .id('PrivacyConsentAgreeButton')
          .height(44)
          .width('100%')
          .backgroundColor('#E63946')
          .fontColor('#FFFFFF')
          .onClick((): void => this.acceptPrivacyConsent());
      }
      .id('PrivacyConsentDialog')
      .width(520)
      .constraintSize({ maxWidth: '86%' })
      .padding(24)
      .backgroundColor('#FFFFFEFB')
      .border({ width: 2, color: '#FFD28A' })
      .borderRadius(18)
      .shadow({ radius: 24, color: '#33000000', offsetX: 0, offsetY: 10 });
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('#80000000')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM,
      SafeAreaEdge.START, SafeAreaEdge.END])
    .zIndex(20);
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
        // Read packLibraryVersion so ArkUI re-runs the builder after chip / pack loads.
        Text(this.packLibraryVersion >= 0 ? this.regionLabel(this.todayRegion) : this.todayRegion.displayName)
          .id('AdventureCardTitle')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor('#3F2F1A');
        Blank();
        Text(this.dailyStatusLabel)
          .id('AdventureCardDailyStatusLabel')
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

      Text(this.packLibraryVersion >= 0 ? this.regionStory(this.todayRegion) : '今天的冒险包含 5 关卡，含拼写、复习与首领关')
        .id('AdventureCardStory')
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

  /**
   * V0.6.7.5: chip label is the English `p.name` to match
   * PackManagerPage. Previously this preferred `p.labelZh` (Chinese)
   * and fell through to the category-catalog overlay, which produced
   * the mixed-language chip row reported as a bug — `animal-safari`
   * / `ocean-realm` had global overrides with empty `description`
   * (so labelZh was blanked) and rendered in English, while the
   * rest stayed in Chinese. Locking the chip text to `p.name` makes
   * the row deterministic and consistent with the 我的词包 page.
   */
  private packChipLabel(p: Pack): string {
    if (p.name.length > 0) return p.name;
    return p.id;
  }

  @Builder
  private regionPicker() {
    // V0.6.5.1: chip set is now driven by PackSelectionService.getActiveIds()
    // resolved through the merged PackLibrary; chip ids stay stable
    // (RegionChip_<id>) so existing UI tests keep targeting them.
    Scroll() {
      Row({ space: 10 }) {
        ForEach(this.chipPacks, (p: Pack): void => {
          Button(this.packLibraryVersion >= 0 ? this.packChipLabel(p) : p.name)
            .id(`RegionChip_${p.id}`)
            .fontSize(13)
            .height(32)
            .padding({ left: 12, right: 12 })
            .backgroundColor(p.id === this.todayPack.id ? '#E63946' : '#FFFFFF')
            .fontColor(p.id === this.todayPack.id ? '#FFFFFF' : '#3F2F1A')
            .borderRadius(16)
            .border({ width: 1, color: p.id === this.todayPack.id ? '#E63946' : '#DDDDDD' })
            .onClick((): void => {
              AppStorage.setOrCreate<string>(TODAY_REGION_ID_KEY, p.id);
              this.todayPack = p;
              this.todayRegion = regionFromPack(p);
              this.todayPrefs.saveRegionId(p.id).catch((err: BusinessError): void => {
                console.error(`HomePage: TodayPreferences.saveRegionId failed: ${JSON.stringify(err)}`);
              });
            });
        }, (p: Pack): string => p.id);
      }
      .padding({ right: 4 });
    }
    .id('RegionPickerScroll')
    .width('100%')
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off);
  }
}
