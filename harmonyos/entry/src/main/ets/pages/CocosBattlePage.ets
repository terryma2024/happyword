/**
 * CocosBattlePage — hosts the live Cocos battle scene (V1.1.0 Task 1.5).
 *
 * The page is a thin lifecycle shell; all battle logic lives in services:
 *   - BattleSessionFactory builds the BattleEngine exactly like BattlePage
 *     (same word universe, GameConfig, plan and pack handoff).
 *   - CocosBattleBridge translates engine state/outcomes into bridge
 *     messages for the scene and routes scene intents back into the engine.
 *   - BattleResultEnricher runs the BattlePage-identical finish enrichment
 *     before routing to ResultPage.
 *
 * Lifecycle:
 *   aboutToAppear     boot engine host (fallback to native on throw), init
 *                     stores, build session, construct bridge, arm the 5 s
 *                     ready-timeout fallback.
 *   scene ready       (bridge onReady) cancel the timeout, start the 1 Hz
 *                     countdown driver: engine.tick(1) + bridge.sendStateTick.
 *   onPageShow/Hide   relay to CocosEngineHost page lifecycle.
 *   battle end        bridge onFinish / countdown timeout → enrich + route
 *                     to ResultPage (one replaceUrl per session).
 *   aboutToDisappear  stop timers, bridge.dispose(), clear scene handler,
 *                     audio teardown + best-effort cloud sync (BattlePage
 *                     parity).
 *
 * Fallback contract: any boot failure / build failure / missing battle-ready
 * sets AppStorage[COCOS_BATTLE_FALLBACK_KEY] = true (read by battleRouteUrl
 * and isCocosRuntimeAvailable) and replaces this page with the native
 * BattlePage, which restarts the battle from the same stored GameConfig.
 * Page re-entry is fully supported: the patched engine
 * (cpp/cocos-patches/OpenHarmonyPlatform.cpp) rebinds the swapchain to the
 * re-created XComponent surface, so every battle of the process can run in
 * Cocos.
 *
 * Escape contract: the scene's Escape button sends battle/escape and the
 * bridge finishes immediately — same as the native BattlePage and the iOS
 * CocosBattleBridge (no confirm dialog on any platform).
 */
import { BusinessError } from '@ohos.base';
import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { cocosEngineHost } from '../services/CocosEngineHost';
import {
  CocosBattleBridge,
  CocosBattleBridgeCallbacks,
  CocosTransport,
} from '../services/CocosBattleBridge';
import {
  BattleSessionSetup,
  buildBattleSessionSetup,
  initBattleSessionStores,
} from '../services/BattleSessionFactory';
import {
  BattleResultEnrichmentInputs,
  enrichAndFlushSessionResult,
} from '../services/BattleResultEnricher';
import { COCOS_BATTLE_FALLBACK_KEY } from '../services/CocosBattlePreference';
import { AnswerOutcome, BattleEngine, TickOutcome } from '../services/BattleEngine';
import { GameConfig } from '../models/GameConfig';
import { SessionResult } from '../models/SessionResult';
import { BattleAudioMixer } from '../services/BattleAudioMixer';
import { shouldAutoSpeak } from '../services/PronunciationService';
import { getLearningRecorder, LearningRecorder } from '../services/LearningRecorder';
import {
  getMonsterProgressStore,
  MonsterProgressStore,
} from '../services/MonsterProgressStore';
import {
  DailyLearningStateService,
  getDailyLearningStateService,
} from '../services/DailyLearningStateService';
import { requestPageOrientation } from '../utils/orientation';

/** Must stay in sync with the surface id the Cocos native layer binds to. */
const COCOS_XCOMPONENT_ID: string = 'xcomponentId';
/** Module name registered by the natively compiled engine (libcocos.so). */
const COCOS_LIBRARY_NAME: string = 'cocos';
/** Countdown cadence — BattlePage TICK_MS parity. */
const TICK_MS: number = 1000;
/**
 * If the scene has not sent battle/ready within this window the engine is
 * considered broken and the battle falls back to the native page. Re-entry
 * is immune: CocosEngineHost replays a synthetic ready synchronously when
 * the bridge registers its handler.
 */
const READY_TIMEOUT_MS: number = 5000;

const DOMAIN: number = 0x0000;
const TAG: string = 'CocosBattlePage';

/** Adapts CocosEngineHost's send/handler pair to the bridge transport seam. */
class EngineHostTransport implements CocosTransport {
  send(json: string): void {
    cocosEngineHost().sendToScene(json);
  }

  setHandler(handler: (json: string) => void): void {
    cocosEngineHost().setSceneMessageHandler(handler);
  }
}

/**
 * Bridge callbacks backed by page-injected closures (ArkUI structs cannot be
 * referenced as types, so the page hands its behavior in piecewise).
 */
class PageBridgeCallbacks implements CocosBattleBridgeCallbacks {
  private readonly finishFn: (result: SessionResult) => void;
  private readonly sfxFn: (soundKey: string) => void;
  private readonly speakFn: (word: string) => void;
  private readonly autoSpeakFn: (word: string, questionKind: string) => void;
  private readonly readyFn: () => void;
  private readonly answerOutcomeFn:
    (answeredWordId: string, preAnswerCatalogIndex: number, outcome: AnswerOutcome) => void;

  constructor(
    finishFn: (result: SessionResult) => void,
    sfxFn: (soundKey: string) => void,
    speakFn: (word: string) => void,
    autoSpeakFn: (word: string, questionKind: string) => void,
    readyFn: () => void,
    answerOutcomeFn:
      (answeredWordId: string, preAnswerCatalogIndex: number, outcome: AnswerOutcome) => void,
  ) {
    this.finishFn = finishFn;
    this.sfxFn = sfxFn;
    this.speakFn = speakFn;
    this.autoSpeakFn = autoSpeakFn;
    this.readyFn = readyFn;
    this.answerOutcomeFn = answerOutcomeFn;
  }

  onFinish(result: SessionResult): void {
    this.finishFn(result);
  }

  onAnswerOutcome(answeredWordId: string, preAnswerCatalogIndex: number, outcome: AnswerOutcome): void {
    this.answerOutcomeFn(answeredWordId, preAnswerCatalogIndex, outcome);
  }

  playSfx(soundKey: string): void {
    this.sfxFn(soundKey);
  }

  speakWord(word: string): void {
    this.speakFn(word);
  }

  autoSpeakWord(word: string, questionKind: string): void {
    this.autoSpeakFn(word, questionKind);
  }

  onReady(): void {
    this.readyFn();
  }
}

@Entry
@Component
struct CocosBattlePage {
  private engine: BattleEngine | undefined = undefined;
  private bridge: CocosBattleBridge | undefined = undefined;
  private setup: BattleSessionSetup | undefined = undefined;
  private audio: BattleAudioMixer = new BattleAudioMixer();
  private recorder: LearningRecorder = getLearningRecorder();
  private monsterProgress: MonsterProgressStore = getMonsterProgressStore();
  private dailyStateService: DailyLearningStateService = getDailyLearningStateService();
  private isReviewMode: boolean = false;
  private autoSpeak: boolean = true;
  /** 1 Hz countdown driver; -1 when not running. */
  private tickTimer: number = -1;
  /** battle/ready watchdog; -1 once the scene reported in (or fired). */
  private readyTimeoutTimer: number = -1;
  /** One replaceUrl per session — BattlePage.battleEndHandled parity. */
  private battleEndHandled: boolean = false;
  /** Set once the fallback replaceUrl has been posted. */
  private fallbackTriggered: boolean = false;
  /**
   * Gates the XComponent: false when the engine cannot render (boot
   * failure) so no surface is created on the fallback path. Decided in
   * aboutToAppear, i.e. before the first build().
   */
  @State private engineUsable: boolean = true;
  /**
   * Gates the XComponent until setWindowLayoutFullScreen(true) resolved.
   * expandSafeArea alone is NOT enough for a SURFACE XComponent: ArkUI
   * expands the drawn hole to the window edges, but the native surface is
   * created at the safe-area layout size, so the engine renders short of
   * the bottom avoid area (observed: 2800x1777 surface inside a 2800x1840
   * hole = 63 px dead strip). Creating the surface only after the window
   * layout is fullscreen makes its first size the final one.
   */
  @State private windowReady: boolean = false;

  /**
   * Cocos template parity (cocos/native/.../EntryAbility.ets): games run
   * with the window layout fullscreen so the XComponent surface spans the
   * whole window. Restored to the default on exit so the rest of the app
   * keeps its safe-area-aware layout.
   */
  private setLayoutFullScreen(enabled: boolean, thenShowSurface: boolean): void {
    const ctx: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    window.getLastWindow(ctx).then((win: window.Window): Promise<void> => {
      return win.setWindowLayoutFullScreen(enabled);
    }).then((): void => {
      if (thenShowSurface) {
        this.windowReady = true;
      }
    }).catch((err: BusinessError): void => {
      hilog.warn(DOMAIN, TAG, 'setWindowLayoutFullScreen(%{public}s) failed: %{public}s',
        String(enabled), JSON.stringify(err));
      // Layout fullscreen is cosmetic; never block the battle on it.
      if (thenShowSurface) {
        this.windowReady = true;
      }
    });
  }

  private applyOrientationPolicy(): void {
    requestPageOrientation(
      this.getUIContext().getHostContext() as common.UIAbilityContext,
      'CocosBattlePage',
      (px: number): number => this.getUIContext().px2vp(px),
    );
  }

  aboutToAppear(): void {
    this.applyOrientationPolicy();
    this.setLayoutFullScreen(true, true);
    const ctx: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    // Engine boot is retryable inside the host; a throw here means the
    // native engine could not be initialised at all — go native for the
    // rest of the process lifetime.
    try {
      cocosEngineHost().ensureBooted(ctx);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'engine boot failed: %{public}s', (err as Error).message);
      this.engineUsable = false;
      this.fallbackToNative('boot-failed');
      return;
    }
    initBattleSessionStores(ctx);
    // Arm the ready watchdog before anything async: if the scene never
    // reports battle/ready the player still lands in a playable battle.
    this.readyTimeoutTimer = setTimeout((): void => {
      this.readyTimeoutTimer = -1;
      hilog.error(DOMAIN, TAG, 'no battle/ready within %{public}d ms', READY_TIMEOUT_MS);
      this.fallbackToNative('ready-timeout');
    }, READY_TIMEOUT_MS);
    buildBattleSessionSetup(ctx, (cfg: GameConfig): void => {
      this.autoSpeak = cfg.autoSpeak;
      this.audio.enter(ctx, cfg).catch((err: BusinessError): void => {
        console.error(`CocosBattlePage: BattleAudioMixer.enter failed: ${JSON.stringify(err)}`);
      });
    }).then((setup: BattleSessionSetup): void => {
      if (this.fallbackTriggered || this.battleEndHandled) {
        return;
      }
      this.setup = setup;
      this.engine = setup.engine;
      this.isReviewMode = setup.isReviewMode;
      // First monster of the session counts as encountered the moment the
      // battle is set up — BattlePage parity (recordEncounterForCurrentMonster
      // runs on its first syncFromEngine). recordEncounter is an idempotent
      // flag, so a later native-fallback battle recording it again is harmless.
      this.recordEncounterForCurrentMonster();
      // Constructing the bridge registers the scene handler; on re-entry
      // the host replays a synthetic battle/ready synchronously, which
      // cancels the watchdog and starts the countdown right away.
      this.bridge = new CocosBattleBridge(
        setup.engine,
        new EngineHostTransport(),
        new PageBridgeCallbacks(
          (result: SessionResult): void => {
            this.finishBattle(result);
          },
          (soundKey: string): void => {
            this.audio.play(soundKey);
          },
          (word: string): void => {
            this.audio.speakWord(word);
          },
          (word: string, questionKind: string): void => {
            // BattlePage.maybeAutoSpeakCurrent parity. isRevealing is false:
            // the bridge only auto-speaks when a question swaps in (ready /
            // post-hold), never during the feedback window.
            if (shouldAutoSpeak(this.autoSpeak, this.audio.isVoiceAvailable(), false, questionKind)) {
              this.audio.speakWord(word);
            }
          },
          (): void => {
            this.onSceneReady();
          },
          (answeredWordId: string, preAnswerCatalogIndex: number, outcome: AnswerOutcome): void => {
            this.handleAnswerOutcome(answeredWordId, preAnswerCatalogIndex, outcome);
          },
        ),
        setup.catalogIndexProvider,
      );
    }).catch((err: BusinessError): void => {
      console.error(`CocosBattlePage: session setup failed: ${JSON.stringify(err)}`);
      this.fallbackToNative('setup-failed');
    });
  }

  onPageShow(): void {
    this.applyOrientationPolicy();
    cocosEngineHost().notifyPageShow();
  }

  onPageHide(): void {
    cocosEngineHost().notifyPageHide();
  }

  aboutToDisappear(): void {
    // Give the safe-area-aware pages their reserved avoid areas back.
    this.setLayoutFullScreen(false, false);
    this.clearTimers();
    const bridge: CocosBattleBridge | undefined = this.bridge;
    if (bridge !== undefined) {
      bridge.dispose();
    }
    cocosEngineHost().clearSceneMessageHandler();
    // Best-effort audio teardown — BattlePage parity.
    this.audio.exit().catch((err: BusinessError): void => {
      console.error(`CocosBattlePage: BattleAudioMixer.exit failed: ${JSON.stringify(err)}`);
    });
    // Fire-and-forget cloud sync once a battle ends — BattlePage parity.
    const sync = this.recorder.getCloudSync();
    if (sync !== undefined) {
      sync.syncOnce().catch((err: BusinessError): void => {
        console.error(`CocosBattlePage: cloud sync failed: ${JSON.stringify(err)}`);
      });
    }
  }

  private clearTimers(): void {
    if (this.tickTimer >= 0) {
      clearInterval(this.tickTimer);
      this.tickTimer = -1;
    }
    if (this.readyTimeoutTimer >= 0) {
      clearTimeout(this.readyTimeoutTimer);
      this.readyTimeoutTimer = -1;
    }
  }

  /**
   * Per-answer side effects — the BattlePage-identical block from
   * onOptionTap / handleSpellSubmit (and the iOS
   * AppCoordinator.submitBattleOptionForAnimation): learning record, daily
   * review marking, and monster codex progress. The bridge fires this
   * exactly once per accepted submit, never for medium step advances and
   * never after dispose.
   */
  private handleAnswerOutcome(
    answeredWordId: string,
    preAnswerCatalogIndex: number,
    outcome: AnswerOutcome,
  ): void {
    // Falls through silently if the recorder wasn't ready — BattlePage parity.
    if (answeredWordId.length > 0) {
      this.recorder.recordAnswer(answeredWordId, outcome.correct);
      this.markDailyReviewWordIfNeeded(answeredWordId);
    }
    if (outcome.monsterDefeated && preAnswerCatalogIndex > 0) {
      this.monsterProgress.recordDefeat(preAnswerCatalogIndex);
    }
    if (outcome.newMonsterSpawned) {
      // The engine already advanced, so the provider now resolves the NEW
      // monster's catalog index (iOS recordMonsterProgress parity).
      this.recordEncounterForCurrentMonster();
    }
  }

  /** Mirrors BattlePage.markDailyReviewWordIfNeeded. */
  private markDailyReviewWordIfNeeded(wordId: string): void {
    if (!this.isReviewMode || wordId.length === 0) {
      return;
    }
    this.dailyStateService.markReviewedWords(Date.now(), [wordId])
      .catch((err: BusinessError): void => {
        console.error(`CocosBattlePage: markReviewedWords failed: ${JSON.stringify(err)}`);
      });
  }

  /** Mirrors BattlePage.recordEncounterForCurrentMonster (codex flag). */
  private recordEncounterForCurrentMonster(): void {
    const setup: BattleSessionSetup | undefined = this.setup;
    if (setup === undefined) {
      return;
    }
    const catalogIndex: number = setup.catalogIndexProvider();
    if (catalogIndex <= 0) {
      return;
    }
    this.monsterProgress.recordEncounter(catalogIndex);
  }

  /** First (and every) battle/ready: stop the watchdog, drive the clock. */
  private onSceneReady(): void {
    if (this.readyTimeoutTimer >= 0) {
      clearTimeout(this.readyTimeoutTimer);
      this.readyTimeoutTimer = -1;
    }
    if (this.tickTimer < 0) {
      this.tickTimer = setInterval((): void => {
        this.onTick();
      }, TICK_MS);
    }
  }

  /**
   * Drive the engine's countdown by 1 second and mirror it to the scene.
   * On the tick that ends the battle (time up) finish exactly like
   * BattlePage.onTick: build the result and route — no extra hold.
   */
  private onTick(): void {
    const engine: BattleEngine | undefined = this.engine;
    if (engine === undefined) {
      return;
    }
    const outcome: TickOutcome = engine.tick(1);
    const bridge: CocosBattleBridge | undefined = this.bridge;
    if (bridge !== undefined) {
      bridge.sendStateTick();
    }
    if (outcome.battleEnded) {
      if (this.tickTimer >= 0) {
        clearInterval(this.tickTimer);
        this.tickTimer = -1;
      }
      this.finishBattle(engine.buildSessionResult());
    }
  }

  /**
   * Single battle-end handoff (bridge onFinish, countdown timeout, escape):
   * run the BattlePage-identical enrichment, then replace to ResultPage.
   */
  private finishBattle(result: SessionResult): void {
    if (this.battleEndHandled || this.fallbackTriggered) {
      return;
    }
    this.battleEndHandled = true;
    this.clearTimers();
    // Stop the engine render loop BEFORE the navigation destroys the
    // XComponent surface — an in-flight frame racing the surface destroy
    // aborts the process in eglSwapBuffers (see CocosEngineHost.pauseRendering).
    cocosEngineHost().pauseRendering();
    const setup: BattleSessionSetup | undefined = this.setup;
    const inputs: BattleResultEnrichmentInputs = new BattleResultEnrichmentInputs();
    if (setup !== undefined) {
      inputs.isTodayMode = setup.isTodayMode;
      inputs.todayPlan = setup.todayPlan;
      inputs.activePack = setup.activePack;
    }
    enrichAndFlushSessionResult(
      this.getUIContext().getHostContext() as common.UIAbilityContext,
      result,
      inputs,
    );
    this.getUIContext().getRouter().replaceUrl({
      url: 'pages/ResultPage',
      params: result,
    }).catch((err: BusinessError): void => {
      console.error(`CocosBattlePage: replaceUrl ResultPage failed: ${JSON.stringify(err)}`);
    });
  }

  /**
   * Engine unusable — latch the process-wide fallback flag (the routing
   * layer and isCocosRuntimeAvailable() read it) and restart the battle on
   * the native page.
   */
  private fallbackToNative(reason: string): void {
    if (this.fallbackTriggered || this.battleEndHandled) {
      return;
    }
    this.fallbackTriggered = true;
    this.clearTimers();
    // Same surface-destroy race as finishBattle: halt rendering first.
    cocosEngineHost().pauseRendering();
    hilog.warn(DOMAIN, TAG, 'falling back to native BattlePage (%{public}s)', reason);
    AppStorage.setOrCreate<boolean>(COCOS_BATTLE_FALLBACK_KEY, true);
    const bridge: CocosBattleBridge | undefined = this.bridge;
    if (bridge !== undefined) {
      bridge.dispose();
    }
    this.getUIContext().getRouter().replaceUrl({
      url: 'pages/BattlePage',
    }).catch((err: BusinessError): void => {
      console.error(`CocosBattlePage: replaceUrl BattlePage failed: ${JSON.stringify(err)}`);
    });
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.engineUsable && this.windowReady) {
        XComponent({
          id: COCOS_XCOMPONENT_ID,
          type: XComponentType.SURFACE,
          libraryname: COCOS_LIBRARY_NAME,
        })
          .focusable(true)
          .defaultFocus(true)
          .width('100%')
          .height('100%')
          // Fill the whole window: without this the page reserves the bottom
          // navigation-indicator avoid area, the surface ends up shorter than
          // the window (e.g. 2800x1777 vs 2800x1840 on MatePad) and a dead
          // strip shows below the scene. CUTOUT is safe to expand too: in
          // landscape the camera punch-holes sit over empty scene background
          // at the screen edge, never over content (BattlePage parity —
          // its root Stack expands SYSTEM on all four edges as well).
          .expandSafeArea([SafeAreaType.SYSTEM, SafeAreaType.CUTOUT],
            [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM, SafeAreaEdge.START, SafeAreaEdge.END])
          .onLoad((): void => {
            // Surface is ready — notify the host; it posts onXCLoad at most
            // once and resumes the engine render loop.
            cocosEngineHost().notifySurfaceLoaded();
          })
          .onDestroy((): void => {
            // Surface gone — the host must not resume rendering until the
            // next surface's onLoad (the patched engine rebinds the
            // swapchain to that new surface).
            cocosEngineHost().notifySurfaceDestroyed();
          })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
    // Root expands too so the black backdrop covers the avoid areas even
    // when the surface lags a frame behind (or the fallback path renders
    // without an XComponent).
    .expandSafeArea([SafeAreaType.SYSTEM, SafeAreaType.CUTOUT],
      [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM, SafeAreaEdge.START, SafeAreaEdge.END])
  }
}
