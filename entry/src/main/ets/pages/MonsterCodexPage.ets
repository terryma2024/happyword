import { router } from '@kit.ArkUI';
import { CodexEntry, MONSTER_CODEX } from '../data/MonsterCodex';

/**
 * MonsterCodexPage: read-only browse of 3 archetype monsters
 * (Slime / Zombie / Dragon). No persistence — every entry starts
 * at index 0. No audio. No swipe / long-press / zoom — only the
 * left/right circular arrow buttons drive navigation, and they
 * disable at boundaries (no wrap-around).
 *
 * ArkUI reactivity note (lesson from v0.3.6 letter-spacing fix):
 * every @Builder below is parameter-less and reads `this.currentIndex`
 * directly (or via the helper methods `current()` / `hasPrev()` /
 * `hasNext()`). Do NOT pass parameters into the @Builder bodies —
 * ArkUI's compile-time dependency analysis only tracks @State reads
 * inside the Builder body's source, so a parameterised Builder will
 * silently freeze on the initial frame.
 */
@Entry
@Component
struct MonsterCodexPage {
  @State private currentIndex: number = 0;

  private hasPrev(): boolean {
    return this.currentIndex > 0;
  }

  private hasNext(): boolean {
    return this.currentIndex < MONSTER_CODEX.length - 1;
  }

  private current(): CodexEntry {
    return MONSTER_CODEX[this.currentIndex];
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

  build() {
    Column() {
      this.topBar();
      this.avatarRow();
      this.nameBlock();
      this.positionIndicator();
      this.descriptionBlock();
    }
    .width('100%')
    .height('100%')
    .padding({ top: 16, left: 16, right: 16, bottom: 16 })
    .backgroundColor('#F8F9FA');
  }

  @Builder
  private topBar() {
    Row() {
      Button('←')
        .id('CodexBackButton')
        .type(ButtonType.Circle)
        .width(40)
        .height(40)
        .fontSize(20)
        .fontColor('#1D3557')
        .backgroundColor('#FFFFFF')
        .onClick((): void => {
          router.back();
        });

      Text('怪物图鉴')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1D3557')
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
        .margin({ right: 40 });
    }
    .width('100%');
  }

  @Builder
  private avatarRow() {
    Row({ space: 12 }) {
      Button('⬅')
        .id('CodexPrev')
        .type(ButtonType.Circle)
        .width(56)
        .height(56)
        .fontSize(28)
        .fontColor(this.hasPrev() ? '#E63946' : '#999999')
        .backgroundColor(this.hasPrev() ? '#FCEAEA' : '#EEEEEE')
        .enabled(this.hasPrev())
        .onClick((): void => {
          this.goPrev();
        });

      Stack() {
        Column()
          .width(140)
          .height(140)
          .backgroundColor('#FFFFFF')
          .borderRadius(20)
          .border({ width: 1, color: '#E0E0E0' });

        Image($rawfile(this.current().assetPath))
          .id('CodexAvatar')
          .objectFit(ImageFit.Contain)
          .width(112)
          .height(112)
          .syncLoad(true)
          .interpolation(ImageInterpolation.High);
      }
      .width(140)
      .height(140)
      .alignContent(Alignment.Center);

      Button('➡')
        .id('CodexNext')
        .type(ButtonType.Circle)
        .width(56)
        .height(56)
        .fontSize(28)
        .fontColor(this.hasNext() ? '#E63946' : '#999999')
        .backgroundColor(this.hasNext() ? '#FCEAEA' : '#EEEEEE')
        .enabled(this.hasNext())
        .onClick((): void => {
          this.goNext();
        });
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .margin({ top: 16 });
  }

  @Builder
  private nameBlock() {
    Column({ space: 6 }) {
      Text(this.current().nameEn)
        .id('CodexName')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1D3557');

      Text(`「${this.current().kindLabelZh}」`)
        .id('CodexKindLabel')
        .fontSize(14)
        .fontColor('#457B9D')
        .backgroundColor('#EAF2F8')
        .padding({ left: 12, right: 12, top: 4, bottom: 4 })
        .borderRadius(12);
    }
    .alignItems(HorizontalAlign.Center)
    .margin({ top: 12 });
  }

  @Builder
  private positionIndicator() {
    Text(`${this.currentIndex + 1} / ${MONSTER_CODEX.length}`)
      .id('CodexPositionIndicator')
      .fontSize(12)
      .fontColor('#888888')
      .margin({ top: 8 });
  }

  @Builder
  private descriptionBlock() {
    Text(this.current().descriptionZh)
      .id('CodexDescription')
      .fontSize(14)
      .lineHeight(22)
      .fontColor('#333333')
      .textAlign(TextAlign.Center)
      .padding({ left: 24, right: 24 })
      .margin({ top: 12 });
  }
}
