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
import { CloudCredentials, CloudCredentialsSnapshot } from '../services/CloudCredentials';
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
 *   - 保存草稿: PUT same JSON as PATCH (`edited_extracted`) — stays `pending`.
 *     (Client uses PUT; HarmonyOS HTTP stack rejects PATCH at runtime.)
 *   - 确认并完成: PUT/patch `edited_extracted` + POST /approve — draft
 *     becomes `approved` and words enter the DB / formal vocabulary.
 *   - Reject POSTs /reject. Success paths toast + back-nav where
 *     applicable. 409 ALREADY_REVIEWED auto-backs after a brief toast.
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
  private cloudCreds: CloudCredentials = new CloudCredentials();
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
    const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.cloudCreds.init(ctx).then((): Promise<void> => this.bootstrapLessonDraftClient())
      .catch((err: BusinessError): void => {
        console.error(`LessonDraftReviewPage: CloudCredentials.init failed: ${JSON.stringify(err)}`);
        this.loadDraft().catch((e2: BusinessError): void => {
          console.error(`LessonDraftReviewPage.loadDraft failed: ${JSON.stringify(e2)}`);
        });
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

  private async bootstrapLessonDraftClient(): Promise<void> {
    const snap: CloudCredentialsSnapshot = await this.cloudCreds.load();
    this.client.setFamilyIdForLessonApis(snap.familyId);
    await this.loadDraft();
  }

  private async loadDraft(): Promise<void> {
    if (this.draftId.length === 0) {
      this.showToast('未找到草稿');
      this.scheduleBack(BACK_AFTER_TOAST_MS);
      return;
    }
    try {
      const d: LessonDraftDto = await this.client.getLessonDraft(this.draftId);
      // V0.7: a draft can land here in `extracting` or `extract_failed`
      // when the parent admin clicks an in-progress upload from the
      // home card. There's nothing for them to review yet, so toast
      // and bounce back rather than crash on the (null) `extracted`
      // deref inside `applyDraft`.
      if (d.status !== 'pending') {
        this.showToast(
          d.status === 'extracting'
            ? 'AI 还在识别，请稍后刷新'
            : '草稿已复核',
        );
        this.scheduleBack(BACK_AFTER_TOAST_MS);
        return;
      }
      this.applyDraft(d);
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
    //
    // V0.7: `loadDraft` only calls `applyDraft` for `status==pending`
    // drafts, which always have `extracted` populated by the cron.
    // Guard anyway so a future caller (e.g. a manual refresh after
    // successful approval lands the row in `approved`) cannot crash.
    const extracted: LessonExtractedDto | undefined = d.extracted;
    if (extracted === undefined || extracted === null) {
      this.error = '当前草稿暂无可复核内容';
      return;
    }
    const edited: LessonExtractedDto | undefined = d.edited_extracted;
    const src: LessonExtractedDto =
      edited !== undefined && edited !== null ? edited : extracted;
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
    // English lesson theme for operators (`label_en`). Legacy drafts may
    // only have filled `label_zh` — fall back so old extractions still load.
    const themeEn: string =
      src.label_en.length > 0 ? src.label_en :
      (extracted.label_en.length > 0 ? extracted.label_en : src.label_zh);
    this.categoryLabel = themeEn;
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

  /**
   * Builds `edited_extracted` for PATCH.
   * @param keptOnly true → only rows with checkbox on (used before approve);
   *   false → every row (save draft without dropping unchecked rows).
   */
  private buildEditedPayload(keptOnly: boolean): LessonExtractedDto | null {
    const d: LessonDraftDto | undefined = this.draft;
    if (d === undefined) {
      return null;
    }
    const extracted: LessonExtractedDto | undefined = d.extracted;
    if (extracted === undefined || extracted === null) {
      return null;
    }
    const editedPatch: LessonExtractedDto | undefined = d.edited_extracted;
    const srcLabels: LessonExtractedDto =
      editedPatch !== undefined && editedPatch !== null ? editedPatch : extracted;
    const trimmedTheme: string = this.categoryLabel.trim();
    const words: LessonExtractedWord[] = [];
    for (let i: number = 0; i < this.edits.length; i++) {
      if (!keptOnly || this.keepFlags[i]) {
        const row: LessonExtractedWord = new LessonExtractedWord();
        row.word = this.edits[i].word;
        row.meaningZh = this.edits[i].meaningZh;
        row.difficulty = this.edits[i].difficulty;
        words.push(row);
      }
    }
    if (keptOnly && words.length === 0) {
      return null;
    }
    const out: LessonExtractedDto = new LessonExtractedDto();
    out.category_id = extracted.category_id;
    out.label_en =
      trimmedTheme.length > 0 ? trimmedTheme : srcLabels.label_en;
    out.label_zh = srcLabels.label_zh;
    out.story_zh = srcLabels.story_zh;
    out.words = words;
    return out;
  }

  /** PATCH only — draft stays `pending`; operators can leave and return. */
  private async onSaveDraft(): Promise<void> {
    if (this.draft === undefined) {
      return;
    }
    const payload: LessonExtractedDto | null = this.buildEditedPayload(false);
    if (payload === null) {
      this.error = '当前草稿暂无可保存内容';
      return;
    }
    if (payload.words.length === 0) {
      this.showToast('没有可保存的词');
      return;
    }
    this.busy = true;
    this.error = '';
    try {
      const updated: LessonDraftDto = await this.client.patchLessonDraft(this.draftId, payload);
      this.draft = updated;
      this.showToast('草稿已保存，可继续复核');
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

  private async onApprove(): Promise<void> {
    const d: LessonDraftDto | undefined = this.draft;
    if (d === undefined) {
      return;
    }
    const extracted: LessonExtractedDto | undefined = d.extracted;
    if (extracted === undefined || extracted === null) {
      this.error = '当前草稿暂无可复核内容';
      return;
    }
    const edited: LessonExtractedDto | null = this.buildEditedPayload(true);
    if (edited === null) {
      this.error = '请至少保留一个单词';
      return;
    }
    this.busy = true;
    this.error = '';
    try {
      await this.client.patchLessonDraft(this.draftId, edited);
      const summary: LessonApproveSummaryDto =
        await this.client.approveLessonDraft(this.draftId);
      const insertedCount: number = summary.created_words.length;
      this.showToast(`复核完成，已加入词表（${insertedCount} 个词）`);
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
    .backgroundColor('#FFFFFF')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM,
      SafeAreaEdge.START, SafeAreaEdge.END]);
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
        Column({ space: 0 }) {
          ForEach(this.edits, (w: LessonExtractedWord, i: number): void => {
            this.wordRow(w, i);
          }, (w: LessonExtractedWord, i: number): string => `${i}-${w.word}`);
        }
        .width('100%');
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring);
    }
    .width('100%')
    .layoutWeight(1)
    .padding(12)
    .backgroundColor('#F7F9FC')
    .borderRadius(12)
    .alignItems(HorizontalAlign.Start);
  }

  @Builder
  private wordRow(w: LessonExtractedWord, i: number): void {
    Row({ space: 6 }) {
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
        .layoutWeight(1)
        .textAlign(TextAlign.Start)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .fontColor('#1D3557');
      Text(this.edits[i].meaningZh)
        .id(`LessonReviewRowMeaning_${i}`)
        .fontSize(15)
        .layoutWeight(1)
        .textAlign(TextAlign.Start)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .fontColor('#1D3557');
      if (this.editedFlags[i]) {
        Text('✎')
          .id(`LessonReviewRowEdited_${i}`)
          .fontSize(14)
          .fontColor('#457B9D')
          .width(22)
          .textAlign(TextAlign.Center);
      } else {
        Blank().width(22);
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
    .padding({ left: 8, right: 8, top: 10, bottom: 10 })
    .backgroundColor((i % 2 === 0) ? '#F8F9FB' : '#FFFFFF');
  }

  @Builder
  private actionRow(): void {
    Column({ space: 10 }) {
      Row({ space: 12 }) {
        Button(this.busy ? '请稍候…' : '保存草稿')
          .id('LessonReviewSaveDraftButton')
          .layoutWeight(1)
          .height(48)
          .fontSize(15)
          .backgroundColor(this.busy ? '#F0F0F0' : '#FFFFFF')
          .fontColor(this.busy ? '#999999' : '#1D3557')
          .borderWidth(this.busy ? 0 : 1)
          .borderColor('#1D3557')
          .enabled(!this.busy)
          .onClick((): void => {
            this.onSaveDraft().catch((err: BusinessError): void => {
              console.error(`LessonDraftReviewPage.onSaveDraft failed: ${JSON.stringify(err)}`);
            });
          });
        Button(this.busy ? '请稍候…' : '确认并完成')
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
      Button('全部拒绝')
        .id('LessonReviewRejectButton')
        .width('100%')
        .height(44)
        .fontSize(14)
        .backgroundColor(this.busy ? '#F0F0F0' : '#F1F3F5')
        .fontColor(this.busy ? '#999999' : '#444444')
        .enabled(!this.busy)
        .onClick((): void => {
          this.onReject().catch((err: BusinessError): void => {
            console.error(`LessonDraftReviewPage.onReject failed: ${JSON.stringify(err)}`);
          });
        });
    }
    .width('100%');
  }

  @Builder
  private editDialog(): void {
    if (this.editingIndex >= 0) {
      // Do NOT put HitTestMode.Block on the outer Stack — it swallows every
      // touch including the dialog (same pitfall as WishlistPage giftBoxModal:
      // Block belongs on the dimmed backdrop only).
      Stack({ alignContent: Alignment.Center }) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('rgba(0, 0, 0, 0.45)')
          .hitTestBehavior(HitTestMode.Block)
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
      .height('100%');
    }
  }
}
