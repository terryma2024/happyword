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
import { CloudCredentials, CloudCredentialsSnapshot } from '../services/CloudCredentials';
import { effectiveServerBaseUrl } from '../services/RemoteWordPackConfig';
import {
  IOrientationAdapter,
  RealOrientationAdapter,
  lockPortrait,
  restoreAutoLandscape,
} from '../utils/orientation';
import {
  LessonImagePicker,
  RealLessonCameraAdapter,
  RealPhotoFileReader,
  RealPhotoPickerAdapter,
} from '../services/LessonImagePicker';
import {
  COMPRESS_TARGET_BYTES,
  IImageCompressor,
  ImageCompressionError,
  RealImageCompressor,
} from '../services/ImageCompressor';

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
  // V0.7: the import endpoint returns a draft in `status="extracting"`
  // — `extracted` and `model` are populated asynchronously by the
  // server-side cron (~1 min), so there's no word count to surface
  // here. We keep `lastImportedId` so the success banner can deep-
  // link the operator into the draft's review page once they refresh.
  @State private lastImportedId: string = '';
  // Three buckets (manually refreshed):
  //   pending         — 待复核 (parent admin to approve / reject)
  //   extracting      — 待 AI 识别 (cron job will eventually flip → pending)
  //   extract_failed  — 识别失败 N 次后放弃 (operator to investigate)
  @State private pendingDrafts: LessonDraftDto[] = [];
  @State private extractingDrafts: LessonDraftDto[] = [];
  @State private failedDrafts: LessonDraftDto[] = [];
  private toastTimer: number = -1;
  private serverBaseUrl: string = effectiveServerBaseUrl();
  private cloudCreds: CloudCredentials = new CloudCredentials();
  private client: ParentApiClient = ParentApiClient.withRealHttp(this.serverBaseUrl);
  private orientation: IOrientationAdapter = new RealOrientationAdapter(
    this.getUIContext().getHostContext() as common.UIAbilityContext,
  );
  private picker: LessonImagePicker = new LessonImagePicker(
    new RealPhotoPickerAdapter(this.getUIContext().getHostContext() as common.UIAbilityContext),
    new RealLessonCameraAdapter(this.getUIContext().getHostContext() as common.UIAbilityContext),
    new RealPhotoFileReader(),
  );
  // V0.7: photo gallery originals are routinely 5–10 MB on modern
  // phones, but Vercel's edge enforces a hard 4.5 MB request-body cap.
  // Compressing here lets uploads succeed without touching the server
  // limit. See docstring on `RealImageCompressor` for the strategy.
  private compressor: IImageCompressor = new RealImageCompressor();

  aboutToAppear(): void {
    lockPortrait(this.orientation).catch((err: BusinessError): void => {
      console.error(`ParentAdminPage.lockPortrait failed: ${JSON.stringify(err)}`);
    });
    const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.cloudCreds.init(ctx).then((): Promise<void> => this.bootstrapParentAdminNetwork())
      .catch((err: BusinessError): void => {
        console.error(`ParentAdminPage: CloudCredentials.init failed: ${JSON.stringify(err)}`);
        this.refreshStats().catch((e2: BusinessError): void => {
          console.error(`ParentAdminPage.refreshStats(initial) failed: ${JSON.stringify(e2)}`);
        });
        this.refreshPendingDrafts().catch((e3: BusinessError): void => {
          console.error(`ParentAdminPage.refreshPendingDrafts(initial) failed: ${JSON.stringify(e3)}`);
        });
      });
  }

  onPageShow(): void {
    // Re-lock on pop-back from LessonDraftReviewPage; idempotent.
    lockPortrait(this.orientation).catch((err: BusinessError): void => {
      console.error(`ParentAdminPage.lockPortrait(onPageShow) failed: ${JSON.stringify(err)}`);
    });
    const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.cloudCreds.init(ctx).then((): Promise<void> => this.resyncLessonFamilyAndDrafts())
      .catch((err: BusinessError): void => {
        console.error(`ParentAdminPage: CloudCredentials.init(onPageShow) failed: ${JSON.stringify(err)}`);
        this.refreshPendingDrafts().catch((e2: BusinessError): void => {
          console.error(`ParentAdminPage.refreshPendingDrafts(onPageShow) failed: ${JSON.stringify(e2)}`);
        });
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

  private async bootstrapParentAdminNetwork(): Promise<void> {
    const snap: CloudCredentialsSnapshot = await this.cloudCreds.load();
    this.client.setFamilyIdForLessonApis(snap.familyId);
    await this.refreshStats();
    await this.refreshPendingDrafts();
  }

  private async resyncLessonFamilyAndDrafts(): Promise<void> {
    const snap: CloudCredentialsSnapshot = await this.cloudCreds.load();
    this.client.setFamilyIdForLessonApis(snap.familyId);
    await this.refreshPendingDrafts();
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
      // Pages are 1-indexed on the server (Query(1, ge=1)); passing 0 here
      // makes the GET return HTTP 422 and the pending list silently stays
      // empty. See server/app/routers/admin_lessons.py::list_lesson_drafts.
      //
      // V0.7: fetch all three async-extract buckets so the stats card
      // and the failure-triage list stay in sync with reality on each
      // manual refresh. Pure POJO calls — `Promise.all` keeps wall-
      // clock cost ≈ one slowest request rather than three serial.
      // ArkTS rejects destructuring variable declarations
      // (arkts-no-destruct-decls), so we index into the result array.
      const pages: LessonDraftListPage[] = await Promise.all([
        this.client.listLessonDraftsByStatus('pending', 1, PENDING_PAGE_SIZE),
        this.client.listLessonDraftsByStatus('extracting', 1, PENDING_PAGE_SIZE),
        this.client.listLessonDraftsByStatus('extract_failed', 1, PENDING_PAGE_SIZE),
      ]);
      this.pendingDrafts = pages[0].items;
      this.extractingDrafts = pages[1].items;
      this.failedDrafts = pages[2].items;
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
      // Always run through the compressor; it short-circuits when the
      // image already fits, otherwise it re-encodes to JPEG under the
      // Vercel edge body cap. Throws ImageCompressionError on failure
      // (handled by the catch below via humanizeImportError).
      const upload: PickedImage =
        await this.compressor.compress(file, COMPRESS_TARGET_BYTES);
      const draft: LessonDraftDto = await this.client.importLesson(upload);
      this.lastImportedId = draft.id;
      // V0.7: the import endpoint no longer runs the LLM, so
      // `draft.extracted` is undefined here — the cron will populate
      // it asynchronously and a manual refresh will pull it in.
      // Don't deref `.words.length`; it would crash with a null deref.
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
  }

  private static humanizeImportError(e: object): string {
    if (e instanceof ImageCompressionError) {
      const ce: ImageCompressionError = e as ImageCompressionError;
      if (ce.code === 'DECODE_FAILED') {
        return '图片解析失败，请换一张图片';
      }
      if (ce.code === 'NOT_ACHIEVABLE') {
        return '图片过大无法压缩到上传限制以内，请换一张图片';
      }
      // ENCODE_FAILED / SCALE_FAILED — surface a generic message.
      return '图片压缩失败，请稍后重试';
    }
    if (e instanceof LessonImportError) {
      const err: LessonImportError = e as LessonImportError;
      if (err.code === 'TOO_LARGE') {
        // Only fires if the post-compression buffer still exceeds the
        // client-side IMPORT_MAX_BYTES guard (4.5 MB to match Vercel's
        // edge cap). The compressor's NOT_ACHIEVABLE branch above
        // handles "we couldn't shrink it" with a clearer message.
        return '图片过大，请换一张图片';
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
    const router = this.getUIContext().getRouter();
    router.replaceUrl({ url: 'pages/ConfigPage' }).catch((err: BusinessError): void => {
      console.error(`ParentAdminPage.back replaceUrl ConfigPage failed: ${JSON.stringify(err)}`);
      router.back();
    });
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

        Text(`服务器: ${this.serverBaseUrl}`)
          .id('ParentAdminServerLabel')
          .fontSize(13)
          .fontColor('#666666');

        this.statsCard();
        this.lessonImportCard();
        this.draftListCard();
        if (this.failedDrafts.length > 0) {
          this.failedDraftListCard();
        }
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
    .backgroundColor('#FFFFFF')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM,
      SafeAreaEdge.START, SafeAreaEdge.END]);
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
        // V0.7: the import flow is async — split the lesson-import
        // count by status so the operator sees both the cron backlog
        // and the parent-review queue at a glance. Counts come from
        // the per-status list endpoints (refreshed alongside the
        // pending-drafts list, see refreshPendingDrafts).
        this.statsLine('待 AI 识别', `${this.extractingDrafts.length}`);
        this.statsLine('待复核课本图', `${this.pendingDrafts.length}`);
        if (this.failedDrafts.length > 0) {
          this.statsLine('识别失败', `${this.failedDrafts.length}`);
        }
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
        // V0.7: the LLM extraction runs in a 1-minute Vercel cron, so
        // the just-uploaded draft is in `status="extracting"`. Tell
        // the operator to refresh after ~1 min and then go review.
        Row({ space: 8 }) {
          Text('✓ 已上传，AI 识别中…1 分钟后点"刷新"查看')
            .id('ParentAdminImportSuccess')
            .fontSize(13)
            .fontColor('#1E7E34')
            .layoutWeight(1);
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

  // V0.7: surface drafts whose async LLM extraction was abandoned
  // after MAX_EXTRACT_ATTEMPTS failures. We render the timestamp and
  // the persisted error code/message so the operator can triage
  // (bad image vs. OPENAI_API_KEY misconfig vs. transient outage)
  // without having to dig through Vercel logs. There's no retry
  // affordance here yet — V0.8 will add a "重新识别" button that
  // resets `extract_attempts` and flips status back to extracting.
  @Builder
  private failedDraftListCard(): void {
    Column({ space: 8 }) {
      Text(`识别失败 (${this.failedDrafts.length})`)
        .id('ParentAdminFailedTitle')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor('#C0392B');
      Text('AI 已多次尝试仍未识别成功，请联系管理员检查后端日志。')
        .fontSize(13)
        .fontColor('#666666');
      ForEach(this.failedDrafts, (d: LessonDraftDto): void => {
        this.failedDraftRow(d);
      }, (d: LessonDraftDto): string => d.id);
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#FBEAEA')
    .borderRadius(12)
    .alignItems(HorizontalAlign.Start);
  }

  @Builder
  private failedDraftRow(d: LessonDraftDto): void {
    Column({ space: 4 }) {
      Row({ space: 8 }) {
        Text(this.formatTimestamp(d.created_at))
          .id(`LessonDraftFailedRow_${d.id}`)
          .fontSize(13)
          .fontColor('#3F2F1A')
          .layoutWeight(1);
        Text(`${d.extract_attempts} 次`)
          .fontSize(12)
          .fontColor('#888888');
      }
      .width('100%');
      Text(this.formatFailureReason(d))
        .fontSize(12)
        .fontColor('#C0392B');
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
    .alignItems(HorizontalAlign.Start);
  }

  private formatFailureReason(d: LessonDraftDto): string {
    const code: string = d.extract_last_error_code ?? 'UNKNOWN';
    const msg: string = d.extract_last_error_message ?? '(no message)';
    return `[${code}] ${msg}`;
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
