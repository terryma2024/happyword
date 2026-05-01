import { BusinessError } from '@ohos.base';
import { common } from '@kit.AbilityKit';
import {
  ParentApiClient,
  ParentAuthError,
  ParentHttpError,
  LessonApproveSummaryDto,
  LessonDraftDto,
  LessonExtractedDto,
  LessonExtractedWord,
} from '../services/ParentApiClient';
import { effectiveServerBaseUrl } from '../services/RemoteWordPackConfig';
import {
  IOrientationAdapter,
  RealOrientationAdapter,
  lockPortrait,
} from '../utils/orientation';

/**
 * LessonDraftReviewPage — V0.5.8 Phase G.
 *
 * Renders a single LessonDraftDto for parent review. Surfaces:
 *   - Source thumbnail + editable category label.
 *   - Word list with keep/discard toggles + per-row "edit" dialog.
 *   - Approve / reject actions: approve PATCHes the edited extraction
 *     then POSTs /approve; reject POSTs /reject. Both back-nav on
 *     success. 409 ALREADY_REVIEWED auto-backs after a brief toast.
 *
 * Orientation: locks portrait on appear and re-locks on onPageShow
 * (idempotent) — outer ParentAdminPage owns the auto-landscape restore
 * via aboutToDisappear. See spec §6.3 "Screen orientation lifecycle".
 *
 * Route params: { draftId: string } from ParentAdminPage.gotoReview().
 * Missing draftId toasts and back-navs.
 */

const TOAST_MS: number = 1800;
const BACK_AFTER_TOAST_MS: number = 800;
const BACK_AFTER_409_MS: number = 1000;

class LessonReviewRouteParams {
  draftId: string = '';
}

@Entry
@Component
struct LessonDraftReviewPage {
  @State private draft?: LessonDraftDto = undefined;
  @State private edits: LessonExtractedWord[] = [];
  @State private keepFlags: boolean[] = [];
  @State private editedFlags: boolean[] = [];
  @State private categoryLabel: string = '';
  @State private editingIndex: number = -1;
  @State private editEnglishDraft: string = '';
  @State private editChineseDraft: string = '';
  @State private busy: boolean = false;
  @State private error: string = '';
  @State private toast: string = '';
  private toastTimer: number = -1;
  private draftId: string = '';
  private client: ParentApiClient = ParentApiClient.withRealHttp(effectiveServerBaseUrl());
  private orientation: IOrientationAdapter = new RealOrientationAdapter(
    this.getUIContext().getHostContext() as common.UIAbilityContext,
  );

  aboutToAppear(): void {
    lockPortrait(this.orientation).catch((err: BusinessError): void => {
      console.error(`LessonDraftReviewPage.lockPortrait failed: ${JSON.stringify(err)}`);
    });
    const raw: object | undefined = this.getUIContext().getRouter().getParams() as object | undefined;
    if (raw !== undefined) {
      const p: LessonReviewRouteParams = raw as LessonReviewRouteParams;
      if (typeof p.draftId === 'string') {
        this.draftId = p.draftId;
      }
    }
    this.loadDraft().catch((err: BusinessError): void => {
      console.error(`LessonDraftReviewPage.loadDraft failed: ${JSON.stringify(err)}`);
    });
  }

  onPageShow(): void {
    lockPortrait(this.orientation).catch((err: BusinessError): void => {
      console.error(`LessonDraftReviewPage.lockPortrait(onPageShow) failed: ${JSON.stringify(err)}`);
    });
  }

  aboutToDisappear(): void {
    if (this.toastTimer >= 0) {
      clearTimeout(this.toastTimer);
      this.toastTimer = -1;
    }
    // Outer ParentAdminPage handles restoreAutoLandscape on its own
    // aboutToDisappear; portrait stays locked across the back-pop so
    // the parent's onPageShow re-lock is a no-op.
  }

  private async loadDraft(): Promise<void> {
    if (this.draftId.length === 0) {
      this.showToast('未找到草稿');
      this.scheduleBack(BACK_AFTER_TOAST_MS);
      return;
    }
    try {
      const d: LessonDraftDto = await this.client.getLessonDraft(this.draftId);
      this.applyDraft(d);
      if (d.status !== 'pending') {
        this.showToast('草稿已复核');
        this.scheduleBack(BACK_AFTER_TOAST_MS);
      }
    } catch (err) {
      this.error = LessonDraftReviewPage.humanizeError(err);
    }
  }

  private applyDraft(d: LessonDraftDto): void {
    this.draft = d;
    // The server schema declares edited_extracted as Optional, and
    // FastAPI serialises a missing edit as JSON null (NOT an absent
    // key). After JSON.parse the field arrives as JS `null`, which is
    // `!== undefined` but obviously cannot be dereferenced — guard
    // against both shapes so a freshly-imported draft (always null
    // edits) renders the original extraction instead of crashing.
    const edited: LessonExtractedDto | undefined = d.edited_extracted;
    const src: LessonExtractedDto =
      edited !== undefined && edited !== null ? edited : d.extracted;
    const initEdits: LessonExtractedWord[] = [];
    const initKeep: boolean[] = [];
    const initEdited: boolean[] = [];
    for (let i: number = 0; i < src.words.length; i++) {
      const w: LessonExtractedWord = new LessonExtractedWord();
      w.word = src.words[i].word;
      w.meaningZh = src.words[i].meaningZh;
      w.difficulty = src.words[i].difficulty;
      initEdits.push(w);
      initKeep.push(true);
      initEdited.push(false);
    }
    this.edits = initEdits;
    this.keepFlags = initKeep;
    this.editedFlags = initEdited;
    this.categoryLabel = src.label_zh.length > 0 ? src.label_zh : d.extracted.label_zh;
  }

  private showToast(msg: string): void {
    this.toast = msg;
    if (this.toastTimer >= 0) {
      clearTimeout(this.toastTimer);
    }
    this.toastTimer = setTimeout((): void => {
      this.toast = '';
      this.toastTimer = -1;
    }, TOAST_MS);
  }

  private scheduleBack(ms: number): void {
    setTimeout((): void => this.back(), ms);
  }

  private back(): void {
    this.getUIContext().getRouter().back();
  }

  private openEditDialog(i: number): void {
    if (i < 0 || i >= this.edits.length) {
      return;
    }
    this.editingIndex = i;
    this.editEnglishDraft = this.edits[i].word;
    this.editChineseDraft = this.edits[i].meaningZh;
  }

  private closeEditDialog(): void {
    this.editingIndex = -1;
  }

  private saveEdit(): void {
    const en: string = this.editEnglishDraft.trim();
    const zh: string = this.editChineseDraft.trim();
    if (en.length === 0 || zh.length === 0) {
      this.showToast('英文和中文都不能为空');
      return;
    }
    const i: number = this.editingIndex;
    if (i < 0 || i >= this.edits.length) {
      this.closeEditDialog();
      return;
    }
    const next: LessonExtractedWord[] = this.edits.slice();
    const w: LessonExtractedWord = new LessonExtractedWord();
    w.word = en;
    w.meaningZh = zh;
    w.difficulty = this.edits[i].difficulty;
    next[i] = w;
    this.edits = next;
    const flags: boolean[] = this.editedFlags.slice();
    flags[i] = true;
    this.editedFlags = flags;
    this.closeEditDialog();
  }

  private async onApprove(): Promise<void> {
    const d: LessonDraftDto | undefined = this.draft;
    if (d === undefined) {
      return;
    }
    const kept: LessonExtractedWord[] = [];
    for (let i: number = 0; i < this.edits.length; i++) {
      if (this.keepFlags[i]) {
        kept.push(this.edits[i]);
      }
    }
    if (kept.length === 0) {
      this.error = '请至少保留一个单词';
      return;
    }
    this.busy = true;
    this.error = '';
    try {
      const edited: LessonExtractedDto = new LessonExtractedDto();
      edited.category_id = d.extracted.category_id;
      edited.label_en = d.extracted.label_en;
      edited.label_zh =
        this.categoryLabel.length > 0 ? this.categoryLabel : d.extracted.label_zh;
      edited.story_zh = d.extracted.story_zh;
      edited.words = kept;

      await this.client.patchLessonDraft(this.draftId, edited);
      const summary: LessonApproveSummaryDto =
        await this.client.approveLessonDraft(this.draftId);
      const insertedCount: number = summary.created_words.length;
      this.showToast(`已确认 ${insertedCount} 个单词`);
      this.scheduleBack(BACK_AFTER_TOAST_MS);
    } catch (err) {
      this.error = LessonDraftReviewPage.humanizeError(err);
      if (err instanceof ParentHttpError) {
        const ph: ParentHttpError = err as ParentHttpError;
        if (ph.status === 409) {
          this.scheduleBack(BACK_AFTER_409_MS);
        }
      }
    } finally {
      this.busy = false;
    }
  }

  private async onReject(): Promise<void> {
    if (this.draft === undefined) {
      return;
    }
    this.busy = true;
    this.error = '';
    try {
      await this.client.rejectLessonDraft(this.draftId);
      this.showToast('已丢弃');
      this.scheduleBack(BACK_AFTER_TOAST_MS);
    } catch (err) {
      this.error = LessonDraftReviewPage.humanizeError(err);
      if (err instanceof ParentHttpError) {
        const ph: ParentHttpError = err as ParentHttpError;
        if (ph.status === 409) {
          this.scheduleBack(BACK_AFTER_409_MS);
        }
      }
    } finally {
      this.busy = false;
    }
  }

  private static humanizeError(e: object): string {
    if (e instanceof ParentAuthError) {
      return '服务端拒绝访问 (401/403)';
    }
    if (e instanceof ParentHttpError) {
      const ph: ParentHttpError = e as ParentHttpError;
      if (ph.status === 409) {
        return '草稿已被处理';
      }
      return `服务异常 (HTTP ${ph.status})`;
    }
    return '操作失败，请重试';
  }

  build(): void {
    Stack() {
      Column({ space: 12 }) {
        Row() {
          Button('← 返回')
            .id('LessonReviewBack')
            .height(40)
            .fontSize(14)
            .backgroundColor('#EAF2F8')
            .fontColor('#457B9D')
            .onClick((): void => this.back());
          Text('课本单词复核')
            .id('LessonReviewTitle')
            .layoutWeight(1)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .textAlign(TextAlign.Center);
          Blank().width(72);
        }
        .width('100%');

        if (this.draft === undefined && this.error.length === 0) {
          LoadingProgress().width(40).height(40).color('#457B9D');
        }
        if (this.error.length > 0) {
          Text(this.error)
            .id('LessonReviewError')
            .fontSize(14)
            .fontColor('#C0392B');
        }

        if (this.draft !== undefined) {
          this.bodyCard();
          this.actionRow();
        }
      }
      .padding(16)
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Start);

      this.editDialog();

      if (this.toast.length > 0) {
        Text(this.toast)
          .id('LessonReviewToast')
          .fontSize(14)
          .fontColor('#FFFFFF')
          .backgroundColor('#1D3557')
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .borderRadius(8)
          .margin({ bottom: 32 });
      }
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.Bottom)
    .backgroundColor('#FFFFFF');
  }

  @Builder
  private bodyCard(): void {
    Column({ space: 12 }) {
      if (this.draft !== undefined && this.draft.source_image_url.length > 0) {
        Image(this.draft.source_image_url)
          .id('LessonReviewThumbnail')
          .width('60%')
          .aspectRatio(4 / 3)
          .objectFit(ImageFit.Contain)
          .borderRadius(8);
      }

      Row({ space: 8 }) {
        Text('课本主题').fontSize(14).width(80).fontColor('#3F2F1A');
        TextInput({ text: this.categoryLabel })
          .id('LessonReviewCategoryInput')
          .layoutWeight(1)
          .height(40)
          .fontSize(15)
          .onChange((v: string): void => {
            this.categoryLabel = v;
          });
      }
      .width('100%');

      Text(`共 ${this.edits.length} 个候选词`)
        .id('LessonReviewCount')
        .fontSize(13)
        .fontColor('#666666');

      Scroll() {
        Column({ space: 6 }) {
          ForEach(this.edits, (w: LessonExtractedWord, i: number): void => {
            this.wordRow(w, i);
          }, (w: LessonExtractedWord, i: number): string => `${i}-${w.word}`);
        }
        .width('100%');
      }
      .layoutWeight(1)
      .width('100%');
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#F7F9FC')
    .borderRadius(12)
    .alignItems(HorizontalAlign.Start);
  }

  @Builder
  private wordRow(w: LessonExtractedWord, i: number): void {
    Row({ space: 8 }) {
      Toggle({ type: ToggleType.Checkbox, isOn: this.keepFlags[i] })
        .id(`LessonReviewRowToggle_${i}`)
        .onChange((on: boolean): void => {
          const next: boolean[] = this.keepFlags.slice();
          next[i] = on;
          this.keepFlags = next;
        });
      Text(this.edits[i].word)
        .id(`LessonReviewRowWord_${i}`)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .width(120);
      Text('—').fontSize(15).width(20).fontColor('#666666');
      Text(this.edits[i].meaningZh)
        .id(`LessonReviewRowMeaning_${i}`)
        .fontSize(15)
        .layoutWeight(1)
        .fontColor('#1D3557');
      if (this.editedFlags[i]) {
        Text('✎')
          .id(`LessonReviewRowEdited_${i}`)
          .fontSize(14)
          .fontColor('#457B9D')
          .width(20);
      }
      Button('编辑')
        .id(`LessonReviewRowEdit_${i}`)
        .height(32)
        .fontSize(13)
        .backgroundColor('#EAF2F8')
        .fontColor('#457B9D')
        .onClick((): void => this.openEditDialog(i));
    }
    .id(`LessonReviewRow_${i}`)
    .width('100%')
    .padding({ top: 6, bottom: 6 });
  }

  @Builder
  private actionRow(): void {
    Row({ space: 12 }) {
      Button('全部拒绝')
        .id('LessonReviewRejectButton')
        .layoutWeight(1)
        .height(48)
        .fontSize(15)
        .backgroundColor(this.busy ? '#F0F0F0' : '#F1F3F5')
        .fontColor(this.busy ? '#999999' : '#444444')
        .enabled(!this.busy)
        .onClick((): void => {
          this.onReject().catch((err: BusinessError): void => {
            console.error(`LessonDraftReviewPage.onReject failed: ${JSON.stringify(err)}`);
          });
        });
      Button(this.busy ? '处理中…' : '全部确认')
        .id('LessonReviewApproveButton')
        .layoutWeight(1)
        .height(48)
        .fontSize(15)
        .backgroundColor(this.busy ? '#F0F0F0' : '#1D3557')
        .fontColor(this.busy ? '#999999' : '#FFFFFF')
        .enabled(!this.busy)
        .onClick((): void => {
          this.onApprove().catch((err: BusinessError): void => {
            console.error(`LessonDraftReviewPage.onApprove failed: ${JSON.stringify(err)}`);
          });
        });
    }
    .width('100%');
  }

  @Builder
  private editDialog(): void {
    if (this.editingIndex >= 0) {
      Stack() {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#000000')
          .opacity(0.45)
          .onClick((): void => this.closeEditDialog());
        Column({ space: 12 }) {
          Text('编辑单词')
            .id('LessonReviewEditDialog')
            .fontSize(18)
            .fontWeight(FontWeight.Bold);
          Row({ space: 8 }) {
            Text('英文').width(60).fontSize(14);
            TextInput({ text: this.editEnglishDraft })
              .id('LessonReviewEditEnglish')
              .layoutWeight(1)
              .height(40)
              .fontSize(15)
              .onChange((v: string): void => {
                this.editEnglishDraft = v;
              });
          }
          .width('100%');
          Row({ space: 8 }) {
            Text('中文').width(60).fontSize(14);
            TextInput({ text: this.editChineseDraft })
              .id('LessonReviewEditChinese')
              .layoutWeight(1)
              .height(40)
              .fontSize(15)
              .onChange((v: string): void => {
                this.editChineseDraft = v;
              });
          }
          .width('100%');
          Row({ space: 12 }) {
            Button('取消')
              .id('LessonReviewEditCancel')
              .layoutWeight(1)
              .height(40)
              .fontSize(14)
              .backgroundColor('#F1F3F5')
              .fontColor('#444444')
              .onClick((): void => this.closeEditDialog());
            Button('保存')
              .id('LessonReviewEditConfirm')
              .layoutWeight(1)
              .height(40)
              .fontSize(14)
              .backgroundColor('#1D3557')
              .fontColor('#FFFFFF')
              .onClick((): void => this.saveEdit());
          }
          .width('100%');
        }
        .padding(20)
        .backgroundColor('#FFFFFF')
        .borderRadius(12)
        .width(320);
      }
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.Block);
    }
  }
}
