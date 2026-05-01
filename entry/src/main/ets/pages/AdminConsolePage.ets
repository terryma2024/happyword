import { BusinessError } from '@ohos.base';
import {
  AdminApiClient,
  AdminAuthError,
  AdminHttpError,
  AdminPackPublished,
  AdminStats,
} from '../services/AdminApiClient';
import { SERVER_BASE_URL } from '../services/RemoteWordPackConfig';

/**
 * AdminConsolePage — V0.5.F MVP. Single-page admin shell that exposes
 * the highest-value server admin operations in a parent-PIN-gated UI:
 *  - Login (writes the JWT into AppStorage so subsequent visits skip
 *    the login form for the duration of the session).
 *  - Stats dashboard.
 *  - Publish a fresh word pack (POST /api/v1/admin/packs/publish).
 *  - Logout.
 *
 * Word CRUD, draft generation and asset upload remain CLI-only via the
 * existing server scripts (seed_from_rawfile.py, publish_pack.py,
 * backup_pack.py); a follow-up commit can plug additional admin pages
 * onto this surface as need arises.
 */

const ADMIN_JWT_KEY: string = 'admin_jwt';
const TOAST_MS: number = 3000;

@Entry
@Component
struct AdminConsolePage {
  @State private username: string = '';
  @State private password: string = '';
  @State private busy: boolean = false;
  @State private hasToken: boolean = false;
  @State private toast: string = '';
  @State private stats?: AdminStats = undefined;
  @State private publishedSummary: string = '';
  @State private publishNotes: string = '';
  private toastTimer: number = -1;
  private client: AdminApiClient = AdminApiClient.withRealHttp(SERVER_BASE_URL);

  aboutToAppear(): void {
    const stored: string | undefined = AppStorage.get<string>(ADMIN_JWT_KEY);
    if (stored !== undefined && stored.length > 0) {
      this.client.setBearerToken(stored);
      this.hasToken = true;
      this.refreshStats();
    }
  }

  aboutToDisappear(): void {
    if (this.toastTimer >= 0) {
      clearTimeout(this.toastTimer);
      this.toastTimer = -1;
    }
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

  private async submitLogin(): Promise<void> {
    if (this.username.length === 0 || this.password.length === 0) {
      this.showToast('请填写用户名和密码');
      return;
    }
    this.busy = true;
    try {
      const tok: string = await this.client.login(this.username, this.password);
      AppStorage.setOrCreate<string>(ADMIN_JWT_KEY, tok);
      this.password = '';
      this.hasToken = true;
      this.showToast('登录成功');
      await this.refreshStats();
    } catch (err) {
      if (err instanceof AdminAuthError) {
        this.showToast('账号或密码错误');
      } else if (err instanceof AdminHttpError) {
        this.showToast(`登录失败 (HTTP ${err.status})`);
      } else {
        const be: BusinessError = err as BusinessError;
        this.showToast(`登录异常: ${be.message ?? 'unknown'}`);
      }
    } finally {
      this.busy = false;
    }
  }

  private async refreshStats(): Promise<void> {
    if (!this.hasToken) {
      return;
    }
    this.busy = true;
    try {
      this.stats = await this.client.getStats();
    } catch (err) {
      if (err instanceof AdminAuthError) {
        this.handleAuthExpiry();
      } else if (err instanceof AdminHttpError) {
        this.showToast(`刷新失败 (HTTP ${err.status})`);
      } else {
        const be: BusinessError = err as BusinessError;
        this.showToast(`刷新异常: ${be.message ?? 'unknown'}`);
      }
    } finally {
      this.busy = false;
    }
  }

  private async publishPack(): Promise<void> {
    if (!this.hasToken) {
      return;
    }
    this.busy = true;
    try {
      const notes: string | undefined =
        this.publishNotes.length > 0 ? this.publishNotes : undefined;
      const out: AdminPackPublished = await this.client.publishPack(notes);
      this.publishedSummary =
        `已发布 v${out.version} (schema_v${out.schemaVersion}, ${out.wordCount} 词)`;
      this.publishNotes = '';
      await this.refreshStats();
    } catch (err) {
      if (err instanceof AdminAuthError) {
        this.handleAuthExpiry();
      } else if (err instanceof AdminHttpError) {
        this.showToast(`发布失败 (HTTP ${err.status})`);
      } else {
        const be: BusinessError = err as BusinessError;
        this.showToast(`发布异常: ${be.message ?? 'unknown'}`);
      }
    } finally {
      this.busy = false;
    }
  }

  private handleAuthExpiry(): void {
    AppStorage.delete(ADMIN_JWT_KEY);
    this.client.clearBearerToken();
    this.hasToken = false;
    this.stats = undefined;
    this.showToast('会话已过期，请重新登录');
  }

  private logout(): void {
    AppStorage.delete(ADMIN_JWT_KEY);
    this.client.clearBearerToken();
    this.hasToken = false;
    this.stats = undefined;
    this.publishedSummary = '';
    this.showToast('已退出登录');
  }

  private back(): void {
    this.getUIContext().getRouter().back();
  }

  private formatLatestVersion(): string {
    const s: AdminStats | undefined = this.stats;
    if (s === undefined || s.latestVersion === undefined) {
      return '—';
    }
    return `v${s.latestVersion}`;
  }

  private formatLastPublishedAt(): string {
    const s: AdminStats | undefined = this.stats;
    if (s === undefined || s.lastPublishedAt === undefined || s.lastPublishedAt.length === 0) {
      return '—';
    }
    return s.lastPublishedAt;
  }

  build(): void {
    Scroll() {
      Column({ space: 16 }) {
        Row() {
          Button('返回')
            .id('AdminConsoleBack')
            .width(80)
            .height(36)
            .fontSize(14)
            .backgroundColor('#EAF2F8')
            .fontColor('#457B9D')
            .onClick((): void => this.back());
          Blank();
          Text('管理员控制台')
            .id('AdminConsoleTitle')
            .fontSize(20)
            .fontWeight(FontWeight.Bold);
          Blank();
          if (this.hasToken) {
            Button('退出')
              .id('AdminConsoleLogout')
              .width(80)
              .height(36)
              .fontSize(14)
              .backgroundColor('#FFEAEA')
              .fontColor('#E63946')
              .onClick((): void => this.logout());
          } else {
            Text('').width(80);
          }
        }
        .width('100%');

        Text(`服务器: ${SERVER_BASE_URL}`)
          .id('AdminConsoleServerLabel')
          .fontSize(13)
          .fontColor('#666666');

        if (!this.hasToken) {
          this.loginCard();
        } else {
          this.statsCard();
          this.publishCard();
        }

        if (this.toast.length > 0) {
          Text(this.toast)
            .id('AdminConsoleToast')
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
  private loginCard(): void {
    Column({ space: 12 }) {
      Text('登录').fontSize(18).fontWeight(FontWeight.Medium);
      TextInput({ placeholder: '用户名', text: this.username })
        .id('AdminConsoleUsername')
        .width('100%')
        .height(44)
        .enabled(!this.busy)
        .onChange((v: string): void => {
          this.username = v;
        });
      TextInput({ placeholder: '密码', text: this.password })
        .id('AdminConsolePassword')
        .type(InputType.Password)
        .width('100%')
        .height(44)
        .enabled(!this.busy)
        .onChange((v: string): void => {
          this.password = v;
        });
      Button(this.busy ? '登录中…' : '登录')
        .id('AdminConsoleLoginButton')
        .width('100%')
        .height(44)
        .fontSize(16)
        .backgroundColor(this.busy ? '#F0F0F0' : '#1D3557')
        .fontColor(this.busy ? '#999999' : '#FFFFFF')
        .enabled(!this.busy)
        .onClick((): void => {
          this.submitLogin().catch((err: BusinessError): void => {
            console.error(`AdminConsolePage.submitLogin failed: ${JSON.stringify(err)}`);
          });
        });
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#F7F9FC')
    .borderRadius(12);
  }

  @Builder
  private statsCard(): void {
    Column({ space: 8 }) {
      Row() {
        Text('概览').fontSize(18).fontWeight(FontWeight.Medium);
        Blank();
        Button('刷新')
          .id('AdminConsoleRefresh')
          .width(80)
          .height(32)
          .fontSize(13)
          .backgroundColor('#EAF2F8')
          .fontColor('#457B9D')
          .enabled(!this.busy)
          .onClick((): void => {
            this.refreshStats().catch((err: BusinessError): void => {
              console.error(`AdminConsolePage.refreshStats failed: ${JSON.stringify(err)}`);
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
          .id('AdminConsoleStatsEmpty')
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
        .id(`AdminConsoleStat_${label}`)
        .fontSize(14)
        .fontColor('#1D3557');
    }
    .width('100%')
    .margin({ bottom: 4 });
  }

  @Builder
  private publishCard(): void {
    Column({ space: 12 }) {
      Text('发布新版本词包').fontSize(18).fontWeight(FontWeight.Medium);
      Text('从最新词库快照打包并发布。客户端需要在配置页手动同步后才能看到新版本。')
        .fontSize(13)
        .fontColor('#666666');
      TextInput({ placeholder: '备注（可选，最多 500 字）', text: this.publishNotes })
        .id('AdminConsolePublishNotes')
        .width('100%')
        .height(44)
        .enabled(!this.busy)
        .onChange((v: string): void => {
          this.publishNotes = v;
        });
      Button(this.busy ? '发布中…' : '立即发布')
        .id('AdminConsolePublishButton')
        .width('100%')
        .height(44)
        .fontSize(16)
        .backgroundColor(this.busy ? '#F0F0F0' : '#E63946')
        .fontColor(this.busy ? '#999999' : '#FFFFFF')
        .enabled(!this.busy)
        .onClick((): void => {
          this.publishPack().catch((err: BusinessError): void => {
            console.error(`AdminConsolePage.publishPack failed: ${JSON.stringify(err)}`);
          });
        });
      if (this.publishedSummary.length > 0) {
        Text(this.publishedSummary)
          .id('AdminConsolePublishSummary')
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
