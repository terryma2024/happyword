import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { CloudCredentials, CloudCredentialsSnapshot } from '../services/CloudCredentials';
import { DeviceIdProvider, DeviceIdResult } from '../services/DeviceIdProvider';

@Entry
@Component
struct BoundDeviceInfoPage {
  @State private snap: CloudCredentialsSnapshot = new CloudCredentialsSnapshot();
  @State private deviceIdSuffix: string = '';
  @State private deviceIdSource: string = '';
  @State private busy: boolean = false;
  @State private ready: boolean = false;
  private credentials: CloudCredentials = new CloudCredentials();
  private provider: DeviceIdProvider = new DeviceIdProvider();

  aboutToAppear(): void {
    const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
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
      router.back();
    } finally {
      this.busy = false;
    }
  }

  build() {
    Column() {
      Row() {
        Text('家长账户').fontSize(20).fontWeight(FontWeight.Bold).fontColor('#1f2937')
        Blank()
        Button('返回').fontSize(14).backgroundColor('#e2e8f0').fontColor('#1f2937')
          .onClick(() => router.back())
      }
      .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })

      if (!this.ready) {
        Text('加载中…').fontSize(14).fontColor('#64748b').padding(24)
      } else if (!this.snap.isBound()) {
        Text('当前未绑定家长账号。').fontSize(14).fontColor('#64748b').padding(24)
      } else {
        Column({ space: 12 }) {
          this.row('孩子档案', `${this.snap.avatarEmoji || '🦄'} ${this.snap.nickname || '宝贝'}`)
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
        .width('100%').padding(24)
      }
    }
    .width('100%').height('100%').backgroundColor('#f8fafc')
  }

  @Builder
  row(label: string, value: string) {
    Row() {
      Text(label).fontSize(14).fontColor('#64748b').width(140)
      Text(value).fontSize(14).fontColor('#1f2937').textAlign(TextAlign.End)
        .layoutWeight(1)
    }
    .width('100%').padding({ top: 8, bottom: 8 })
  }
}
