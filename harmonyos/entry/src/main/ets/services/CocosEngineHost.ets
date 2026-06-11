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

  /**
   * Idempotent engine boot. Replicates the scaffold's order:
   * appLifecycle.onCreate -> resourceManagerInit -> writablePathInit ->
   * worker creation + UI<->worker port wiring. The XComponent's onLoad later
   * posts 'onXCLoad', upon which the worker runs nativeEngineInit/Start.
   */
  ensureBooted(ctx: common.UIAbilityContext): void {
    if (this.booted) {
      return;
    }
    this.booted = true;
    const engineUtils: context = cocos.getContext(ContextType.ENGINE_UTILS);
    this.appLifecycle = cocos.getContext(ContextType.APP_LIFECYCLE);
    engineUtils.registerFunction('executeMethodAsync', executeMethodAsync);
    engineUtils.registerFunction('executeMethodSync', executeMethodSync);
    this.appLifecycle.onCreate();
    engineUtils.resourceManagerInit(ctx.resourceManager);
    engineUtils.writablePathInit(ctx.cacheDir);
    // Creates the CocosWorker thread; the vendored WorkerManager points at
    // entry/ets/cocosvendor/workers/cocos_worker.ets.
    WorkerPort.getInstance().initPort(WorkerManager.getInstance().getWorker());
    // The app is foreground when the battle page boots the engine; the
    // scaffold equivalent fires onShow via its windowStage RESUMED handler.
    this.visible = true;
    this.appLifecycle.onShow();
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
