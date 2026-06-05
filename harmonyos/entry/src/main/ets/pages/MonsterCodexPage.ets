import { CodexEntry, MONSTER_CODEX } from '../data/MonsterCodex';
import {
  getMonsterByIndex,
  levelBadgeZhForMonsterLevel,
} from '../data/MonsterCatalog';
import { CoinAccount, getCoinAccount } from '../services/CoinAccount';
import {
  getMonsterProgressStore,
  maskedQuestionMarks,
  MonsterProgressRecord,
  MonsterProgressStore,
  MonsterRewardState,
  MONSTER_MYSTERY_ASSET,
} from '../services/MonsterProgressStore';
import display from '@ohos.display';
import { BusinessError } from '@ohos.base';
import { common } from '@kit.AbilityKit';
import { PAGE_BODY_EDGE_VP } from '../constants/PageLayoutInsets';
import { PageTopChrome } from '../components/PageTopChrome';
import { requestPageOrientation } from '../utils/orientation';

/**
 * MonsterCodexPage: read-only browse of the 100 codex monsters
 * (Slime → Music Box Fairy). No persistence — every entry starts at index 0.
 * No audio. No swipe / long-press / zoom — only the left/right
 * circular arrow buttons drive navigation, and they disable at
 * boundaries (no wrap-around).
 *
 * Responsive layout (added Sat 2026-05-02):
 *   - On phones (shorter screen edge < 600vp) the page renders the
 *     legacy "compact" sizes that V0.3.7 shipped with.
 *   - On pads / foldables (shorter edge ≥ 600vp, MatePad-class) the
 *     monster image, navigation arrows, and surrounding text scale
 *     up roughly 2× so the codex fills the larger viewport instead
 *     of clustering at the top of a sea of background.
 *   - The body block (avatar + name + position + description) is
 *     vertically centred in the remaining space below the top bar
 *     so the layout reads the same on both form factors regardless
 *     of how much vertical room the device offers.
 *
 * ArkUI reactivity note (lesson from v0.3.6 text-layout fix):
 * every @Builder below is parameter-less and reads `this.currentIndex`
 * directly (or via the helper methods `current()` / `hasPrev()` /
 * `hasNext()`). Do NOT pass parameters into the @Builder bodies —
 * ArkUI's compile-time dependency analysis only tracks @State reads
 * inside the Builder body's source, so a parameterised Builder will
 * silently freeze on the initial frame. The same constraint also
 * applies to the new responsive sizing helpers (`avatarSize()` etc.):
 * they MUST be method calls inside the Builder, not parameters.
 */

/** HarmonyOS standard width breakpoint between sm (phone) and md (pad). */
const PAD_BREAKPOINT_VP: number = 600;

@Entry
@Component
struct MonsterCodexPage {
  @State private currentIndex: number = 0;
  @State private progressRevision: number = 0;
  /**
   * Shorter screen edge in vp. Drives the responsive sizing helpers
   * below. Defaults to a phone-class value so the first frame is
   * never larger-than-life if the display query throws.
   */
  @State private shortEdgeVp: number = 360;
  private progressStore: MonsterProgressStore = getMonsterProgressStore();
  private coinAccount: CoinAccount = getCoinAccount();

  private applyOrientationPolicy(): void {
    requestPageOrientation(
      this.getUIContext().getHostContext() as common.UIAbilityContext,
      'MonsterCodexPage',
      (px: number): number => this.getUIContext().px2vp(px),
    );
  }

  aboutToAppear(): void {
    this.applyOrientationPolicy();
    const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.progressStore.init(ctx).then((): void => {
      this.progressRevision += 1;
    }).catch((err: BusinessError): void => {
      console.error(`MonsterCodexPage: MonsterProgressStore.init failed: ${JSON.stringify(err)}`);
    });
    this.coinAccount.init(ctx).catch((err: BusinessError): void => {
      console.error(`MonsterCodexPage: CoinAccount.init failed: ${JSON.stringify(err)}`);
    });
    try {
      const d: display.Display = display.getDefaultDisplaySync();
      const widthVp: number = this.getUIContext().px2vp(d.width);
      const heightVp: number = this.getUIContext().px2vp(d.height);
      this.shortEdgeVp = Math.min(widthVp, heightVp);
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      console.error(`MonsterCodexPage: display query failed: ${JSON.stringify(e)}`);
      // Keep the phone-class default; the page is still usable.
    }
  }

  onPageShow(): void {
    this.applyOrientationPolicy();
  }

  private isPad(): boolean {
    return this.shortEdgeVp >= PAD_BREAKPOINT_VP;
  }

  // --- responsive sizing ---------------------------------------------------
  // Two-tier breakpoint: phone (sm) vs pad (md+). Sticking to two tiers
  // keeps the visual language predictable and avoids a continuous-scale
  // factor that compounds rounding errors in nested layouts.

  private avatarFrameSize(): number { return this.isPad() ? 320 : 140; }
  private avatarImageSize(): number { return this.isPad() ? 256 : 112; }
  private avatarFrameRadius(): number { return this.isPad() ? 32 : 20; }

  private arrowSize(): number { return this.isPad() ? 96 : 56; }
  private arrowFontSize(): number { return this.isPad() ? 44 : 28; }
  private arrowGap(): number { return this.isPad() ? 28 : 12; }

  private nameFontSize(): number { return this.isPad() ? 32 : 22; }
  private kindFontSize(): number { return this.isPad() ? 20 : 14; }
  private positionFontSize(): number { return this.isPad() ? 16 : 12; }
  private descriptionFontSize(): number { return this.isPad() ? 20 : 14; }
  private descriptionLineHeight(): number { return this.isPad() ? 30 : 22; }
  private descriptionMaxWidth(): string { return this.isPad() ? '70%' : '100%'; }

  private hasPrev(): boolean {
    return this.currentIndex > 0;
  }

  private hasNext(): boolean {
    return this.currentIndex < MONSTER_CODEX.length - 1;
  }

  private current(): CodexEntry {
    return MONSTER_CODEX[this.currentIndex];
  }

  private currentProgress(): MonsterProgressRecord {
    const revision: number = this.progressRevision;
    if (revision < 0) {
      return new MonsterProgressRecord();
    }
    return this.progressStore.recordFor(this.currentIndex + 1);
  }

  private currentEncountered(): boolean {
    return this.currentProgress().encountered;
  }

  private currentAssetPath(): string {
    return this.currentEncountered() ? this.current().assetPath : MONSTER_MYSTERY_ASSET;
  }

  private currentDisplayName(): string {
    const name: string = this.current().nameEn;
    return this.currentEncountered() ? name : maskedQuestionMarks(name);
  }

  private currentKindLabel(): string {
    const kind: string = this.current().kindLabelZh;
    return this.currentEncountered() ? kind : maskedQuestionMarks(kind);
  }

  private currentDescription(): string {
    const description: string = this.current().descriptionZh;
    return this.currentEncountered() ? description : maskedQuestionMarks(description);
  }

  private rewardState(milestone: number): MonsterRewardState {
    return this.progressStore.rewardState(this.currentIndex + 1, milestone);
  }

  private claimReward(milestone: number): void {
    const state: MonsterRewardState = this.rewardState(milestone);
    if (!state.enabled) {
      return;
    }
    const ok: boolean = this.progressStore.claimReward(this.currentIndex + 1, milestone, this.coinAccount, Date.now());
    if (!ok) {
      return;
    }
    this.progressRevision += 1;
    this.progressStore.flushNow().catch((err: BusinessError): void => {
      console.error(`MonsterCodexPage: MonsterProgressStore.flushNow failed: ${JSON.stringify(err)}`);
    });
    this.coinAccount.flushNow().catch((err: BusinessError): void => {
      console.error(`MonsterCodexPage: CoinAccount.flushNow failed: ${JSON.stringify(err)}`);
    });
  }

  private currentLevelBadgeZh(): string {
    return levelBadgeZhForMonsterLevel(getMonsterByIndex(this.currentIndex + 1).level);
  }

  private goPrev(): void {
    if (this.hasPrev()) {
      this.currentIndex -= 1;
    }
  }

  private goNext(): void {
    if (this.hasNext()) {
      this.currentIndex += 1;
    }
  }

  build(): void {
    Column() {
      PageTopChrome({
        backButtonId: 'CodexBackButton',
        title: '怪物图鉴',
        titleId: 'MonsterCodexTitle',
        onBack: (): void => {
          this.getUIContext().getRouter().back();
        },
      })
      // Body wrapper: layoutWeight(1) consumes the remaining vertical
      // space and `FlexAlign.Center` pins the avatar/name/description
      // block to the page's vertical centre. Without this the codex
      // hugs the top of the screen on tall pads, leaving a giant
      // empty area below the description.
      Column() {
        this.avatarRow();
        this.nameBlock();
        this.positionIndicator();
        this.descriptionBlock();
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
      .padding({ left: PAGE_BODY_EDGE_VP, right: PAGE_BODY_EDGE_VP, bottom: PAGE_BODY_EDGE_VP });
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F8F9FA')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM,
      SafeAreaEdge.START, SafeAreaEdge.END]);
  }

  @Builder
  private avatarRow() {
    Row({ space: this.arrowGap() }) {
      Button('⬅')
        .id('CodexPrev')
        .type(ButtonType.Circle)
        .width(this.arrowSize())
        .height(this.arrowSize())
        .fontSize(this.arrowFontSize())
        .fontColor(this.hasPrev() ? '#E63946' : '#999999')
        .backgroundColor(this.hasPrev() ? '#FCEAEA' : '#EEEEEE')
        .enabled(this.hasPrev())
        .onClick((): void => {
          this.goPrev();
        });

      Stack() {
        Column()
          .width(this.avatarFrameSize())
          .height(this.avatarFrameSize())
          .backgroundColor('#FFFFFF')
          .borderRadius(this.avatarFrameRadius())
          .border({ width: 1, color: '#E0E0E0' });

        Image($rawfile(this.currentAssetPath()))
          .id('CodexAvatar')
          .objectFit(ImageFit.Contain)
          .width(this.avatarImageSize())
          .height(this.avatarImageSize())
          .syncLoad(true)
          .interpolation(ImageInterpolation.High);
      }
      .width(this.avatarFrameSize())
      .height(this.avatarFrameSize())
      .alignContent(Alignment.Center);

      Button('➡')
        .id('CodexNext')
        .type(ButtonType.Circle)
        .width(this.arrowSize())
        .height(this.arrowSize())
        .fontSize(this.arrowFontSize())
        .fontColor(this.hasNext() ? '#E63946' : '#999999')
        .backgroundColor(this.hasNext() ? '#FCEAEA' : '#EEEEEE')
        .enabled(this.hasNext())
        .onClick((): void => {
          this.goNext();
        });
    }
    .width('100%')
    .justifyContent(FlexAlign.Center);
  }

  @Builder
  private nameBlock() {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        Text(this.currentDisplayName())
          .id('CodexName')
          .fontSize(this.nameFontSize())
          .fontWeight(FontWeight.Bold)
          .fontColor('#1D3557');

        Text(this.currentLevelBadgeZh())
          .id(`MonsterCodexLevelBadge_${this.current().key}`)
          .fontSize(this.isPad() ? 14 : 11)
          .fontColor('#FFFFFF')
          .backgroundColor('#457B9D')
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(9)
          .constraintSize({ minWidth: 28, minHeight: 18 });
      }
      .justifyContent(FlexAlign.Center);

      Text(`「${this.currentKindLabel()}」`)
        .id('CodexKindLabel')
        .fontSize(this.kindFontSize())
        .fontColor('#457B9D')
        .backgroundColor('#EAF2F8')
        .padding({ left: 12, right: 12, top: 4, bottom: 4 })
        .borderRadius(12);
    }
    .alignItems(HorizontalAlign.Center)
    .margin({ top: 16 });
  }

  @Builder
  private positionIndicator() {
    Column({ space: 8 }) {
      Text(`${this.currentIndex + 1} / ${MONSTER_CODEX.length}`)
        .id('CodexPositionIndicator')
        .fontSize(this.positionFontSize())
        .fontColor('#888888');
      if (this.currentEncountered()) {
        Text(`击败 ${this.currentProgress().defeatCount} 次`)
          .id('CodexDefeatCount')
          .fontSize(this.positionFontSize())
          .fontColor('#1D3557')
          .fontWeight(FontWeight.Medium);
        this.rewardButtons();
      }
    }
    .alignItems(HorizontalAlign.Center)
    .margin({ top: 8 });
  }

  @Builder
  private rewardButtons() {
    Row({ space: 10 }) {
      this.rewardButton(50, 'CodexReward50Button');
      this.rewardButton(100, 'CodexReward100Button');
    }
    .justifyContent(FlexAlign.Center);
  }

  @Builder
  private rewardButton(milestone: number, id: string) {
    Button(this.rewardState(milestone).label)
      .id(id)
      .height(this.isPad() ? 40 : 32)
      .padding({ left: 14, right: 14 })
      .fontSize(this.isPad() ? 15 : 12)
      .fontColor(this.rewardState(milestone).enabled ? '#503A00' : '#7A8794')
      .backgroundColor(this.rewardState(milestone).enabled ? '#F6C453' : '#EDF0F3')
      .borderRadius(16)
      .enabled(this.rewardState(milestone).enabled)
      .onClick((): void => {
        this.claimReward(milestone);
      });
  }

  @Builder
  private descriptionBlock() {
    Text(this.currentDescription())
      .id('CodexDescription')
      .fontSize(this.descriptionFontSize())
      .lineHeight(this.descriptionLineHeight())
      .fontColor('#333333')
      .textAlign(TextAlign.Center)
      .constraintSize({ maxWidth: this.descriptionMaxWidth() })
      .padding({ left: 24, right: 24 })
      .margin({ top: 12 });
  }
}
