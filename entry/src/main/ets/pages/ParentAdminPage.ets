import { BusinessError } from '@ohos.base';
import { common } from '@kit.AbilityKit';
import {
  ParentApiClient,
  ParentAuthError,
  ParentHttpError,
  ParentPackPublished,
  ParentStats,
  LessonDraftDto,
  LessonDraftListPage,
  LessonImportError,
  PickedImage,
} from '../services/ParentApiClient';
import { SERVER_BASE_URL } from '../services/RemoteWordPackConfig';
import {
  IOrientationAdapter,
  RealOrientationAdapter,
  lockPortrait,
  restoreAutoLandscape,
} from '../utils/orientation';
import {
  LessonImagePicker,
  RealPhotoFileReader,
  RealPhotoPickerAdapter,
} from '../services/LessonImagePicker';

/**
 * ParentAdminPage — V0.5.8.
 *
 * Open parent admin console (no login UI). Stays in portrait orientation
 * for the duration of the page; restores AUTO_ROTATION_LANDSCAPE when
 * the user backs out to ConfigPage. The login flow + JWT plumbing was
 * removed in V0.5.8 C2 and will return in V0.6 as a per-family token.
 *
 * Page surfaces:
 *   - Stats card: live snapshot of server state (refresh button).
 *   - Lesson import card (F1, photo → words → review draft).
 *   - Pending drafts list (F2, navigates to LessonDraftReviewPage).
 *   - Publish card: publishes a fresh word-pack snapshot (kept separate
 *     from lesson import — see F3 rationale comment above publishCard).
 *
 * See `docs/superpowers/specs/2026-05-01-v0.5.8-parent-admin-revamp-design.md`.
 */

const TOAST_MS: number = 3000;
const PENDING_PAGE_SIZE: number = 50;
const PICK_SOURCE_CAMERA: string = 'camera';
const PICK_SOURCE_GALLERY: string = 'gallery';

class LessonReviewRouteParams {
  draftId: string = '';
}

@Entry
@Component
struct ParentAdminPage {
  @State private busy: boolean = false;
  @State private toast: string = '';
  @State private stats?: ParentStats = undefined;
  @State private publishedSummary: string = '';
  @State private publishNotes: string = '';
  @State private importBusy: boolean = false;
  @State private importError: string = '';
  @State private lastImportedId: string = '';
  @State private lastImportedWordCount: number = 0;
  @State private pendingDrafts: LessonDraftDto[] = [];
  private toastTimer: number = -1;
  private client: ParentApiClient = ParentApiClient.withRealHttp(SERVER_BASE_URL);
  private orientation: IOrientationAdapter = new RealOrientationAdapter(
    this.getUIContext().getHostContext() as common.UIAbilityContext,
  );
  private picker: LessonImagePicker = new LessonImagePicker(
    new RealPhotoPickerAdapter(this.getUIContext().getHostContext() as common.UIAbilityContext),
    new RealPhotoFileReader(),
  );

  aboutToAppear(): void {
    lockPortrait(this.orientation).catch((err: BusinessError): void => {
      console.error(`ParentAdminPage.lockPortrait failed: ${JSON.stringify(err)}`);
    });
    this.refreshStats().catch((err: BusinessError): void => {
      console.error(`ParentAdminPage.refreshStats(initial) failed: ${JSON.stringify(err)}`);
    });
    this.refreshPendingDrafts().catch((err: BusinessError): void => {
      console.error(`ParentAdminPage.refreshPendingDrafts(initial) failed: ${JSON.stringify(err)}`);
    });
  }

  onPageShow(): void {
    // Re-lock on pop-back from LessonDraftReviewPage; idempotent.
    lockPortrait(this.orientation).catch((err: BusinessError): void => {
      console.error(`ParentAdminPage.lockPortrait(onPageShow) failed: ${JSON.stringify(err)}`);
    });
    // Refresh so an approved draft drops out of the pending list.
    this.refreshPendingDrafts().catch((err: BusinessError): void => {
      console.error(`ParentAdminPage.refreshPendingDrafts(onPageShow) failed: ${JSON.stringify(err)}`);
    });
  }

  aboutToDisappear(): void {
    if (this.toastTimer >= 0) {
      clearTimeout(this.toastTimer);
      this.toastTimer = -1;
    }
    restoreAutoLandscape(this.orientation).catch((err: BusinessError): void => {
      console.error(`ParentAdminPage.restoreAutoLandscape failed: ${JSON.stringify(err)}`);
    });
  }

  private showToast(message: string): void {
    this.toast = message;
    if (this.toastTimer >= 0) {
      clearTimeout(this.toastTimer);
    }
    this.toastTimer = setTimeout((): void => {
      this.toast = '';
      this.toastTimer = -1;
    }, TOAST_MS);
  }

  private async refreshStats(): Promise<void> {
    this.busy = true;
    try {
      this.stats = await this.client.getStats();
    } catch (err) {
      if (err instanceof ParentAuthError) {
        this.showToast('服务端拒绝访问 (401/403)');
      } else if (err instanceof ParentHttpError) {
        this.showToast(`刷新失败 (HTTP ${err.status})`);
      } else {
        const be: BusinessError = err as BusinessError;
        this.showToast(`刷新异常: ${be.message ?? 'unknown'}`);
      }
    } finally {
      this.busy = false;
    }
  }

  private async refreshPendingDrafts(): Promise<void> {
    try {
      const page: LessonDraftListPage =
        await this.client.listPendingLessonDrafts(0, PENDING_PAGE_SIZE);
      this.pendingDrafts = page.items;
    } catch (err) {
      const be: BusinessError = err as BusinessError;
      console.error(`ParentAdminPage.refreshPendingDrafts failed: ${JSON.stringify(be)}`);
    }
  }

  private async publishPack(): Promise<void> {
    this.busy = true;
    try {
      const notes: string | undefined =
        this.publishNotes.length > 0 ? this.publishNotes : undefined;
      const out: ParentPackPublished = await this.client.publishPack(notes);
      this.publishedSummary =
        `已发布 v${out.version} (schema_v${out.schemaVersion}, ${out.wordCount} 词)`;
      this.publishNotes = '';
      await this.refreshStats();
    } catch (err) {
      if (err instanceof ParentAuthError) {
        this.showToast('服务端拒绝访问 (401/403)');
      } else if (err instanceof ParentHttpError) {
        this.showToast(`发布失败 (HTTP ${err.status})`);
      } else {
        const be: BusinessError = err as BusinessError;
        this.showToast(`发布异常: ${be.message ?? 'unknown'}`);
      }
    } finally {
      this.busy = false;
    }
  }

  private async onPickPhoto(source: string): Promise<void> {
    this.resetImportState();
    this.importBusy = true;
    try {
      const file: PickedImage | null = source === PICK_SOURCE_CAMERA
        ? await this.picker.pickFromCamera()
        : await this.picker.pickFromGallery();
      if (file === null) {
        return;
      }
      const draft: LessonDraftDto = await this.client.importLesson(file);
      this.lastImportedId = draft.id;
      this.lastImportedWordCount = draft.extracted.words.length;
      await this.refreshPendingDrafts();
    } catch (err) {
      this.importError = ParentAdminPage.humanizeImportError(err);
    } finally {
      this.importBusy = false;
    }
  }

  private resetImportState(): void {
    this.importError = '';
    this.lastImportedId = '';
    this.lastImportedWordCount = 0;
  }

  private static humanizeImportError(e: object): string {
    if (e instanceof LessonImportError) {
      const err: LessonImportError = e as LessonImportError;
      if (err.code === 'TOO_LARGE') {
        return '图片超过 8 MB，请压缩后重试';
      }
      if (err.code === 'BAD_MIME') {
        return '仅支持 JPG / PNG / WebP 图片';
      }
      if (err.code === 'NETWORK') {
        return '网络异常，请检查后重试';
      }
      return `服务异常 (HTTP ${err.status})`;
    }
    if (e instanceof ParentAuthError) {
      return '服务端拒绝访问 (401/403)';
    }
    if (e instanceof ParentHttpError) {
      const ph: ParentHttpError = e as ParentHttpError;
      return `服务异常 (HTTP ${ph.status})`;
    }
    return '上传失败，请稍后重试';
  }

  private gotoReview(draftId: string): void {
    if (draftId.length === 0) {
      return;
    }
    const params: LessonReviewRouteParams = new LessonReviewRouteParams();
    params.draftId = draftId;
    this.getUIContext().getRouter().pushUrl({
      url: 'pages/LessonDraftReviewPage',
      params,
    }).catch((err: BusinessError): void => {
      console.error(`ParentAdminPage.gotoReview failed: ${JSON.stringify(err)}`);
    });
  }

  private back(): void {
    this.getUIContext().getRouter().back();
  }

  private formatLatestVersion(): string {
    const s: ParentStats | undefined = this.stats;
    if (s === undefined || s.latestVersion === undefined) {
      return '—';
    }
    return `v${s.latestVersion}`;
  }

  private formatLastPublishedAt(): string {
    const s: ParentStats | undefined = this.stats;
    if (s === undefined || s.lastPublishedAt === undefined || s.lastPublishedAt.length === 0) {
      return '—';
    }
    return s.lastPublishedAt;
  }

  private formatTimestamp(iso: string): string {
    // Best-effort: '2026-05-01T14:23:45+00:00' → '2026-05-01 14:23'.
    if (iso.length < 16) {
      return iso;
    }
    return `${iso.substring(0, 10)} ${iso.substring(11, 16)}`;
  }

  build(): void {
    Scroll() {
      Column({ space: 16 }) {
        Row() {
          Button('返回')
            .id('ParentAdminBack')
            .width(80)
            .height(36)
            .fontSize(14)
            .backgroundColor('#EAF2F8')
            .fontColor('#457B9D')
            .onClick((): void => this.back());
          Blank();
          Text('家长管理后台')
            .id('ParentAdminTitle')
            .fontSize(20)
            .fontWeight(FontWeight.Bold);
          Blank();
          Text('').width(80);
        }
        .width('100%');

        Text(`服务器: ${SERVER_BASE_URL}`)
          .id('ParentAdminServerLabel')
          .fontSize(13)
          .fontColor('#666666');

        this.statsCard();
        this.lessonImportCard();
        this.draftListCard();
        this.publishCard();

        if (this.toast.length > 0) {
          Text(this.toast)
            .id('ParentAdminToast')
            .fontSize(13)
            .fontColor('#1D3557')
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .backgroundColor('#FFF4D0')
            .borderRadius(6);
        }
      }
      .padding(16)
      .alignItems(HorizontalAlign.Start);
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF');
  }

  @Builder
  private statsCard(): void {
    Column({ space: 8 }) {
      Row() {
        Text('概览').fontSize(18).fontWeight(FontWeight.Medium);
        Blank();
        Button('刷新')
          .id('ParentAdminRefresh')
          .width(80)
          .height(32)
          .fontSize(13)
          .backgroundColor('#EAF2F8')
          .fontColor('#457B9D')
          .enabled(!this.busy)
          .onClick((): void => {
            this.refreshStats().catch((err: BusinessError): void => {
              console.error(`ParentAdminPage.refreshStats failed: ${JSON.stringify(err)}`);
            });
          });
      }
      .width('100%');

      if (this.stats !== undefined) {
        this.statsLine('用户数', `${this.stats.userCount}`);
        this.statsLine('词条数', `${this.stats.wordCount}`);
        this.statsLine('类别数', `${this.stats.categoryCount}`);
        this.statsLine('已发布版本数', `${this.stats.packCount}`);
        this.statsLine('最新版本', this.formatLatestVersion());
        this.statsLine('最近发布时间', this.formatLastPublishedAt());
        this.statsLine('待审 LLM 草稿', `${this.stats.llmDraftPending}`);
        this.statsLine('待审课本图', `${this.stats.lessonImportDraftPending}`);
      } else {
        Text(this.busy ? '加载中…' : '尚无数据')
          .id('ParentAdminStatsEmpty')
          .fontSize(13)
          .fontColor('#666666');
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#F7F9FC')
    .borderRadius(12);
  }

  @Builder
  private statsLine(label: string, value: string): void {
    Row() {
      Text(label).fontSize(14).fontColor('#3F2F1A').width(120);
      Text(value)
        .id(`ParentAdminStat_${label}`)
        .fontSize(14)
        .fontColor('#1D3557');
    }
    .width('100%')
    .margin({ bottom: 4 });
  }

  @Builder
  private lessonImportCard(): void {
    Column({ space: 12 }) {
      Text('导入课本单词').fontSize(18).fontWeight(FontWeight.Medium);
      Text('拍照或从相册选择课本图片，模型会识别课文里的单词，由您确认后入库。')
        .fontSize(13)
        .fontColor('#666666');

      Row({ space: 12 }) {
        Button('📷 拍照')
          .id('ParentAdminPickCameraButton')
          .layoutWeight(1)
          .height(48)
          .fontSize(15)
          .backgroundColor(this.importBusy ? '#F0F0F0' : '#1D3557')
          .fontColor(this.importBusy ? '#999999' : '#FFFFFF')
          .enabled(!this.importBusy)
          .onClick((): void => {
            this.onPickPhoto(PICK_SOURCE_CAMERA).catch((err: BusinessError): void => {
              console.error(`ParentAdminPage.onPickPhoto(camera) failed: ${JSON.stringify(err)}`);
            });
          });
        Button('🖼️ 从相册')
          .id('ParentAdminPickGalleryButton')
          .layoutWeight(1)
          .height(48)
          .fontSize(15)
          .backgroundColor(this.importBusy ? '#F0F0F0' : '#457B9D')
          .fontColor(this.importBusy ? '#999999' : '#FFFFFF')
          .enabled(!this.importBusy)
          .onClick((): void => {
            this.onPickPhoto(PICK_SOURCE_GALLERY).catch((err: BusinessError): void => {
              console.error(`ParentAdminPage.onPickPhoto(gallery) failed: ${JSON.stringify(err)}`);
            });
          });
      }
      .width('100%');

      if (this.importBusy) {
        Row({ space: 8 }) {
          LoadingProgress().width(20).height(20).color('#457B9D');
          Text('上传 / 识别中… 通常 10–30 秒')
            .id('ParentAdminImportProgress')
            .fontSize(13)
            .fontColor('#666666');
        }
        .width('100%');
      }

      if (this.importError.length > 0) {
        Row({ space: 8 }) {
          Text(this.importError)
            .id('ParentAdminImportError')
            .fontSize(13)
            .fontColor('#C0392B')
            .layoutWeight(1);
          Button('重试')
            .id('ParentAdminImportRetry')
            .height(32)
            .fontSize(13)
            .backgroundColor('#EAF2F8')
            .fontColor('#457B9D')
            .onClick((): void => {
              this.importError = '';
            });
        }
        .width('100%');
      }

      if (this.lastImportedId.length > 0) {
        Row({ space: 8 }) {
          Text(`✓ 已识别 ${this.lastImportedWordCount} 个单词，请确认`)
            .id('ParentAdminImportSuccess')
            .fontSize(13)
            .fontColor('#1E7E34')
            .layoutWeight(1);
          Button('去复核 →')
            .id('ParentAdminGotoReviewButton')
            .height(32)
            .fontSize(13)
            .backgroundColor('#1E7E34')
            .fontColor('#FFFFFF')
            .onClick((): void => this.gotoReview(this.lastImportedId));
        }
        .width('100%');
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#F7F9FC')
    .borderRadius(12)
    .alignItems(HorizontalAlign.Start);
  }

  @Builder
  private draftListCard(): void {
    Column({ space: 8 }) {
      Text(`待复核草稿 (${this.pendingDrafts.length})`)
        .id('ParentAdminPendingTitle')
        .fontSize(18)
        .fontWeight(FontWeight.Medium);

      if (this.pendingDrafts.length === 0) {
        Text('（暂无待复核草稿）')
          .id('ParentAdminPendingEmpty')
          .fontSize(13)
          .fontColor('#888888');
      } else {
        ForEach(this.pendingDrafts, (d: LessonDraftDto): void => {
          this.draftRow(d);
        }, (d: LessonDraftDto): string => d.id);
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#F7F9FC')
    .borderRadius(12)
    .alignItems(HorizontalAlign.Start);
  }

  @Builder
  private draftRow(d: LessonDraftDto): void {
    Row({ space: 8 }) {
      Text(this.formatTimestamp(d.created_at))
        .id(`LessonDraftRow_${d.id}`)
        .fontSize(13)
        .fontColor('#3F2F1A')
        .layoutWeight(1);
      Button('复核 →')
        .id(`LessonDraftReviewLink_${d.id}`)
        .height(32)
        .fontSize(13)
        .backgroundColor('#457B9D')
        .fontColor('#FFFFFF')
        .onClick((): void => this.gotoReview(d.id));
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 });
  }

  @Builder
  private publishCard(): void {
    // V0.5.8: pack publish stays a *separate* one-tap action so the parent
    // can import multiple lesson photos before triggering a release. See
    // spec §1 in docs/superpowers/specs/2026-05-01-v0.5.8-parent-admin-revamp-design.md.
    Column({ space: 12 }) {
      Text('发布新版本词包').fontSize(18).fontWeight(FontWeight.Medium);
      Text('从最新词库快照打包并发布。客户端需要在配置页手动同步后才能看到新版本。')
        .fontSize(13)
        .fontColor('#666666');
      TextInput({ placeholder: '备注（可选，最多 500 字）', text: this.publishNotes })
        .id('ParentAdminPublishNotes')
        .width('100%')
        .height(44)
        .enabled(!this.busy)
        .onChange((v: string): void => {
          this.publishNotes = v;
        });
      Button(this.busy ? '发布中…' : '立即发布')
        .id('ParentAdminPublishButton')
        .width('100%')
        .height(44)
        .fontSize(16)
        .backgroundColor(this.busy ? '#F0F0F0' : '#E63946')
        .fontColor(this.busy ? '#999999' : '#FFFFFF')
        .enabled(!this.busy)
        .onClick((): void => {
          this.publishPack().catch((err: BusinessError): void => {
            console.error(`ParentAdminPage.publishPack failed: ${JSON.stringify(err)}`);
          });
        });
      if (this.publishedSummary.length > 0) {
        Text(this.publishedSummary)
          .id('ParentAdminPublishSummary')
          .fontSize(13)
          .fontColor('#2A9D8F');
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#F7F9FC')
    .borderRadius(12);
  }
}
