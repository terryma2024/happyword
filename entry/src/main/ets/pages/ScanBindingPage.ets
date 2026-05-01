import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { scanBarcode, scanCore } from '@kit.ScanKit';
import { BusinessError } from '@ohos.base';
import { CloudCredentials } from '../services/CloudCredentials';
import {
  BarcodeScannerLike,
  BindingState,
  BindingStateUpdate,
  CancelledScanError,
  DeviceBindingService,
} from '../services/DeviceBindingService';
import { DeviceIdProvider } from '../services/DeviceIdProvider';
import { BindingApiClient } from '../services/BindingApiClient';
import { RealParentFetchAdapter } from '../services/ParentApiClient';
import { effectiveServerBaseUrl } from '../services/RemoteWordPackConfig';

class RealScanKitScanner implements BarcodeScannerLike {
  async scan(): Promise<string> {
    const opts: scanBarcode.ScanOptions = {
      scanTypes: [scanCore.ScanType.QR_CODE],
      enableMultiMode: false,
      enableAlbum: false,
    };
    try {
      const r: scanBarcode.ScanResult = await scanBarcode.startScanForResult(
        getContext(this) as common.UIAbilityContext,
        opts,
      );
      return r.originalValue;
    } catch (err) {
      const be: BusinessError = err as BusinessError;
      // Cancellation by user (closing the scan UI) surfaces as code 1000500001;
      // map it to our sentinel so the service returns to Idle quietly.
      if (be.code === 1000500001) {
        throw new CancelledScanError();
      }
      throw new Error(`ScanKit failed: code=${be.code} msg=${be.message}`);
    }
  }
}

@Entry
@Component
struct ScanBindingPage {
  @State private state: BindingState = 'idle';
  @State private failureReason: string = '';
  @State private childNickname: string = '';
  @State private manualMode: boolean = false;
  @State private manualCode: string = '';
  @State private busy: boolean = false;

  private service?: DeviceBindingService;

  aboutToAppear(): void {
    this.bootstrapService();
  }

  private bootstrapService(): void {
    const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    const provider: DeviceIdProvider = new DeviceIdProvider();
    const credentials: CloudCredentials = new CloudCredentials();
    const baseUrl: string = effectiveServerBaseUrl();
    const httpClient: BindingApiClient = new BindingApiClient(
      new RealParentFetchAdapter(),
      baseUrl,
    );

    Promise.all([provider.init(ctx), credentials.init(ctx)])
      .then(() => {
        const svc: DeviceBindingService = new DeviceBindingService(
          new RealScanKitScanner(),
          httpClient,
          provider,
          credentials,
        );
        svc.setListener((u: BindingStateUpdate): void => {
          this.state = u.state;
          if (u.snapshot !== undefined) {
            this.childNickname = u.snapshot.nickname;
          }
          if (u.reason !== undefined) {
            this.failureReason = u.reason as string;
          }
        });
        this.service = svc;
      })
      .catch((err: BusinessError) => {
        console.error(`ScanBindingPage.bootstrap failed: ${JSON.stringify(err)}`);
      });
  }

  private get reasonHint(): string {
    if (this.failureReason === 'TOKEN_EXPIRED') {
      return '二维码已过期，请让家长在网页重新生成。';
    }
    if (this.failureReason === 'TOKEN_REDEEMED') {
      return '此二维码已被使用过。';
    }
    if (this.failureReason === 'TOKEN_INVALID') {
      return '二维码或短码无效。';
    }
    if (this.failureReason === 'NETWORK') {
      return '网络异常，请检查后重试。';
    }
    if (this.failureReason === 'UNKNOWN') {
      return '出错了，请稍后再试。';
    }
    return '';
  }

  private async onScanTap(): Promise<void> {
    if (this.service === undefined || this.busy) {
      return;
    }
    this.busy = true;
    this.failureReason = '';
    try {
      await this.service.start();
    } finally {
      this.busy = false;
    }
  }

  private async onSubmitShortCode(): Promise<void> {
    if (this.service === undefined || this.busy) {
      return;
    }
    this.busy = true;
    this.failureReason = '';
    try {
      await this.service.redeemShortCode(this.manualCode);
    } finally {
      this.busy = false;
    }
  }

  build() {
    Column() {
      Row() {
        Text('扫码绑定家长账号')
          .fontSize(20).fontWeight(FontWeight.Bold).fontColor('#1f2937')
        Blank()
        Button('返回').fontSize(14).backgroundColor('#e2e8f0').fontColor('#1f2937')
          .onClick(() => router.back())
      }
      .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })

      if (this.state === 'bound') {
        Column() {
          Text('🎉').fontSize(48)
          Text(`绑定成功，${this.childNickname || '宝贝'}！`)
            .fontSize(18).fontWeight(FontWeight.Bold).margin({ top: 8 })
          Button('返回首页').margin({ top: 24 }).onClick(() => router.back())
        }.width('100%').padding(24)
      } else if (this.manualMode) {
        Column({ space: 12 }) {
          Text('输入家长网页显示的 6 位短码').fontSize(14).fontColor('#475569')
          TextInput({ placeholder: '000000', text: this.manualCode })
            .type(InputType.Number).maxLength(6)
            .fontSize(28).textAlign(TextAlign.Center)
            .width('60%').margin({ top: 8 })
            .onChange((v: string) => { this.manualCode = v; })
          Button(this.busy ? '正在验证…' : '提交')
            .enabled(!this.busy && this.manualCode.length === 6)
            .onClick(() => this.onSubmitShortCode())
          Button('返回扫码').backgroundColor('#e2e8f0').fontColor('#1f2937')
            .onClick(() => { this.manualMode = false; this.manualCode = ''; })
          if (this.reasonHint.length > 0) {
            Text(this.reasonHint).fontColor('#dc2626').fontSize(13).margin({ top: 8 })
          }
        }.width('100%').padding(24)
      } else {
        Column({ space: 12 }) {
          Text('请扫描家长网页 /parent/devices/add 显示的二维码')
            .fontSize(14).fontColor('#475569').textAlign(TextAlign.Center)
          Button(this.busy ? '正在打开扫码器…' : '打开扫码器')
            .enabled(!this.busy && this.service !== undefined)
            .margin({ top: 16 })
            .onClick(() => this.onScanTap())
          Button('无法扫码？手动输入短码')
            .backgroundColor('#e2e8f0').fontColor('#1f2937')
            .onClick(() => { this.manualMode = true; })
          if (this.reasonHint.length > 0) {
            Text(this.reasonHint).fontColor('#dc2626').fontSize(13).margin({ top: 16 })
          }
        }.width('100%').padding(24)
      }
    }
    .width('100%').height('100%').backgroundColor('#f8fafc')
  }
}
