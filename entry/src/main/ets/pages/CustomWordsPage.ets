import { common } from '@kit.AbilityKit';
import {
  GameConfig,
  GAME_CONFIG_STORAGE_KEY,
  cloneGameConfig
} from '../models/GameConfig';
import { persistGameConfigBestEffort } from '../services/GameConfigPersistence';

/**
 * CustomWordsPage — owns `GameConfig.customWordsRaw` end to end.
 * Reads the current raw text on aboutToAppear, lets the player edit
 * multi-line `中文:英文` pairs, and on Save merges the edited text
 * back into the stored GameConfig without touching other fields
 * (spec §4.5 / §3.4).
 *
 * V0.6.5.1 — deprecated. The three-layer pack model (built-in / global /
 * family) replaces the legacy "custom words" category: parents who want
 * to upload their own vocabulary should bind a parent account and use
 *  设置 → 进入家长后台 → 上传课本 → 复核 — that flow produces a
 *  family pack visible in 设置 → 📦 我的词包. We still ship the
 * raw-text editor for backwards-compat: existing AppStorage snapshots
 * with `customWordsRaw` content keep working, and the UI test
 *  configCustomWordsOnly_oneShotVictory still drives this page. A
 * deprecation banner above the editor nudges new parents toward the
 * supported flow without breaking the legacy save path.
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
    persistGameConfigBestEffort(this.getUIContext().getHostContext() as common.UIAbilityContext, merged);
    this.getUIContext().getRouter().back();
  }

  private onCancel(): void {
    this.getUIContext().getRouter().back();
  }

  build(): void {
    Column() {
      Text('自定义词表')
        .id('CustomWordsTitle')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 8 });

      // V0.6.5.1: legacy entry point. Surface a soft deprecation hint
      // at the top so new parents follow the family-pack flow instead.
      Column({ space: 4 }) {
        Text('⚠ 此页已不推荐使用')
          .fontSize(13)
          .fontColor('#B45309')
          .fontWeight(FontWeight.Medium);
        Text('家长可绑定账号后，从「家长后台 → 上传课本」上传词包，效果更好且支持图文。')
          .fontSize(12)
          .fontColor('#7C2D12');
      }
      .id('CustomWordsDeprecationBanner')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .backgroundColor('#FEF3C7')
      .borderRadius(8)
      .margin({ bottom: 12 });

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
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('#FFFFFF')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM,
      SafeAreaEdge.START, SafeAreaEdge.END]);
  }
}
