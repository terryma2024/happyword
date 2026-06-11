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
 *
 * Escape contract: the scene's Escape button sends battle/escape and the
 * bridge finishes immediately — same as the native BattlePage and the iOS
 * CocosBattleBridge (no confirm dialog on any platform).
 */
import { BusinessError } from '@ohos.base';
import { common } from '@kit.AbilityKit';
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
import { BattleEngine, TickOutcome } from '../services/BattleEngine';
import { GameConfig } from '../models/GameConfig';
import { SessionResult } from '../models/SessionResult';
import { BattleAudioMixer } from '../services/BattleAudioMixer';
import { shouldAutoSpeak } from '../services/PronunciationService';
import { getLearningRecorder, LearningRecorder } from '../services/LearningRecorder';
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

  constructor(
    finishFn: (result: SessionResult) => void,
    sfxFn: (soundKey: string) => void,
    speakFn: (word: string) => void,
    autoSpeakFn: (word: string, questionKind: string) => void,
    readyFn: () => void,
  ) {
    this.finishFn = finishFn;
    this.sfxFn = sfxFn;
    this.speakFn = speakFn;
    this.autoSpeakFn = autoSpeakFn;
    this.readyFn = readyFn;
  }

  onFinish(result: SessionResult): void {
    this.finishFn(result);
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
  private autoSpeak: boolean = true;
  /** 1 Hz countdown driver; -1 when not running. */
  private tickTimer: number = -1;
  /** battle/ready watchdog; -1 once the scene reported in (or fired). */
  private readyTimeoutTimer: number = -1;
  /** One replaceUrl per session — BattlePage.battleEndHandled parity. */
  private battleEndHandled: boolean = false;
  /** Set once the fallback replaceUrl has been posted. */
  private fallbackTriggered: boolean = false;

  private applyOrientationPolicy(): void {
    requestPageOrientation(
      this.getUIContext().getHostContext() as common.UIAbilityContext,
      'CocosBattlePage',
      (px: number): number => this.getUIContext().px2vp(px),
    );
  }

  aboutToAppear(): void {
    this.applyOrientationPolicy();
    const ctx: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    // Engine boot is retryable inside the host; a throw here means the
    // native engine could not be initialised at all — go native for the
    // rest of the process lifetime.
    try {
      cocosEngineHost().ensureBooted(ctx);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'engine boot failed: %{public}s', (err as Error).message);
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
      XComponent({
        id: COCOS_XCOMPONENT_ID,
        type: XComponentType.SURFACE,
        libraryname: COCOS_LIBRARY_NAME,
      })
        .focusable(true)
        .defaultFocus(true)
        .width('100%')
        .height('100%')
        .onLoad((): void => {
          // Surface is ready — notify the host; it posts onXCLoad at most once.
          cocosEngineHost().notifySurfaceLoaded();
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
  }
}
