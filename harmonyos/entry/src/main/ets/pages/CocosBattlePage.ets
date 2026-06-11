/**
 * CocosBattlePage — V1.1.0 Task 0.2 embed spike.
 *
 * Hosts the Cocos battle scene inside an XComponent. Boot order replicates
 * the Cocos-generated scaffold page (pages/index.ets in
 * cocos/native/engine/harmonyos-next): the engine boots lazily on first
 * visit (CocosEngineHost.ensureBooted), then the XComponent surface load
 * posts 'onXCLoad' to the CocosWorker via CocosEngineHost.notifySurfaceLoaded
 * (at most once per process), which runs nativeEngineInit/Start.
 *
 * All engine and worker interactions are routed through CocosEngineHost so
 * this page imports no vendored symbols directly.
 *
 * The scene renders its default state (Battle top bar + two cards); its
 * `battle/ready` bridge message goes unanswered at this stage — expected
 * until Task 0.3 wires the bridge.
 */
import { common } from '@kit.AbilityKit';
import { cocosEngineHost } from '../services/CocosEngineHost';

/** Must stay in sync with the surface id the Cocos native layer binds to. */
const COCOS_XCOMPONENT_ID: string = 'xcomponentId';
/** Module name registered by the natively compiled engine (libcocos.so). */
const COCOS_LIBRARY_NAME: string = 'cocos';

@Entry
@Component
struct CocosBattlePage {
  aboutToAppear(): void {
    const ctx: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    cocosEngineHost().ensureBooted(ctx);
  }

  onPageShow(): void {
    cocosEngineHost().notifyPageShow();
  }

  onPageHide(): void {
    cocosEngineHost().notifyPageHide();
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
