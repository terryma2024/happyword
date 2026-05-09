import { common } from '@kit.AbilityKit';
import { CloudCredentials, CloudCredentialsSnapshot } from '../services/CloudCredentials';
import { DeviceIdProvider, DeviceIdResult } from '../services/DeviceIdProvider';
import {
  ChildProfileApiClient,
  ChildProfileHttpError,
  UpdatedChildProfile,
} from '../services/ChildProfileApiClient';
import { RealParentFetchAdapter } from '../services/ParentApiClient';
import { effectiveServerBaseUrl } from '../services/RemoteWordPackConfig';
import {
  EditChildNicknameDialog,
  NicknameSubmitResult,
} from '../components/EditChildNicknameDialog';

@Entry
@Component
struct BoundDeviceInfoPage {
  @State private snap: CloudCredentialsSnapshot = new CloudCredentialsSnapshot();
  @State private deviceIdSuffix: string = '';
  @State private deviceIdSource: string = '';
  @State private busy: boolean = false;
  @State private ready: boolean = false;
  @State private nicknameToastText: string = '';
  private nicknameToastTimer: number = -1;
  private credentials: CloudCredentials = new CloudCredentials();
  private provider: DeviceIdProvider = new DeviceIdProvider();
  private editDialog: CustomDialogController | null = null;

  aboutToAppear(): void {
    const ctx: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    Promise.all([this.credentials.init(ctx), this.provider.init(ctx)])
      .then(() => Promise.all([this.credentials.load(), this.provider.get()]))
      .then((tuple: [CloudCredentialsSnapshot, DeviceIdResult]) => {
        this.snap = tuple[0];
        const id: string = tuple[1].deviceId;
        this.deviceIdSuffix = id.length >= 4 ? id.substring(id.length - 4) : id;
        this.deviceIdSource = this.snap.deviceIdSource.length > 0
          ? this.snap.deviceIdSource
          : tuple[1].source;
        this.ready = true;
      })
      .catch((err: Error) => {
        console.error(`BoundDeviceInfoPage.bootstrap failed: ${JSON.stringify(err)}`);
        this.ready = true;
      });
  }

  private formatPairedAt(): string {
    if (this.snap.pairedAtMs <= 0) {
      return '—';
    }
    const d: Date = new Date(this.snap.pairedAtMs);
    return d.toLocaleString();
  }

  private async onUnbind(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    try {
      // V0.6.2: local clear only; server-side revoke ships in V0.6.7. Parents
      // can also revoke from the parent web (DELETE /api/v1/parent/children/:id).
      await this.credentials.clearBinding();
      this.getUIContext().getRouter().back();
    } finally {
      this.busy = false;
    }
  }

  private openEditNickname(): void {
    this.editDialog = new CustomDialogController({
      builder: EditChildNicknameDialog({
        initialNickname: this.snap.nickname,
        onSubmit: (trimmed: string): Promise<NicknameSubmitResult> => {
          return this.persistNickname(trimmed);
        },
        onCancel: (): void => {
          // No-op: dialog dismisses itself.
        },
      }),
      autoCancel: true,
      customStyle: true,
    });
    this.editDialog.open();
  }

  /**
   * Maps server-side error codes (returned by ChildProfileApiClient as
   * `ChildProfileHttpError.code`) to a Chinese user-facing message.
   * Unknown codes fall back to the HTTP status, mirroring the unbind
   * toast in ConfigPage.
   */
  private mapNicknameErrorToMessage(err: ChildProfileHttpError): string {
    switch (err.code) {
      case 'INVALID_NICKNAME':
        return '名字不能为空';
      case 'BINDING_REVOKED':
        return '绑定已被撤销，请重新扫码';
      case 'NETWORK':
        return '网络错误，请稍后重试';
      case 'NOT_BOUND':
        return '当前未绑定，请先扫码';
      default:
        return `保存失败 (HTTP ${err.status || '?'})`;
    }
  }

  /**
   * Sends the PUT, mirrors the server-canonical value into local
   * preferences on success so the HomePage badge + ConfigPage button
   * pick it up on next onPageShow. Returns a NicknameSubmitResult so
   * the dialog can either close itself or surface the inline error.
   */
  private async persistNickname(trimmed: string): Promise<NicknameSubmitResult> {
    const adapter: RealParentFetchAdapter = new RealParentFetchAdapter();
    const baseUrl: string = effectiveServerBaseUrl();
    const client: ChildProfileApiClient = new ChildProfileApiClient(adapter, baseUrl);
    try {
      const updated: UpdatedChildProfile =
        await client.updateNickname(this.snap.deviceToken, trimmed);
      const next: CloudCredentialsSnapshot = new CloudCredentialsSnapshot();
      next.deviceToken = this.snap.deviceToken;
      next.bindingId = this.snap.bindingId;
      next.familyId = this.snap.familyId;
      next.childProfileId = this.snap.childProfileId;
      next.nickname = updated.nickname;
      next.avatarEmoji = this.snap.avatarEmoji;
      next.pairedAtMs = this.snap.pairedAtMs;
      next.deviceIdSource = this.snap.deviceIdSource;
      await this.credentials.saveBinding(next);
      this.snap = next;
      this.showNicknameToast('已保存');
      return { ok: true };
    } catch (err) {
      const httpErr: ChildProfileHttpError = err instanceof ChildProfileHttpError
        ? err
        : new ChildProfileHttpError('UNKNOWN', String(err), 0);
      console.error(`BoundDeviceInfoPage.updateNickname failed: ${httpErr.code} ${httpErr.status}`);
      return { ok: false, message: this.mapNicknameErrorToMessage(httpErr) };
    }
  }

  private showNicknameToast(text: string): void {
    this.nicknameToastText = text;
    if (this.nicknameToastTimer !== -1) {
      clearTimeout(this.nicknameToastTimer);
    }
    this.nicknameToastTimer = setTimeout((): void => {
      this.nicknameToastText = '';
      this.nicknameToastTimer = -1;
    }, 1500);
  }

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column() {
        Row() {
          Text('家长账户').fontSize(20).fontWeight(FontWeight.Bold).fontColor('#1f2937')
          Blank()
          Button('返回').fontSize(14).backgroundColor('#e2e8f0').fontColor('#1f2937')
            .onClick((): void => {
              this.getUIContext().getRouter().back();
            })
        }
        .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })

        if (!this.ready) {
          Text('加载中…').fontSize(14).fontColor('#64748b').padding(24)
        } else if (!this.snap.isBound()) {
          Text('当前未绑定家长账号。').fontSize(14).fontColor('#64748b').padding(24)
        } else {
          // V0.6.9 — tightened row rhythm: outer padding 24 → 16,
          // inter-row Column space 12 → 4, per-row vertical padding
          // 8 → 6 (so between two rows: 28dp → 16dp). The unbind
          // button keeps a clear top margin so it doesn't crowd the
          // last info row.
          Column({ space: 4 }) {
            this.editableNicknameRow()
            this.row('Family ID', this.snap.familyId)
            this.row('Binding ID', this.snap.bindingId)
            this.row('Device ID 末四位', this.deviceIdSuffix)
            this.row('Device ID 来源', this.deviceIdSource === 'asset_store'
              ? 'AssetStoreKit (持久)'
              : '本地 preferences (重装即丢)')
            this.row('绑定时间', this.formatPairedAt())

            Button(this.busy ? '正在解除…' : '解除绑定 (本地)')
              .backgroundColor('#dc2626').fontColor('#ffffff')
              .enabled(!this.busy).margin({ top: 16 })
              .onClick(() => this.onUnbind())
            Text('提示：V0.6.2 仅在本机清除凭据，需在家长网页 → 设备列表 中删除以撤销。')
              .fontSize(12).fontColor('#64748b').margin({ top: 8 })
          }
          .width('100%').padding(16)
        }
      }
      // Background lives on the root Stack (below) so it can
      // expandSafeArea; the inner Column stays full size but the
      // page bg paints under the system gesture / home-indicator strip
      // in landscape (otherwise a grey default shows through).
      .width('100%').height('100%')

      if (this.nicknameToastText.length > 0) {
        Text(this.nicknameToastText)
          .id('BoundDeviceInfoNicknameToast')
          .fontSize(14)
          .fontColor('#ffffff')
          .backgroundColor('#1f2937')
          .borderRadius(12)
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .margin({ top: 80, right: 16 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#f8fafc')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM,
      SafeAreaEdge.START, SafeAreaEdge.END])
  }

  @Builder
  editableNicknameRow(): void {
    Row() {
      Text('孩子档案').fontSize(14).fontColor('#64748b').width(140)
      Text(`${this.snap.avatarEmoji || '🦄'} ${this.snap.nickname || '宝贝'}`)
        .id('BoundDeviceInfoNicknameValue')
        .fontSize(14).fontColor('#1f2937').textAlign(TextAlign.End)
        .layoutWeight(1)
      Button('✏️ 编辑')
        .id('BoundDeviceInfoNicknameEditButton')
        .fontSize(12).height(28)
        .backgroundColor('#e2e8f0').fontColor('#1f2937')
        .margin({ left: 8 })
        .onClick((): void => this.openEditNickname())
    }
    .width('100%').padding({ top: 6, bottom: 6 })
  }

  @Builder
  row(label: string, value: string) {
    Row() {
      Text(label).fontSize(14).fontColor('#64748b').width(140)
      Text(value).fontSize(14).fontColor('#1f2937').textAlign(TextAlign.End)
        .layoutWeight(1)
    }
    .width('100%').padding({ top: 6, bottom: 6 })
  }
}
