import media from '@ohos.multimedia.media';
import { BusinessError } from '@ohos.base';
import { common } from '@kit.AbilityKit';
import { GiftBox } from '../components/GiftBox';

/**
 * Relative path under `entry/src/main/resources/rawfile/` (sibling of `base/`, not inside it).
 * Bundled OGG (AOSP Argon notification, Apache-2.0) as `sound/notification.ogg`.
 */
const NOTIFICATION_OGG_RAW_PATH: string = 'sound/notification.ogg';

@Entry
@Component
struct Index {
  @State message: string = 'Hello World';
  @State private clickTick: number = 0;
  private avPlayer?: media.AVPlayer;

  async aboutToAppear(): Promise<void> {
    try {
      const host = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
      if (host === undefined) {
        console.error('Host context unavailable for rawfile resource');
        return;
      }
      const raw = await host.resourceManager.getRawFd(NOTIFICATION_OGG_RAW_PATH);

      this.avPlayer = await media.createAVPlayer();
      const player = this.avPlayer;
      player.on('error', (err: BusinessError) => {
        console.error('AVPlayer error:', JSON.stringify(err));
      });
      player.on('stateChange', (state: string) => {
        if (state === 'initialized') {
          player.prepare().catch((err: BusinessError) => {
            console.error('AVPlayer prepare failed:', JSON.stringify(err));
          });
        }
      });
      const fdSrc: media.AVFileDescriptor = {
        fd: raw.fd,
        offset: raw.offset,
        length: raw.length
      };
      player.fdSrc = fdSrc;
    } catch (err) {
      console.error('Failed to setup bundled notification sound:', JSON.stringify(err as BusinessError));
    }
  }

  aboutToDisappear(): void {
    const player = this.avPlayer;
    this.avPlayer = undefined;
    if (player) {
      player.release().catch((e: BusinessError) => {
        console.error('AVPlayer release failed:', JSON.stringify(e));
      });
    }
  }

  /**
   * After the first playback, AVPlayer moves to `completed` (or `paused`), not `prepared`.
   * Seek to 0 then play so every tap replays from the start.
   */
  private async playBundledNotificationSound(): Promise<void> {
    const player = this.avPlayer;
    if (!player) {
      return;
    }
    switch (player.state) {
      case 'prepared':
      case 'completed':
      case 'paused':
      case 'playing':
        break;
      default:
        return;
    }
    try {
      await player.seek(0);
      await player.play();
    } catch (err) {
      console.error('Playback failed:', JSON.stringify(err as BusinessError));
    }
  }

  build(): void {
    RelativeContainer() {
      Text(this.message)
        .id('HelloWorld')
        .fontSize($r('app.float.page_text_font_size'))
        .fontWeight(FontWeight.Bold)
        .alignRules({
          center: { anchor: '__container__', align: VerticalAlign.Center },
          middle: { anchor: '__container__', align: HorizontalAlign.Center }
        })
        .onClick((): void => {
          this.message = 'Welcome';
        })

      GiftBox({ trigger: this.clickTick })
        .alignRules({
          bottom: { anchor: 'HelloButton', align: VerticalAlign.Top },
          middle: { anchor: '__container__', align: HorizontalAlign.Center }
        })
        .margin({ bottom: 24 })

      Button('点击我')
        .id('HelloButton')
        .alignRules({
          bottom: { anchor: '__container__', align: VerticalAlign.Bottom },
          middle: { anchor: '__container__', align: HorizontalAlign.Center }
        })
        .margin({ bottom: 80 })
        .onClick((): void => {
          this.clickTick += 1;
          void this.playBundledNotificationSound();
        })
    }
    .height('100%')
    .width('100%')
  }
}
