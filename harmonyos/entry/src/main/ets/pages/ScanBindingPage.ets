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
import {
  BarcodeImageDecoderLike,
  RealBarcodeImageDecoder,
  SCAN_BINDING_PHOTO_PICKER_OVERRIDE_URI_KEY,
} from '../services/BarcodeImageDecoder';
import {
  IPhotoPickerAdapter,
  PickedFileRef,
  RealPhotoPickerAdapter,
} from '../services/PhotoPickerService';
import { DeviceIdProvider } from '../services/DeviceIdProvider';
import { BindingApiClient } from '../services/BindingApiClient';
import { RealParentFetchAdapter } from '../services/ParentApiClient';
import { effectiveServerBaseUrl, parentFamilyLoginPageUrl } from '../services/RemoteWordPackConfig';
import { openUrlInAppBrowser } from '../services/SystemBrowser';
import { ensureCloudSyncInstalled } from '../services/CloudSyncInstaller';
import { PRIVACY_POLICY_URL, TERMS_OF_SERVICE_URL } from '../services/CompliancePolicy';
import { PAGE_BODY_EDGE_VP } from '../constants/PageLayoutInsets';
import { PageTopChrome } from '../components/PageTopChrome';
import { requestPageOrientation } from '../utils/orientation';

class RealScanKitScanner implements BarcodeScannerLike {
  private ctx: common.UIAbilityContext;

  constructor(ctx: common.UIAbilityContext) {
    this.ctx = ctx;
  }

  async scan(): Promise<string> {
    // V0.6.x — `enableAlbum: true` exposes ScanKit's built-in album
    // button in the system scan UI, in addition to the dedicated
    // ScanBindingGalleryButton on the page itself. Both paths funnel
    // into the same redeem state machine: when the user picks an
    // image from inside the system scan modal, ScanKit decodes it
    // server-side and returns the QR string through the same
    // `startScanForResult` Promise as a camera-captured scan would.
    const opts: scanBarcode.ScanOptions = {
      scanTypes: [scanCore.ScanType.QR_CODE],
      enableMultiMode: false,
      enableAlbum: true,
    };
    try {
      const r: scanBarcode.ScanResult = await scanBarcode.startScanForResult(
        this.ctx,
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
  /**
   * Mirror of `this.service !== undefined`. ArkUI only re-renders when
   * @State (or sibling decorated) fields change; assigning to a plain
   * private field inside `bootstrapService().then(...)` does NOT trigger
   * a rebuild, so without this flag the "打开扫码器" button stays gated
   * on its initial false value forever and clicks become silent no-ops.
   */
  @State private serviceReady: boolean = false;
  /** After first successful bind, auto-open parent PIN setup once. */
  @State private pinSetupNavigated: boolean = false;

  private service?: DeviceBindingService;
  private galleryPicker?: IPhotoPickerAdapter;

  private applyOrientationPolicy(): void {
    requestPageOrientation(
      this.getUIContext().getHostContext() as common.UIAbilityContext,
      'ScanBindingPage',
      (px: number): number => this.getUIContext().px2vp(px),
    );
  }

  aboutToAppear(): void {
    this.applyOrientationPolicy();
    this.bootstrapService();
  }

  onPageShow(): void {
    this.applyOrientationPolicy();
  }

  private bootstrapService(): void {
    const ctx: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    const provider: DeviceIdProvider = new DeviceIdProvider();
    const credentials: CloudCredentials = new CloudCredentials();
    const baseUrl: string = effectiveServerBaseUrl();
    const httpClient: BindingApiClient = new BindingApiClient(
      new RealParentFetchAdapter(),
      baseUrl,
    );
    // V0.6.x — gallery-QR picker + decoder. Both adapters are constructed
    // synchronously here (independent of the async provider/credentials
    // init below) so the picker reference can be saved alongside the
    // service when bootstrap completes.
    const galleryPicker: IPhotoPickerAdapter =
      new RealPhotoPickerAdapter(ctx, SCAN_BINDING_PHOTO_PICKER_OVERRIDE_URI_KEY);
    const decoder: BarcodeImageDecoderLike = new RealBarcodeImageDecoder();

    Promise.all([provider.init(ctx), credentials.init(ctx)])
      .then(() => {
        const svc: DeviceBindingService = new DeviceBindingService(
          new RealScanKitScanner(ctx),
          decoder,
          httpClient,
          provider,
          credentials,
        );
        svc.setListener((u: BindingStateUpdate): void => {
          this.state = u.state;
          if (u.snapshot !== undefined) {
            this.childNickname = u.snapshot.nickname;
          }
          if (u.state === 'bound') {
            ensureCloudSyncInstalled(ctx).catch((err: BusinessError): void => {
              console.error(`ScanBindingPage.ensureCloudSyncInstalled failed: ${JSON.stringify(err)}`);
            });
            this.scheduleParentPinSetupIfNeeded();
          }
          if (u.reason !== undefined) {
            this.failureReason = u.reason as string;
          }
        });
        this.service = svc;
        this.galleryPicker = galleryPicker;
        this.serviceReady = true;
      })
      .catch((err: BusinessError) => {
        console.error(`ScanBindingPage.bootstrap failed: ${JSON.stringify(err)}`);
        this.serviceReady = false;
      });
  }

  /**
   * Binding success routes to ParentPinSetupPage so the parent sets a PIN
   * before dismissing back to this page's success summary.
   */
  private scheduleParentPinSetupIfNeeded(): void {
    if (this.pinSetupNavigated) {
      return;
    }
    this.pinSetupNavigated = true;
    const router = this.getUIContext().getRouter();
    setTimeout((): void => {
      router.pushUrl({ url: 'pages/ParentPinSetupPage' }).catch((err: BusinessError): void => {
        console.error(`ScanBindingPage.scheduleParentPinSetupIfNeeded: ${JSON.stringify(err)}`);
      });
    }, 0);
  }

  // Note: using a method (not a TS getter) because ArkUI's `@Entry`/
  // `@Component` struct rendering does not invoke TS property getters
  // inside `build()`; the access surfaces as undefined and crashes
  // with "Cannot read property length of undefined".
  private reasonHint(): string {
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

  /**
   * V0.6.x — open the system gallery, decode the picked image, and
   * feed the resulting payload into the same redeem path the camera
   * scanner uses. User cancel (picker returns null) silently returns
   * to idle with no error message; decoder / parser failures surface
   * as TOKEN_INVALID via DeviceBindingService.startFromGalleryImage.
   */
  private async onPickQrTap(): Promise<void> {
    if (this.service === undefined || this.galleryPicker === undefined || this.busy) {
      return;
    }
    this.busy = true;
    this.failureReason = '';
    try {
      const ref: PickedFileRef | null = await this.galleryPicker.selectGallery();
      if (ref === null) {
        return;
      }
      await this.service.startFromGalleryImage(ref.uri);
    } finally {
      this.busy = false;
    }
  }

  private onParentLoginLinkTap(): void {
    const url: string = parentFamilyLoginPageUrl();
    openUrlInAppBrowser(this.getUIContext(), url).catch((err: Error): void => {
      console.error(`ScanBindingPage.onParentLoginLinkTap: ${err.message}`);
      try {
        this.getUIContext().getPromptAction().showToast({
          message: 'Could not open browser',
          duration: 2000,
        });
      } catch (toastErr) {
        console.error(`ScanBindingPage.onParentLoginLinkTap toast: ${JSON.stringify(toastErr as BusinessError)}`);
      }
    });
  }

  private openComplianceUrl(url: string): void {
    openUrlInAppBrowser(this.getUIContext(), url).catch((err: Error): void => {
      console.error(`ScanBindingPage.openComplianceUrl failed: ${err.message}`);
    });
  }

  @Builder
  private complianceLinks() {
    Column({ space: 6 }) {
      Text('绑定或登录前请阅读')
        .id('ScanBindingCompliancePrompt')
        .fontSize(12)
        .fontColor('#475569');
      Row({ space: 12 }) {
        Button('用户协议')
          .id('ScanBindingTermsButton')
          .height(36)
          .fontSize(13)
          .backgroundColor(Color.Transparent)
          .fontColor('#1D4ED8')
          .onClick((): void => this.openComplianceUrl(TERMS_OF_SERVICE_URL));
        Button('隐私政策')
          .id('ScanBindingPrivacyButton')
          .height(36)
          .fontSize(13)
          .backgroundColor(Color.Transparent)
          .fontColor('#1D4ED8')
          .onClick((): void => this.openComplianceUrl(PRIVACY_POLICY_URL));
      }
      .justifyContent(FlexAlign.Center);
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .margin({ top: 4 });
  }

  build() {
    Column() {
      PageTopChrome({
        backButtonId: 'ScanBindingTopBack',
        title: '扫码绑定家长账号',
        titleId: 'ScanBindingTitle',
        onBack: (): void => {
          this.getUIContext().getRouter().back();
        },
      })

      if (this.state === 'bound') {
        Column() {
          Text('🎉')
            .id('ScanBindingSuccessEmoji')
            .fontSize(48)
          Text(`绑定成功，${this.childNickname || '宝贝'}！`)
            .id('ScanBindingSuccessLabel')
            .fontSize(18).fontWeight(FontWeight.Bold).margin({ top: 8 })
          Button('返回首页')
            .id('ScanBindingSuccessBack')
            .margin({ top: 24 })
            .onClick((): void => {
            this.getUIContext().getRouter().back();
          })
        }.width('100%').padding(PAGE_BODY_EDGE_VP)
      } else if (this.manualMode) {
        Column({ space: 12 }) {
          Text('输入家长网页显示的 6 位短码').fontSize(14).fontColor('#475569')
          TextInput({ placeholder: '000000', text: this.manualCode })
            .id('ScanBindingManualInput')
            .type(InputType.Number).maxLength(6)
            .fontSize(28).textAlign(TextAlign.Center)
            .width('60%').margin({ top: 8 })
            .onChange((v: string) => { this.manualCode = v; })
          Button(this.busy ? '正在验证…' : '提交')
            .id('ScanBindingManualSubmit')
            .enabled(!this.busy && this.serviceReady && this.manualCode.length === 6)
            .onClick(() => this.onSubmitShortCode())
          Button('返回扫码')
            .id('ScanBindingManualBackToScan')
            .backgroundColor('#e2e8f0').fontColor('#1f2937')
            .onClick(() => { this.manualMode = false; this.manualCode = ''; })
          Button('创建或登录 家长账号')
            .id('ScanBindingParentLoginLinkManual')
            .fontSize(14)
            .height(40)
            .backgroundColor(Color.Transparent)
            .fontColor('#2563eb')
            .margin({ top: 8 })
            .onClick((): void => {
              this.onParentLoginLinkTap();
            })
          this.complianceLinks();
          if (this.reasonHint().length > 0) {
            Text(this.reasonHint()).fontColor('#dc2626').fontSize(13).margin({ top: 8 })
          }
        }.width('100%').padding(PAGE_BODY_EDGE_VP)
      } else {
        Column({ space: 12 }) {
          Text('请扫描家长端「添加设备」页面显示的二维码')
            .id('ScanBindingIdlePrompt')
            .fontSize(14).fontColor('#475569').textAlign(TextAlign.Center)
          Button(this.busy ? '正在打开扫码器…' : '打开扫码器')
            .id('ScanBindingScannerButton')
            .enabled(!this.busy && this.serviceReady)
            .margin({ top: 16 })
            .onClick(() => this.onScanTap())
          Button('📷 从图库选择二维码')
            .id('ScanBindingGalleryButton')
            .enabled(!this.busy && this.serviceReady)
            .onClick(() => this.onPickQrTap())
          Button('无法扫码？手动输入短码')
            .id('ScanBindingManualToggle')
            .backgroundColor('#e2e8f0').fontColor('#1f2937')
            .onClick(() => { this.manualMode = true; })
          Button('创建或登录 家长账号')
            .id('ScanBindingParentLoginLink')
            .fontSize(14)
            .height(40)
            .backgroundColor(Color.Transparent)
            .fontColor('#2563eb')
            .margin({ top: 8 })
            .onClick((): void => {
              this.onParentLoginLinkTap();
            })
          this.complianceLinks();
          if (this.reasonHint().length > 0) {
            Text(this.reasonHint()).fontColor('#dc2626').fontSize(13).margin({ top: 16 })
          }
        }.width('100%').padding(PAGE_BODY_EDGE_VP)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#f8fafc')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM,
      SafeAreaEdge.START, SafeAreaEdge.END]);
  }
}
