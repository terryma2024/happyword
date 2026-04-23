import { router } from '@kit.ArkUI';
import {
  GameConfig,
  GAME_CONFIG_STORAGE_KEY,
  cloneGameConfig
} from '../models/GameConfig';

/**
 * CustomWordsPage — owns `GameConfig.customWordsRaw` end to end.
 * Reads the current raw text on aboutToAppear, lets the player edit
 * multi-line `中文:英文` pairs, and on Save merges the edited text
 * back into the stored GameConfig without touching other fields
 * (spec §4.5 / §3.4).
 */
@Entry
@Component
struct CustomWordsPage {
  @State private rawText: string = '';

  aboutToAppear(): void {
    const cfg: GameConfig | undefined =
      AppStorage.get<GameConfig>(GAME_CONFIG_STORAGE_KEY);
    this.rawText = cfg !== undefined ? cfg.customWordsRaw : '';
  }

  private onSave(): void {
    const current: GameConfig =
      AppStorage.get<GameConfig>(GAME_CONFIG_STORAGE_KEY) ?? new GameConfig();
    const merged: GameConfig = cloneGameConfig(current);
    merged.customWordsRaw = this.rawText;
    AppStorage.set<GameConfig>(GAME_CONFIG_STORAGE_KEY, merged);
    router.back();
  }

  private onCancel(): void {
    router.back();
  }

  build(): void {
    Column() {
      Text('自定义词表')
        .id('CustomWordsTitle')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 8 });

      Text('格式：中文:英文，每行一个')
        .fontSize(14)
        .fontColor('#666666')
        .margin({ bottom: 12 });

      TextArea({
        text: this.rawText,
        placeholder: '每行一条，例如：\n苹果:apple\n香蕉:banana'
      })
        .id('CustomWordsTextArea')
        .width('80%')
        .height('55%')
        .fontSize(16)
        .backgroundColor('#F7F7F7')
        .padding(12)
        .onChange((v: string): void => {
          this.rawText = v;
        });

      Row({ space: 16 }) {
        Button('取消')
          .id('CustomWordsCancelButton')
          .width(160).height(52)
          .backgroundColor('#BDBDBD')
          .onClick((): void => this.onCancel());
        Button('保存')
          .id('CustomWordsSaveButton')
          .width(160).height(52)
          .backgroundColor('#2ECC71')
          .onClick((): void => this.onSave());
      }
      .margin({ top: 20 });
    }
    .width('100%')
    .height('100%')
    .padding({ top: 24, bottom: 24, left: 40, right: 40 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center);
  }
}
