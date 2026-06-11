/**
 * CocosEngineHost — lazy boot + app-lifecycle relay for the embedded Cocos
 * battle engine (V1.1.0, Task 0.2 embed spike).
 *
 * The Cocos-generated scaffold wires the engine inside its own EntryAbility
 * (appLifecycle.onCreate / resourceManagerInit in onCreate, writablePathInit
 * in onWindowStageCreate, onShow/onHide from windowStage events). Our app
 * hosts many non-Cocos pages, so instead of grafting eager engine calls into
 * EntryAbility we keep the engine dormant until CocosBattlePage boots it via
 * ensureBooted(). EntryAbility only relays foreground/background, which
 * no-ops until the engine is booted.
 *
 * Note: importing 'libcocos.so' here dlopens the engine lib at app start
 * (EntryAbility imports this module). That only loads + registers the NAPI
 * module — no engine threads or rendering start until ensureBooted().
 */
import { common } from '@kit.AbilityKit';
import cocos, { context } from 'libcocos.so';
import { ContextType } from '../cocosvendor/common/Constants';
import { WorkerPort } from '../cocosvendor/common/WorkerPort';
import { WorkerManager } from '../cocosvendor/cocos/WorkerManager';

/** Engine-utils dispatcher pair, replicated from the scaffold pages/index.ets
 *  module prologue (the engine resolves jsb reflection calls through these). */
function executeMethodAsync(nativeFunc: Function, funcData: string, funCb: Function): void {
  nativeFunc(funcData, funCb);
}

function executeMethodSync(nativeFunc: Function, funcData: string): string | boolean | number {
  return nativeFunc(funcData) as string | boolean | number;
}

export class CocosEngineHost {
  private booted: boolean = false;
  private visible: boolean = false;
  private appLifecycle: context | undefined = undefined;
  /** Tracks whether onXCLoad has already been posted to the worker so the
   *  message is sent at most once per process lifetime regardless of how many
   *  times CocosBattlePage is entered and re-entered. */
  private surfaceLoadNotified: boolean = false;

  /**
   * Idempotent engine boot. Replicates the scaffold's order:
   * appLifecycle.onCreate -> resourceManagerInit -> writablePathInit ->
   * worker creation + UI<->worker port wiring. The XComponent's onLoad later
   * posts 'onXCLoad', upon which the worker runs nativeEngineInit/Start.
   *
   * All fallible work runs inside the try block; instance fields are only
   * written after everything succeeds so that a partial failure does not
   * leave the host in a permanently-latched-but-broken state. On failure the
   * fields are reset and the error is re-thrown to the caller.
   */
  ensureBooted(ctx: common.UIAbilityContext): void {
    if (this.booted) {
      return;
    }
    try {
      const engineUtils: context = cocos.getContext(ContextType.ENGINE_UTILS);
      const lifecycle: context = cocos.getContext(ContextType.APP_LIFECYCLE);
      engineUtils.registerFunction('executeMethodAsync', executeMethodAsync);
      engineUtils.registerFunction('executeMethodSync', executeMethodSync);
      lifecycle.onCreate();
      engineUtils.resourceManagerInit(ctx.resourceManager);
      engineUtils.writablePathInit(ctx.cacheDir);
      // Creates the CocosWorker thread; the vendored WorkerManager points at
      // entry/ets/cocosvendor/workers/cocos_worker.ets.
      WorkerPort.getInstance().initPort(WorkerManager.getInstance().getWorker());
      // All fallible work succeeded — commit state.
      this.appLifecycle = lifecycle;
      this.booted = true;
      // The app is foreground when the battle page boots the engine; the
      // scaffold equivalent fires onShow via its windowStage RESUMED handler.
      this.visible = true;
      this.appLifecycle.onShow();
    } catch (err) {
      // Reset so the next page visit can retry rather than silently no-op.
      this.booted = false;
      this.appLifecycle = undefined;
      this.visible = false;
      console.error('CocosEngineHost.ensureBooted failed:', JSON.stringify(err as object));
      // Re-throw as a typed Error so ArkTS strict-mode accepts the throw.
      const msg: string = (err instanceof Error) ? err.message : JSON.stringify(err as object);
      throw new Error(`CocosEngineHost boot failed: ${msg}`);
    }
  }

  /**
   * Called by CocosBattlePage's XComponent onLoad handler when the surface
   * is ready. Posts 'onXCLoad' to the CocosWorker at most once per process
   * lifetime — re-entering the page does not reinitialise the engine.
   */
  notifySurfaceLoaded(): void {
    if (this.surfaceLoadNotified) {
      return;
    }
    this.surfaceLoadNotified = true;
    WorkerPort.getInstance().postMessage('onXCLoad');
  }

  /** Relay from CocosBattlePage.onPageShow to the Cocos JSPAGE_LIFECYCLE. */
  notifyPageShow(): void {
    if (!this.booted) {
      return;
    }
    const pageLifecycle: context = cocos.getContext(ContextType.JSPAGE_LIFECYCLE);
    pageLifecycle.onPageShow();
  }

  /** Relay from CocosBattlePage.onPageHide to the Cocos JSPAGE_LIFECYCLE. */
  notifyPageHide(): void {
    if (!this.booted) {
      return;
    }
    const pageLifecycle: context = cocos.getContext(ContextType.JSPAGE_LIFECYCLE);
    pageLifecycle.onPageHide();
  }

  /** Relay from EntryAbility.onForeground; no-op until booted. */
  notifyForeground(): void {
    if (!this.booted || this.visible) {
      return;
    }
    this.visible = true;
    this.appLifecycle?.onShow();
  }

  /** Relay from EntryAbility.onBackground; no-op until booted. */
  notifyBackground(): void {
    if (!this.booted || !this.visible) {
      return;
    }
    this.visible = false;
    this.appLifecycle?.onHide();
  }
}

const host: CocosEngineHost = new CocosEngineHost();

export function cocosEngineHost(): CocosEngineHost {
  return host;
}
