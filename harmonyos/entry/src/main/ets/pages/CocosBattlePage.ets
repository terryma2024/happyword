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
import { hilog } from '@kit.PerformanceAnalysisKit';
import { cocosEngineHost } from '../services/CocosEngineHost';

/** Must stay in sync with the surface id the Cocos native layer binds to. */
const COCOS_XCOMPONENT_ID: string = 'xcomponentId';
/** Module name registered by the natively compiled engine (libcocos.so). */
const COCOS_LIBRARY_NAME: string = 'cocos';

/** Task 0.3 probe: a battle/init with a distinctive playerMaxHp (7) so the
 *  screenshot proves the scene applied an ArkTS-sent message (HP 7/7).
 *  Plain string literal — ArkTS strict mode rejects untyped object literals,
 *  and Task 1.1 introduces real typed codecs anyway. */
const PROBE_INIT_JSON: string = '{"v":1,"type":"battle/init","payload":{'
  + '"playerMaxHp":7,"monsterMaxHp":5,"monstersTotal":5,"startingSeconds":300,'
  + '"playerArt":{"idle":"CharacterMagician","fight":"CharacterMagicianFight",'
  + '"hurt":"CharacterMagicianBeaten"}}}';

/** Task 0.3 probe: the scene echoes battle/ping back as battle/pong. */
const PROBE_PING_JSON: string =
  '{"v":1,"type":"battle/ping","payload":{"echo":"spike-0.3"}}';

@Entry
@Component
struct CocosBattlePage {
  aboutToAppear(): void {
    const ctx: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    // Task 0.3 probe: log every scene->ArkTS message (expect the organic
    // battle/ready on scene boot, then battle/pong echoes after Ping taps).
    cocosEngineHost().setSceneMessageHandler((json: string): void => {
      hilog.info(0x0000, 'WMBridge', 'scene->arkts %{public}s', json);
    });
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

      Row({ space: 8 }) {
        Button('Back')
          .id('CocosBattleBackButton')
          .fontSize(14)
          .height(36)
          .onClick((): void => {
            this.getUIContext().getRouter().back();
          })

        // Task 0.3 bridge probe: send battle/init (playerMaxHp 7) and a
        // battle/ping the scene echoes back as battle/pong.
        Button('Ping')
          .id('CocosBattlePingButton')
          .fontSize(14)
          .height(36)
          .onClick((): void => {
            hilog.info(0x0000, 'WMBridge', 'arkts->scene sending probe init + ping');
            cocosEngineHost().sendToScene(PROBE_INIT_JSON);
            cocosEngineHost().sendToScene(PROBE_PING_JSON);
          })
      }
      .margin(12)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
  }
}
