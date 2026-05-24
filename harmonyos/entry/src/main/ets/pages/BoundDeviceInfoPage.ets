import { common } from '@kit.AbilityKit';
import { BusinessError } from '@ohos.base';
import { CloudCredentials, CloudCredentialsSnapshot } from '../services/CloudCredentials';
import { DeviceIdProvider, DeviceIdResult } from '../services/DeviceIdProvider';
import {
  ChildProfileApiClient,
  ChildProfileHttpError,
  UpdatedChildProfile,
} from '../services/ChildProfileApiClient';
import { RealParentFetchAdapter } from '../services/ParentApiClient';
import { DeviceUnbindClient, DeviceUnbindOutcome } from '../services/DeviceUnbindClient';
import { effectiveServerBaseUrl } from '../services/RemoteWordPackConfig';
import { getLearningRecorder, LearningRecorder } from '../services/LearningRecorder';
import {
  GameConfig,
  GAME_CONFIG_STORAGE_KEY,
} from '../models/GameConfig';
import { ParentPinDialog } from '../components/ParentPinDialog';
import {
  EditChildNicknameDialog,
  NicknameSubmitResult,
} from '../components/EditChildNicknameDialog';
import { PageTopChrome } from '../components/PageTopChrome';
import { PAGE_BODY_EDGE_VP } from '../constants/PageLayoutInsets';
import { requestPageOrientation } from '../utils/orientation';

@Entry
@Component
struct BoundDeviceInfoPage {
  @State private snap: CloudCredentialsSnapshot = new CloudCredentialsSnapshot();
  @State private deviceIdSuffix: string = '';
  @State private deviceIdSource: string = '';
  @State private busy: boolean = false;
  @State private ready: boolean = false;
  @State private nicknameToastText: string = '';
  @State private unbindToastText: string = '';
  private nicknameToastTimer: number = -1;
  private unbindToastTimer: number = -1;
  private credentials: CloudCredentials = new CloudCredentials();
  private provider: DeviceIdProvider = new DeviceIdProvider();
  private editDialog: CustomDialogController | null = null;
  private unbindPinDialog: CustomDialogController | null = null;

  private applyOrientationPolicy(): void {
    requestPageOrientation(
      this.getUIContext().getHostContext() as common.UIAbilityContext,
      'BoundDeviceInfoPage',
      (px: number): number => this.getUIContext().px2vp(px),
    );
  }

  aboutToAppear(): void {
    this.applyOrientationPolicy();
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

  onPageShow(): void {
    this.applyOrientationPolicy();
  }

  private formatPairedAt(): string {
    if (this.snap.pairedAtMs <= 0) {
      return '—';
    }
    const d: Date = new Date(this.snap.pairedAtMs);
    return d.toLocaleString();
  }

  /**
   * V0.6.7.2 — opens a parent-PIN gate, then calls
   * `POST /api/v1/family/{family_id}/unbind` on confirm. The PIN dialog reuses the
   * shared `ParentPinDialog` component so the UX mirrors the
   * `进入家长后台` flow. On success `DeviceUnbindClient` clears the
   * local credentials, we detach the cloud-sync handler, and route
   * back to ConfigPage (which re-renders into the unbound state via
   * its `onPageShow` → `refreshBindingState` pass).
   *
   * Moved from ConfigPage in V0.6.7.2 — previously this page only
   * cleared local credentials with a "(本地)" suffix; the proper
   * server-side revocation lived behind the now-removed
   * `ConfigUnbindBindingButton` row.
   */
  private onUnbindTap(): void {
    if (this.busy) {
      return;
    }
    const stored: GameConfig | undefined =
      AppStorage.get<GameConfig>(GAME_CONFIG_STORAGE_KEY);
    const expected: string = stored !== undefined ? stored.parentPin : '';
    if (expected.length !== 6) {
      this.showUnbindToast('请先在「家长密码」中设置 6 位 PIN');
      return;
    }
    let ctrl: CustomDialogController | null = null;
    ctrl = new CustomDialogController({
      builder: ParentPinDialog({
        expectedPin: expected,
        title: '解除设备绑定需要家长密码',
        onConfirm: (): void => {
          if (ctrl !== null) {
            ctrl.close();
          }
          this.runUnbind().catch((err: BusinessError): void => {
            console.error(`BoundDeviceInfoPage.runUnbind promise failed: ${JSON.stringify(err)}`);
          });
        },
        onCancel: (): void => {
          if (ctrl !== null) {
            ctrl.close();
          }
        },
      }),
      autoCancel: true,
      customStyle: true,
    });
    this.unbindPinDialog = ctrl;
    ctrl.open();
  }

  private async runUnbind(): Promise<void> {
    if (this.busy) {
      return;
    }
    // V0.6.7.3 codelinter (@performance/hp-arkui-use-local-var-to-replace-state-var):
    // single try/finally ensures `this.busy` is written from exactly
    // one site (`true` at entry, `false` in finally) rather than the
    // earlier two-site try/catch pattern that the rule flagged. The
    // resulting outcome (success/HTTP error / thrown error) is kept
    // in a local variable and only fed to `showUnbindToast` after the
    // finally block has cleared the busy flag.
    this.busy = true;
    const adapter: RealParentFetchAdapter = new RealParentFetchAdapter();
    const baseUrl: string = effectiveServerBaseUrl();
    const client: DeviceUnbindClient =
      new DeviceUnbindClient(this.credentials, adapter, baseUrl);
    let outcome: DeviceUnbindOutcome | null = null;
    let networkError: boolean = false;
    try {
      outcome = await client.unbind();
    } catch (err) {
      console.error(`BoundDeviceInfoPage.runUnbind failed: ${JSON.stringify(err)}`);
      networkError = true;
    } finally {
      this.busy = false;
    }

    if (networkError || outcome === null) {
      this.showUnbindToast('解除失败 (网络错误)');
      return;
    }
    if (!outcome.ok) {
      this.showUnbindToast(`解除失败 (HTTP ${outcome.status})`);
      return;
    }
    // DeviceUnbindClient already cleared local credentials on 200/404.
    // Detach the recorder's cloud-sync handler so subsequent battles
    // don't try to push to a now-revoked binding.
    const recorder: LearningRecorder = getLearningRecorder();
    recorder.attachCloudSync(undefined);
    this.showUnbindToast('已解除设备绑定');
    // Route back to ConfigPage; its onPageShow will re-run
    // refreshBindingState and flip the page to the unbound layout.
    // A short delay lets the toast surface for ~600 ms before the
    // page pops, matching the ConfigPage UX it replaces.
    setTimeout((): void => {
      this.getUIContext().getRouter().back();
    }, 600);
  }

  private showUnbindToast(text: string): void {
    this.unbindToastText = text;
    if (this.unbindToastTimer !== -1) {
      clearTimeout(this.unbindToastTimer);
    }
    this.unbindToastTimer = setTimeout((): void => {
      this.unbindToastText = '';
      this.unbindToastTimer = -1;
    }, 4000);
  }

  private openEditNickname(): void {
    this.editDialog = new CustomDialogController({
      builder: EditChildNicknameDialog({
        initialNickname: this.snap.nickname,
        initialAvatarEmoji: this.snap.avatarEmoji,
        onSubmit: (trimmed: string, avatarEmoji: string): Promise<NicknameSubmitResult> => {
          return this.persistNickname(trimmed, avatarEmoji);
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
      case 'BINDING_NOT_FOUND':
        return '当前后端未找到绑定记录。若在开发者菜单切换过服务器，请改回配对时的环境或重新扫码。';
      case 'BINDING_REVOKED':
        return '绑定已被撤销，请在家长网页确认设备状态或重新扫码配对。';
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
  private async persistNickname(trimmed: string, avatarEmoji: string): Promise<NicknameSubmitResult> {
    const adapter: RealParentFetchAdapter = new RealParentFetchAdapter();
    const baseUrl: string = effectiveServerBaseUrl();
    const client: ChildProfileApiClient = new ChildProfileApiClient(adapter, baseUrl);
    try {
      const updated: UpdatedChildProfile =
        await client.updateProfile(this.snap.deviceToken, this.snap.familyId, trimmed, avatarEmoji);
      const next: CloudCredentialsSnapshot = new CloudCredentialsSnapshot();
      next.deviceToken = this.snap.deviceToken;
      next.bindingId = this.snap.bindingId;
      next.familyId = this.snap.familyId;
      next.childProfileId = this.snap.childProfileId;
      next.nickname = updated.nickname;
      next.avatarEmoji = updated.avatarEmoji.length > 0 ? updated.avatarEmoji : avatarEmoji;
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
      console.error(`BoundDeviceInfoPage.persistNickname failed: ${httpErr.code} ${httpErr.status}`);
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
        PageTopChrome({
          backButtonId: 'BoundDeviceInfoBack',
          title: '孩子档案',
          titleId: 'BoundDeviceInfoTitle',
          onBack: (): void => {
            this.getUIContext().getRouter().back();
          },
        })

        if (!this.ready) {
          Text('加载中…').fontSize(14).fontColor('#64748b').padding(24)
        } else if (!this.snap.isBound()) {
          Text('当前未绑定家长账号。').fontSize(14).fontColor('#64748b').padding(24)
        } else {
          // Landscape / tablet: avoid label–––huge gap–––value; keep a
          // readable column centered with capped width (matches DevEco preview).
          Column() {
            Column({ space: 4 }) {
              this.editableNicknameRow()
              this.row('Family ID', this.snap.familyId)
              this.row('Binding ID', this.snap.bindingId)
              this.row('Device ID 末四位', this.deviceIdSuffix)
              this.row('Device ID 来源', this.deviceIdSource === 'asset_store'
                ? 'AssetStoreKit (持久)'
                : '本地 preferences (重装即丢)')
              this.row('绑定时间', this.formatPairedAt())

              Button(this.busy ? '正在解除…' : '解除设备绑定')
                .id('BoundDeviceInfoUnbindButton')
                .width('100%')
                .backgroundColor('#dc2626').fontColor('#ffffff')
                .enabled(!this.busy).margin({ top: 16 })
                .onClick((): void => this.onUnbindTap())
              if (this.unbindToastText.length > 0) {
                Text(this.unbindToastText)
                  .id('BoundDeviceInfoUnbindToast')
                  .fontSize(12).fontColor('#B91C1C').margin({ top: 8 })
                  .width('100%')
              }
            }
            .width('100%')
            .constraintSize({ maxWidth: 520 })
            .padding(16)
            .backgroundColor('#FFFFFF')
            .borderRadius(12)
          }
          .width('100%')
          .padding({
            left: PAGE_BODY_EDGE_VP,
            right: PAGE_BODY_EDGE_VP,
            bottom: PAGE_BODY_EDGE_VP,
          })
          .alignItems(HorizontalAlign.Center)
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
      Text('孩子档案').fontSize(14).fontColor('#64748b').width(112)
      Text(`${this.snap.avatarEmoji || '🦄'} ${this.snap.nickname || '宝贝'}`)
        .id('BoundDeviceInfoNicknameValue')
        .fontSize(14).fontColor('#1f2937').textAlign(TextAlign.Start)
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
      Text(label).fontSize(14).fontColor('#64748b').width(112)
      Text(value).fontSize(14).fontColor('#1f2937').textAlign(TextAlign.Start)
        .layoutWeight(1)
    }
    .width('100%').padding({ top: 6, bottom: 6 })
  }
}
