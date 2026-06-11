/**
 * CocosBattlePage — V1.1.0 Task 0.2 embed spike.
 *
 * Hosts the Cocos battle scene inside an XComponent. Boot order replicates
 * the Cocos-generated scaffold page (pages/index.ets in
 * cocos/native/engine/harmonyos-next): the engine boots lazily on first
 * visit (CocosEngineHost.ensureBooted), then the XComponent surface load
 * posts 'onXCLoad' to the CocosWorker, which runs nativeEngineInit/Start.
 *
 * The scene renders its default state (Battle top bar + two cards); its
 * `battle/ready` bridge message goes unanswered at this stage — expected
 * until Task 0.3 wires the bridge.
 */
import { common } from '@kit.AbilityKit';
import cocos, { context } from 'libcocos.so';
import { ContextType } from '../cocosvendor/common/Constants';
import { WorkerPort } from '../cocosvendor/common/WorkerPort';
import { cocosEngineHost } from '../services/CocosEngineHost';

/** Must stay in sync with the surface id the Cocos native layer binds to. */
const COCOS_XCOMPONENT_ID: string = 'xcomponentId';
/** Module name registered by the natively compiled engine (libcocos.so). */
const COCOS_LIBRARY_NAME: string = 'cocos';

@Entry
@Component
struct CocosBattlePage {
  private workPort: WorkerPort = WorkerPort.getInstance();
  private pageLifecycle: context | undefined = undefined;

  aboutToAppear(): void {
    const ctx: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    cocosEngineHost().ensureBooted(ctx);
    this.pageLifecycle = cocos.getContext(ContextType.JSPAGE_LIFECYCLE);
  }

  onPageShow(): void {
    this.pageLifecycle?.onPageShow();
  }

  onPageHide(): void {
    this.pageLifecycle?.onPageHide();
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
          // Surface is ready — tell the CocosWorker to init + start the engine.
          this.workPort.postMessage('onXCLoad');
        })

      Button('Back')
        .id('CocosBattleBackButton')
        .fontSize(14)
        .height(36)
        .margin(12)
        .onClick((): void => {
          this.getUIContext().getRouter().back();
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
  }
}
