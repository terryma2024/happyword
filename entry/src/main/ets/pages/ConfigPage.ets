import { common } from '@kit.AbilityKit';
import { BusinessError } from '@ohos.base';
import {
  GameConfig,
  GAME_CONFIG_STORAGE_KEY,
  TIMER_CHOICES,
  HP_MIN,
  HP_MAX,
  MONSTER_COUNT_MIN,
  MONSTER_COUNT_MAX,
  cloneGameConfig
} from '../models/GameConfig';
import { WordPackCache, WordPackCacheRecord } from '../services/WordPackCache';
import { RemoteWordPackService } from '../services/RemoteWordPackService';
import {
  WordPackSyncService,
  SyncOutcome,
  SyncStatus,
} from '../services/WordPackSyncService';
import { ParentPinDialog } from '../components/ParentPinDialog';
import { CloudCredentials, CloudCredentialsSnapshot } from '../services/CloudCredentials';
import { DeviceUnbindClient, DeviceUnbindOutcome } from '../services/DeviceUnbindClient';
import { RealParentFetchAdapter } from '../services/ParentApiClient';
import { persistGameConfigBestEffort } from '../services/GameConfigPersistence';
import { effectiveServerBaseUrl } from '../services/RemoteWordPackConfig';
import { getLearningRecorder, LearningRecorder } from '../services/LearningRecorder';
import { CloudSyncLike, CloudSyncResult } from '../services/CloudSyncTypes';
import { Pack } from '../models/Pack';
import {
  HomeIntegrationBundle,
  loadHomeIntegration,
} from '../services/PackHomeIntegration';
import { MAX_ACTIVE_PACKS } from '../services/PackSelectionService';
import { GlobalPackService, GlobalPackEnsureResult } from '../services/GlobalPackService';
import { FamilyPackService, FamilyPackEnsureResult } from '../services/FamilyPackService';
import { PackNetworkFetchAdapter } from '../services/PackNetworkFetchAdapter';
/**
 * ConfigPage exposes the five battle knobs (HP / monster count / timer /
 * autoSpeak / parent PIN) plus the V0.6.5.1 📦 pack picker that drives
 * Today's adventure word selection. All edits happen on a local
 * @State draft; 保存 writes the snapshot to AppStorage and 取消
 * returns to HomePage untouched.
 *
 * V0.6.6 cleanup: the legacy 词库类别 (enabledCategories) row and
 * its 自定义 / CustomWordsPage entry point were removed when
 * GameConfig dropped those fields. Word selection is now owned end
 * to end by PackSelectionService (built-in / global / family).
 */
@Entry
@Component
struct ConfigPage {
  @State private draft: GameConfig = new GameConfig();
  @State private syncStatusText: string = '';
  @State private syncToastText: string = '';
  @State private syncBusy: boolean = false;
  // V0.6.2: parent-account binding state. Reloaded on aboutToAppear / onPageShow
  // so the row reflects the latest binding without forcing a page rebuild.
  @State private bindingNickname: string = '';
  @State private bindingPresent: boolean = false;
  @State private bindingDeviceIdSource: string = '';
  // V0.6.4: cloud-sync UI state. The last-sync display tracks the most
  // recent successful syncOnce attempt so parents can confirm the
  // device is in touch with the server.
  @State private cloudSyncBusy: boolean = false;
  @State private cloudSyncStatusText: string = '';
  @State private cloudSyncToastText: string = '';
  @State private unbindBusy: boolean = false;
  @State private unbindToastText: string = '';
  private cloudCreds: CloudCredentials = new CloudCredentials();
  private unbindToastTimer: number = -1;
  private syncToastTimer: number = -1;
  private wordPackCache: WordPackCache = new WordPackCache();
  private adminPinDialog: CustomDialogController | null = null;
  /**
   * V0.6.5.1 — pack-picker state. Loaded async by aboutToAppear via
   * `loadHomeIntegration`; until then `availablePacks` is empty and
   * the section renders a "loading" placeholder. Bumping
   * `packPickerVersion` after every active-set / pin / sync edit
   * forces the @Builder closures to re-render.
   */
  @State private availablePacks: Pack[] = [];
  @State private activePackIds: string[] = [];
  @State private pinnedPackIds: string[] = [];
  @State private packPickerVersion: number = 0;
  @State private packSyncBusy: boolean = false;
  @State private packSyncStatusText: string = '';
  @State private packSyncToastText: string = '';
  private packPickerToastTimer: number = -1;
  private homeIntegration: HomeIntegrationBundle = new HomeIntegrationBundle();

  aboutToAppear(): void {
    const stored: GameConfig | undefined =
      AppStorage.get<GameConfig>(GAME_CONFIG_STORAGE_KEY);
    this.draft = cloneGameConfig(stored !== undefined ? stored : new GameConfig());

    const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;

    // V0.5 client follow-up: wire the manual-sync card. The cache
    // handle is owned by ConfigPage so that re-entering the page
    // shows fresh fetchedAt timestamps without going through
    // WordPackBootstrapper again.
    this.wordPackCache.init(ctx).then((): Promise<void> => this.refreshSyncStatus())
      .catch((err: BusinessError): void => {
        console.error(`ConfigPage: WordPackCache.init failed: ${JSON.stringify(err)}`);
      });

    this.cloudCreds.init(ctx).then((): Promise<void> => this.refreshBindingState())
      .catch((err: BusinessError): void => {
        console.error(`ConfigPage: CloudCredentials.init failed: ${JSON.stringify(err)}`);
      });

    // V0.6.5.1: bootstrap the unified pack library + selection so the
    // 📦 picker section can render.
    loadHomeIntegration(ctx).then((bundle: HomeIntegrationBundle): void => {
      this.homeIntegration = bundle;
      this.refreshPackPickerState();
    }).catch((err: BusinessError): void => {
      console.error(`ConfigPage: loadHomeIntegration failed: ${JSON.stringify(err)}`);
    });
  }

  /** Mirror selection state into @State so ArkUI re-renders the picker. */
  private refreshPackPickerState(): void {
    this.availablePacks = this.homeIntegration.library.allPacks();
    this.activePackIds = this.homeIntegration.selection.getActiveIds();
    this.pinnedPackIds = this.homeIntegration.selection.pinnedIdsList();
    const limit: number = MAX_ACTIVE_PACKS;
    this.packSyncStatusText = `已激活 ${this.activePackIds.length} / ${limit}`;
    this.packPickerVersion = this.packPickerVersion + 1;
  }

  private async refreshBindingState(): Promise<void> {
    const snap: CloudCredentialsSnapshot = await this.cloudCreds.load();
    this.bindingPresent = snap.isBound();
    this.bindingNickname = snap.nickname.length > 0 ? snap.nickname : '宝贝';
    this.bindingDeviceIdSource = snap.deviceIdSource;
  }

  onPageShow(): void {
    // Re-sync draft fields owned by other pages so reading them on
    // this page (row labels) reflects the latest value. ConfigPage
    // never mutates these fields itself.
    //   - parentPin: owned by ParentPinSetupPage (V0.3.9)
    const stored: GameConfig | undefined =
      AppStorage.get<GameConfig>(GAME_CONFIG_STORAGE_KEY);
    if (stored !== undefined) {
      this.draft.parentPin = stored.parentPin;
      this.forceRerender();
    }
    // V0.6.2: refresh binding state in case ScanBindingPage / BoundDeviceInfoPage
    // changed it.
    this.refreshBindingState().catch((err: BusinessError): void => {
      console.error(`ConfigPage.onPageShow: refreshBindingState failed: ${JSON.stringify(err)}`);
    });
  }

  private forceRerender(): void {
    this.draft = cloneGameConfig(this.draft);
  }

  private async refreshSyncStatus(): Promise<void> {
    const rec: WordPackCacheRecord | undefined = await this.wordPackCache.readRecord();
    if (rec === undefined) {
      this.syncStatusText = '尚未同步 (使用内置词库)';
      return;
    }
    this.syncStatusText =
      `已缓存 schema v${rec.schemaVersion} · 同步时间 ${ConfigPage.formatLocal(rec.fetchedAt)}`;
  }

  private static formatLocal(iso: string): string {
    if (iso.length === 0) {
      return '—';
    }
    const parsed: number = Date.parse(iso);
    if (!Number.isFinite(parsed)) {
      return iso;
    }
    const d: Date = new Date(parsed);
    const yyyy: number = d.getFullYear();
    const mm: string = String(d.getMonth() + 1).padStart(2, '0');
    const dd: string = String(d.getDate()).padStart(2, '0');
    const hh: string = String(d.getHours()).padStart(2, '0');
    const min: string = String(d.getMinutes()).padStart(2, '0');
    return `${yyyy}-${mm}-${dd} ${hh}:${min}`;
  }

  private onSyncTap(): void {
    if (this.syncBusy) {
      return;
    }
    this.syncBusy = true;
    const remote: RemoteWordPackService = new RemoteWordPackService();
    const svc: WordPackSyncService = new WordPackSyncService(remote, this.wordPackCache);
    svc.syncOnce().then((out: SyncOutcome): void => {
      this.showSyncToast(ConfigPage.toastForOutcome(out));
      this.refreshSyncStatus().catch((err: BusinessError): void => {
        console.error(`ConfigPage.refreshSyncStatus failed: ${JSON.stringify(err)}`);
      });
    }).catch((err: BusinessError): void => {
      console.error(`ConfigPage.onSyncTap failed: ${JSON.stringify(err)}`);
      this.showSyncToast('同步失败 (内部错误)');
    }).then((): void => {
      this.syncBusy = false;
      this.forceRerender();
    });
  }

  private showSyncToast(text: string): void {
    this.syncToastText = text;
    if (this.syncToastTimer >= 0) {
      clearTimeout(this.syncToastTimer);
    }
    this.syncToastTimer = setTimeout((): void => {
      this.syncToastText = '';
      this.syncToastTimer = -1;
      this.forceRerender();
    }, 2400);
  }

  private static toastForOutcome(out: SyncOutcome): string {
    if (out.status === SyncStatus.Updated) {
      return `已同步至 v${out.cachedVersion}`;
    }
    if (out.status === SyncStatus.UpToDate) {
      return out.cachedVersion > 0 ? `已是最新 v${out.cachedVersion}` : '已是最新';
    }
    if (out.status === SyncStatus.HttpError) {
      return `同步失败 (HTTP ${out.httpStatus})`;
    }
    if (out.status === SyncStatus.RejectedTooSmall) {
      return '同步失败 (服务端词包过小)';
    }
    return '同步失败 (网络错误)';
  }

  @Builder
  private syncRow() {
    Column({ space: 8 }) {
      Row() {
        Text('词库同步').fontSize(18).width(120);
        Button(this.syncBusy ? '同步中…' : '同步词包')
          .id('ConfigSyncButton')
          .width(140).height(40)
          .fontSize(16)
          .backgroundColor(this.syncBusy ? '#F0F0F0' : '#EAF2F8')
          .fontColor(this.syncBusy ? '#999999' : '#457B9D')
          .enabled(!this.syncBusy)
          .onClick((): void => this.onSyncTap());
      }
      .alignItems(VerticalAlign.Center);
      Text(this.syncStatusText)
        .id('ConfigSyncStatus')
        .fontSize(13)
        .fontColor('#666666');
      if (this.syncToastText.length > 0) {
        Text(this.syncToastText)
          .id('ConfigSyncToast')
          .fontSize(13)
          .fontColor('#1D3557')
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .backgroundColor('#FFF4D0')
          .borderRadius(6);
      }
    }
    .alignItems(HorizontalAlign.Start)
    .margin({ bottom: 16 });
  }

  @Builder
  private parentAccountRow() {
    Column() {
      Row() {
        Text('家长账户').fontSize(18).width(120);
        if (this.bindingPresent) {
          Button(`孩子档案：${this.bindingNickname}`)
            .id('ConfigBoundDeviceInfoButton')
            .width(220).height(40).fontSize(15)
            .backgroundColor('#E0F2FE').fontColor('#0369A1')
            .borderWidth(2).borderColor('#0EA5E9')
            .onClick((): void => this.openBoundDeviceInfo());
        } else {
          Button('绑定家长账号')
            .id('ConfigBindParentButton')
            .width(220).height(40).fontSize(15)
            .backgroundColor('#FFF4D0').fontColor('#B8860B')
            .borderWidth(2).borderColor('#FFB400')
            .onClick((): void => this.openScanBinding());
        }
      }
      .alignItems(VerticalAlign.Center);
      if (this.bindingDeviceIdSource === 'preferences_fallback') {
        Text('⚠ 此设备未启用 AssetStoreKit，重装后将丢失家长绑定。')
          .id('ConfigPersistentIdWarning')
          .fontSize(12).fontColor('#B45309').margin({ top: 4 });
      }
      if (this.bindingPresent) {
        Row() {
          Text(' ').width(120);
          Button(this.unbindBusy ? '解除中…' : '解除设备绑定')
            .id('ConfigUnbindBindingButton')
            .width(220).height(40).fontSize(15)
            .backgroundColor(this.unbindBusy ? '#E5E7EB' : '#FEE2E2')
            .fontColor(this.unbindBusy ? '#6B7280' : '#B91C1C')
            .borderWidth(2).borderColor(this.unbindBusy ? '#9CA3AF' : '#FCA5A5')
            .enabled(!this.unbindBusy)
            .onClick((): void => this.onUnbindTap());
        }
        .alignItems(VerticalAlign.Center).margin({ top: 8 });
      }
      // Toast lives OUTSIDE the bindingPresent gate so the success
      // message ("已解除设备绑定") remains visible after `runUnbind`
      // refreshes the state and `bindingPresent` flips to false. The
      // empty-state error message ("请先在「家长密码」中设置 6 位 PIN")
      // also needs to surface even when there is no binding.
      if (this.unbindToastText.length > 0) {
        Text(this.unbindToastText)
          .id('ConfigUnbindToast')
          .fontSize(12).fontColor('#B91C1C').margin({ top: 4 });
      }
    }
    .width('100%').alignItems(HorizontalAlign.Center).margin({ bottom: 16 });
  }

  private openScanBinding(): void {
    this.getUIContext().getRouter().pushUrl({ url: 'pages/ScanBindingPage' }).catch((err: BusinessError): void => {
      console.error(`ConfigPage.openScanBinding: ${JSON.stringify(err)}`);
    });
  }

  private openBoundDeviceInfo(): void {
    this.getUIContext().getRouter().pushUrl({ url: 'pages/BoundDeviceInfoPage' }).catch((err: BusinessError): void => {
      console.error(`ConfigPage.openBoundDeviceInfo: ${JSON.stringify(err)}`);
    });
  }

  /**
   * V0.6.7 — opens a parent-PIN gate, then calls /api/v1/child/unbind on
   * confirm. The PIN dialog reuses the existing component so the UX
   * mirrors `进入家长后台` (open parent admin).
   */
  private onUnbindTap(): void {
    if (this.unbindBusy) {
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
          this.runUnbind();
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
    ctrl.open();
  }

  private async runUnbind(): Promise<void> {
    if (this.unbindBusy) {
      return;
    }
    this.getUIContext().animateTo({ duration: 0 }, (): void => {
      this.unbindBusy = true;
    });
    const adapter: RealParentFetchAdapter = new RealParentFetchAdapter();
    const baseUrl: string = effectiveServerBaseUrl();
    const client: DeviceUnbindClient = new DeviceUnbindClient(this.cloudCreds, adapter, baseUrl);
    try {
      const out: DeviceUnbindOutcome = await client.unbind();
      this.getUIContext().animateTo({ duration: 0 }, (): void => {
        this.unbindBusy = false;
      });
      if (out.ok) {
        this.showUnbindToast('已解除设备绑定');
        const recorder: LearningRecorder = getLearningRecorder();
        recorder.attachCloudSync(undefined);
        this.refreshBindingState().catch((err: BusinessError): void => {
          console.error(`ConfigPage.runUnbind.refresh failed: ${JSON.stringify(err)}`);
        });
      } else {
        this.showUnbindToast(`解除失败 (HTTP ${out.status})`);
      }
    } catch (err) {
      console.error(`ConfigPage.runUnbind failed: ${JSON.stringify(err)}`);
      this.getUIContext().animateTo({ duration: 0 }, (): void => {
        this.unbindBusy = false;
      });
      this.showUnbindToast('解除失败 (网络错误)');
    }
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

  @Builder
  private cloudSyncRow() {
    if (this.bindingPresent) {
      Column() {
        Row() {
          Text('学习记录').fontSize(18).width(120);
          Button(this.cloudSyncBusy ? '同步中…' : '立即同步学习记录')
            .id('ConfigCloudSyncButton')
            .width(220).height(40).fontSize(15)
            .backgroundColor(this.cloudSyncBusy ? '#E5E7EB' : '#E0F2FE')
            .fontColor(this.cloudSyncBusy ? '#6B7280' : '#0369A1')
            .borderWidth(2).borderColor(this.cloudSyncBusy ? '#9CA3AF' : '#0EA5E9')
            .enabled(!this.cloudSyncBusy)
            .onClick((): void => this.onCloudSyncTap());
        }
        .alignItems(VerticalAlign.Center);
        if (this.cloudSyncStatusText.length > 0) {
          Text(this.cloudSyncStatusText)
            .id('ConfigCloudSyncStatus')
            .fontSize(12).fontColor('#6B7280').margin({ top: 4 });
        }
        if (this.cloudSyncToastText.length > 0) {
          Text(this.cloudSyncToastText)
            .id('ConfigCloudSyncToast')
            .fontSize(12).fontColor('#0369A1').margin({ top: 4 });
        }
      }
      .width('100%').alignItems(HorizontalAlign.Center).margin({ bottom: 16 });
    }
  }

  private onCloudSyncTap(): void {
    if (this.cloudSyncBusy) {
      return;
    }
    const recorder: LearningRecorder = getLearningRecorder();
    const svc: CloudSyncLike | undefined = recorder.getCloudSync();
    if (svc === undefined) {
      this.applyCloudSyncToast('尚未启用云端同步');
      return;
    }
    this.beginCloudSync();
    svc.syncOnce().then((out: CloudSyncResult): void => {
      this.applyCloudSyncOutcome(
        ConfigPage.formatCloudSyncStatus(out),
        ConfigPage.formatCloudSyncToast(out),
      );
    }).catch((err: BusinessError): void => {
      console.error(`ConfigPage.onCloudSyncTap failed: ${JSON.stringify(err)}`);
      this.applyCloudSyncToast('同步失败 (内部错误)');
    }).then((): void => {
      this.endCloudSync();
    });
  }

  private beginCloudSync(): void {
    this.cloudSyncBusy = true;
    this.cloudSyncToastText = '';
  }

  private endCloudSync(): void {
    this.cloudSyncBusy = false;
    this.forceRerender();
  }

  private applyCloudSyncToast(text: string): void {
    this.cloudSyncToastText = text;
  }

  private applyCloudSyncOutcome(statusText: string, toastText: string): void {
    this.cloudSyncStatusText = statusText;
    this.cloudSyncToastText = toastText;
  }

  private static formatCloudSyncStatus(out: CloudSyncResult): string {
    if (out.serverNowMs <= 0) {
      return '上次同步时间未知';
    }
    return `上次成功同步 ${ConfigPage.formatLocalMs(out.serverNowMs)}`;
  }

  private static formatCloudSyncToast(out: CloudSyncResult): string {
    switch (out.status) {
      case 'unbound': return '未绑定家长账号，请先在“家长账户”中绑定';
      case 'no_changes': return '没有新的学习记录';
      case 'pushed': return `已上传 ${out.pushed} 条学习记录`;
      case 'pulled': return `已合并 ${out.pulled} 条服务器记录`;
      case 'pushed_and_pulled':
        return `已上传 ${out.pushed} 条 / 合并 ${out.pulled} 条服务器记录`;
      case 'network_error': return '同步失败：网络异常，请稍后重试';
      default: return '同步完成';
    }
  }

  private static formatLocalMs(ms: number): string {
    const d: Date = new Date(ms);
    const yyyy: number = d.getFullYear();
    const mm: string = String(d.getMonth() + 1).padStart(2, '0');
    const dd: string = String(d.getDate()).padStart(2, '0');
    const hh: string = String(d.getHours()).padStart(2, '0');
    const mn: string = String(d.getMinutes()).padStart(2, '0');
    return `${yyyy}-${mm}-${dd} ${hh}:${mn}`;
  }

  @Builder
  private adminRow() {
    Row() {
      Text('家长').fontSize(18).width(120);
      Button('家长管理后台')
        .id('ConfigParentAdminButton')
        .width(220).height(40)
        .fontSize(15)
        .backgroundColor('#FFF4D0')
        .fontColor('#B8860B')
        .borderWidth(2)
        .borderColor('#FFB400')
        .onClick((): void => this.openParentAdmin());
    }
    .margin({ bottom: 16 })
    .alignItems(VerticalAlign.Center);
  }

  private decPlayerHp(): void {
    if (this.draft.playerMaxHp > HP_MIN) {
      this.draft.playerMaxHp -= 1;
      this.forceRerender();
    }
  }
  private incPlayerHp(): void {
    if (this.draft.playerMaxHp < HP_MAX) {
      this.draft.playerMaxHp += 1;
      this.forceRerender();
    }
  }
  private decMonsterHp(): void {
    if (this.draft.monsterMaxHp > HP_MIN) {
      this.draft.monsterMaxHp -= 1;
      this.forceRerender();
    }
  }
  private incMonsterHp(): void {
    if (this.draft.monsterMaxHp < HP_MAX) {
      this.draft.monsterMaxHp += 1;
      this.forceRerender();
    }
  }
  private decMonstersTotal(): void {
    if (this.draft.monstersTotal > MONSTER_COUNT_MIN) {
      this.draft.monstersTotal -= 1;
      this.forceRerender();
    }
  }
  private incMonstersTotal(): void {
    if (this.draft.monstersTotal < MONSTER_COUNT_MAX) {
      this.draft.monstersTotal += 1;
      this.forceRerender();
    }
  }

  private selectTimer(seconds: number): void {
    if (this.draft.startingSeconds === seconds) {
      return;
    }
    this.draft.startingSeconds = seconds;
    this.forceRerender();
  }

  private toggleAutoSpeak(): void {
    this.draft.autoSpeak = !this.draft.autoSpeak;
    this.forceRerender();
  }

  private openParentPinSetup(): void {
    this.getUIContext().getRouter().pushUrl({ url: 'pages/ParentPinSetupPage' }).catch((err: BusinessError): void => {
      console.error(`ConfigPage: pushUrl ParentPinSetupPage failed: ${JSON.stringify(err)}`);
    });
  }

  private parentPinIsConfigured(): boolean {
    const stored: GameConfig | undefined =
      AppStorage.get<GameConfig>(GAME_CONFIG_STORAGE_KEY);
    return stored !== undefined && stored.parentPin.length === 6;
  }

  /**
   * V0.5.8: open the parent admin backend after a successful parent
   * PIN verification. Server-side auth was removed in V0.5.8 (returns
   * in V0.6 as per-family JWT); the parent PIN remains the local
   * "keep kids out" gate.
   */
  private openParentAdmin(): void {
    const stored: GameConfig | undefined =
      AppStorage.get<GameConfig>(GAME_CONFIG_STORAGE_KEY);
    const expected: string =
      stored !== undefined ? stored.parentPin : '';
    if (expected.length !== 6) {
      // No parent PIN set — nudge the operator to configure one first.
      this.getUIContext().getRouter().pushUrl({ url: 'pages/ParentPinSetupPage' }).catch((err: BusinessError): void => {
        console.error(`ConfigPage: pushUrl ParentPinSetupPage failed: ${JSON.stringify(err)}`);
      });
      return;
    }
    // Capture the router reference outside the dialog callback so the
    // closure does not depend on `this` still being valid when the
    // CustomDialog dispatches onConfirm.
    const adminRouter = this.getUIContext().getRouter();
    let ctrl: CustomDialogController | null = null;
    ctrl = new CustomDialogController({
      builder: ParentPinDialog({
        expectedPin: expected,
        title: '进入后台需要家长密码',
        onConfirm: (): void => {
          if (ctrl !== null) {
            ctrl.close();
          }
          adminRouter.pushUrl({ url: 'pages/ParentAdminPage' }).catch((err: BusinessError): void => {
            console.error(`ConfigPage: pushUrl ParentAdminPage failed: ${JSON.stringify(err)}`);
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
    this.adminPinDialog = ctrl;
    ctrl.open();
  }

  private onSave(): void {
    // V0.6.6: ConfigPage no longer owns the word pool, so there is no
    // pool-size validation. The pack picker (📦 我的词包) enforces
    // its own min/max active-set rules; on save we just persist the
    // battle knobs.
    const storedNow: GameConfig | undefined =
      AppStorage.get<GameConfig>(GAME_CONFIG_STORAGE_KEY);
    const merged: GameConfig =
      cloneGameConfig(storedNow !== undefined ? storedNow : new GameConfig());
    merged.playerMaxHp = this.draft.playerMaxHp;
    merged.monsterMaxHp = this.draft.monsterMaxHp;
    merged.monstersTotal = this.draft.monstersTotal;
    merged.startingSeconds = this.draft.startingSeconds;
    merged.autoSpeak = this.draft.autoSpeak;

    AppStorage.set<GameConfig>(GAME_CONFIG_STORAGE_KEY, merged);
    persistGameConfigBestEffort(this.getUIContext().getHostContext() as common.UIAbilityContext, merged);
    this.getUIContext().getRouter().back();
  }

  private onCancel(): void {
    this.getUIContext().getRouter().back();
  }

  @Builder
  private stepperRow(label: string, valueId: string, value: number,
                     decId: string, decAction: () => void, decEnabled: boolean,
                     incId: string, incAction: () => void, incEnabled: boolean) {
    Row() {
      Text(label).fontSize(18).width(120);
      Button('-')
        .id(decId)
        .width(44).height(44)
        .fontSize(24)
        .enabled(decEnabled)
        .opacity(decEnabled ? 1.0 : 0.4)
        .onClick((): void => decAction());
      Text(`${value}`)
        .id(valueId)
        .fontSize(22)
        .width(48)
        .textAlign(TextAlign.Center);
      Button('+')
        .id(incId)
        .width(44).height(44)
        .fontSize(24)
        .enabled(incEnabled)
        .opacity(incEnabled ? 1.0 : 0.4)
        .onClick((): void => incAction());
    }
    .margin({ bottom: 12 })
    .alignItems(VerticalAlign.Center);
  }

  private timerLabel(seconds: number): string {
    if (seconds < 60) {
      return `${seconds}s`;
    }
    return `${seconds / 60}m`;
  }

  private timerChipId(seconds: number): string {
    return `ConfigTimer${seconds}s`;
  }

  /**
   * Prefix the active timer chip with "✓" so UI tests can read a chip's
   * selection state via getText() without relying on Button.selected()
   * (not available on ButtonAttribute) or on colour inspection.
   */
  private timerChipLabel(seconds: number): string {
    const base: string = this.timerLabel(seconds);
    return this.draft.startingSeconds === seconds ? `✓${base}` : base;
  }

  @Builder
  private timerRow() {
    Row() {
      Text('倒计时').fontSize(18).width(120);
      Row({ space: 8 }) {
        ForEach(TIMER_CHOICES, (sec: number) => {
          Button(this.timerChipLabel(sec))
            .id(this.timerChipId(sec))
            .width(64).height(40)
            .fontSize(16)
            .backgroundColor(this.draft.startingSeconds === sec ? '#FFB400' : '#EAF2F8')
            .fontColor(this.draft.startingSeconds === sec ? '#FFFFFF' : '#457B9D')
            .onClick((): void => this.selectTimer(sec));
        }, (sec: number) => `${sec}`);
      };
    }
    .margin({ bottom: 12 })
    .alignItems(VerticalAlign.Center);
  }

  @Builder
  private autoSpeakRow() {
    Row() {
      Text('发音播放').fontSize(18).width(120);
      Button(this.draft.autoSpeak ? '✓ 自动朗读' : '自动朗读')
        .id('ConfigAutoSpeakToggle')
        .width(140).height(40)
        .fontSize(16)
        .backgroundColor(this.draft.autoSpeak ? '#FFF4D0' : '#F0F0F0')
        .fontColor(this.draft.autoSpeak ? '#B8860B' : '#666666')
        .borderWidth(this.draft.autoSpeak ? 2 : 0)
        .borderColor('#FFB400')
        .onClick((): void => this.toggleAutoSpeak());
    }
    .margin({ bottom: 12 })
    .alignItems(VerticalAlign.Center);
  }

  @Builder
  private parentPinRow() {
    Row() {
      Text('家长密码').fontSize(18).width(120);
      Button(this.draft.parentPin.length === 6 ? '修改 (•••••• 已设置)' : '设置')
        .id('ConfigParentPinButton')
        .width(220).height(40)
        .fontSize(15)
        .backgroundColor(this.draft.parentPin.length === 6 ? '#FFF4D0' : '#EAF2F8')
        .fontColor(this.draft.parentPin.length === 6 ? '#B8860B' : '#457B9D')
        .borderWidth(this.draft.parentPin.length === 6 ? 2 : 0)
        .borderColor('#FFB400')
        .onClick((): void => this.openParentPinSetup());
    }
    .margin({ bottom: 12 })
    .alignItems(VerticalAlign.Center);
  }

  // V0.6.5.1 — pack picker handlers and renderer.

  /** Toggle a pack in/out of the active selection. Enforces the 5-pack cap. */
  private async togglePackActive(packId: string): Promise<void> {
    const idx: number = this.activePackIds.indexOf(packId);
    let next: string[];
    if (idx >= 0) {
      next = this.activePackIds.slice();
      next.splice(idx, 1);
    } else {
      if (this.activePackIds.length >= MAX_ACTIVE_PACKS) {
        this.showPackToast(`最多可激活 ${MAX_ACTIVE_PACKS} 个词包，请先取消其他词包`);
        return;
      }
      next = this.activePackIds.slice();
      next.push(packId);
    }
    try {
      await this.homeIntegration.selection.setActiveIds(next);
      this.refreshPackPickerState();
    } catch (err) {
      console.error(`ConfigPage.togglePackActive failed: ${JSON.stringify(err as BusinessError)}`);
      this.showPackToast('保存失败，请重试');
    }
  }

  private async togglePackPin(packId: string): Promise<void> {
    if (this.activePackIds.indexOf(packId) < 0) {
      this.showPackToast('只有已激活的词包才能 📌 固定');
      return;
    }
    try {
      await this.homeIntegration.selection.togglePin(packId);
      this.refreshPackPickerState();
    } catch (err) {
      console.error(`ConfigPage.togglePackPin failed: ${JSON.stringify(err as BusinessError)}`);
      this.showPackToast('保存失败，请重试');
    }
  }

  /**
   * Sync global + family packs, then refresh the picker. Best-effort:
   * each service's `ensureLatest` returns a structured outcome and
   * never throws. Family-pack sync only fires when the device is
   * bound — otherwise the row is skipped silently.
   */
  private async onPackSyncTap(): Promise<void> {
    if (this.packSyncBusy) return;
    this.packSyncBusy = true;
    this.packSyncToastText = '';
    const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const baseUrl: string = effectiveServerBaseUrl();
    const adapter: PackNetworkFetchAdapter = new PackNetworkFetchAdapter();
    const gps: GlobalPackService = new GlobalPackService(adapter, baseUrl);
    const fps: FamilyPackService = new FamilyPackService(adapter, baseUrl);
    let globalsUpdated: boolean = false;
    let familyUpdated: boolean = false;
    let familyAttempted: boolean = false;
    try {
      await gps.init(ctx);
      const gOut: GlobalPackEnsureResult = await gps.ensureLatest();
      globalsUpdated = gOut.status === 'updated';
    } catch (err) {
      console.error(`ConfigPage.onPackSyncTap (global) failed: ${JSON.stringify(err as BusinessError)}`);
    }
    try {
      const snap: CloudCredentialsSnapshot = await this.cloudCreds.load();
      if (snap.deviceToken.length > 0) {
        familyAttempted = true;
        await fps.init(ctx);
        const fOut: FamilyPackEnsureResult = await fps.ensureLatest(snap.deviceToken);
        familyUpdated = fOut.status === 'updated' || fOut.status === 'cleared';
      }
    } catch (err) {
      console.error(`ConfigPage.onPackSyncTap (family) failed: ${JSON.stringify(err as BusinessError)}`);
    }

    // Re-load the merged library so newly fetched packs appear in the
    // picker without a full page navigation. Selection is preserved.
    try {
      this.homeIntegration = await loadHomeIntegration(ctx);
      this.refreshPackPickerState();
    } catch (err) {
      console.error(`ConfigPage.onPackSyncTap reload failed: ${JSON.stringify(err as BusinessError)}`);
    }
    this.packSyncBusy = false;
    this.showPackToast(ConfigPage.formatPackSyncToast(globalsUpdated, familyUpdated, familyAttempted));
    this.forceRerender();
  }

  private static formatPackSyncToast(g: boolean, f: boolean, fAttempted: boolean): string {
    if (g && f) return '✅ 已同步全局 + 家庭词包';
    if (g && !fAttempted) return '✅ 已同步全局词包';
    if (g && fAttempted && !f) return '✅ 已同步全局词包 (家庭无更新)';
    if (!g && f) return '✅ 已同步家庭词包';
    if (!g && !f && fAttempted) return '已是最新';
    return '已是最新 (仅全局可同步，未绑定家长账号)';
  }

  private showPackToast(text: string): void {
    this.packSyncToastText = text;
    if (this.packPickerToastTimer >= 0) {
      clearTimeout(this.packPickerToastTimer);
    }
    this.packPickerToastTimer = setTimeout((): void => {
      this.packSyncToastText = '';
      this.packPickerToastTimer = -1;
      this.forceRerender();
    }, 2400);
  }

  /** Look up a pack id's display label, prefer Chinese override. */
  private packPickerLabel(p: Pack): string {
    if (p.labelZh.length > 0) return p.labelZh;
    if (p.name.length > 0) return p.name;
    return p.id;
  }

  private packSourceTag(p: Pack): string {
    if (p.source === 'builtin') return '内置';
    if (p.source === 'global') return '官方';
    return '家庭';
  }

  private packSourceColor(p: Pack): string {
    if (p.source === 'builtin') return '#9CA3AF';
    if (p.source === 'global') return '#0EA5E9';
    return '#10B981';
  }

  private packCheckedColor(active: boolean): string {
    return active ? '#FFB400' : '#9CA3AF';
  }

  @Builder
  private packPickerSection() {
    Column({ space: 8 }) {
      Row() {
        Text('📦 我的词包').fontSize(18).width(120);
        Text(this.packSyncStatusText)
          .id('ConfigPackPickerStatus')
          .fontSize(13).fontColor('#6B7280');
        Blank().layoutWeight(1);
        Button(this.packSyncBusy ? '同步中…' : '🔄 同步词包')
          .id('ConfigPackSyncButton')
          .height(36).fontSize(14)
          .padding({ left: 12, right: 12 })
          .backgroundColor(this.packSyncBusy ? '#F0F0F0' : '#EAF2F8')
          .fontColor(this.packSyncBusy ? '#999999' : '#457B9D')
          .enabled(!this.packSyncBusy)
          .onClick((): void => {
            this.onPackSyncTap().catch((err: BusinessError): void => {
              console.error(`ConfigPage.onPackSyncTap promise failed: ${JSON.stringify(err)}`);
            });
          });
      }
      .width('100%')
      .alignItems(VerticalAlign.Center);

      if (this.availablePacks.length === 0) {
        Text(this.packPickerVersion >= 0 ? '正在加载词包…' : '')
          .id('ConfigPackPickerLoading')
          .fontSize(13).fontColor('#9CA3AF');
      } else {
        ForEach(this.availablePacks, (p: Pack): void => {
          this.packRow(p);
        }, (p: Pack): string => p.id);
      }

      if (this.packSyncToastText.length > 0) {
        Text(this.packSyncToastText)
          .id('ConfigPackSyncToast')
          .fontSize(13).fontColor('#1D3557')
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .backgroundColor('#FFF4D0')
          .borderRadius(6);
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ top: 12, bottom: 12 })
    .margin({ bottom: 16 })
    .borderRadius(12)
    .backgroundColor('#FAFAFA');
  }

  @Builder
  private packRow(p: Pack) {
    Row({ space: 8 }) {
      // Active checkbox — tappable text glyph. Reuses the chip-style
      // visual language so the row stays compact on narrow phones.
      Button(this.activePackIds.indexOf(p.id) >= 0 ? '✓' : ' ')
        .id(`ConfigPackToggle_${p.id}`)
        .width(36).height(36).fontSize(18)
        .backgroundColor(this.packCheckedColor(this.activePackIds.indexOf(p.id) >= 0))
        .fontColor('#FFFFFF')
        .borderRadius(8)
        .onClick((): void => {
          this.togglePackActive(p.id).catch((err: BusinessError): void => {
            console.error(`ConfigPage.togglePackActive promise failed: ${JSON.stringify(err)}`);
          });
        });

      Text(this.packPickerLabel(p))
        .id(`ConfigPackLabel_${p.id}`)
        .fontSize(15).fontColor('#1F2937')
        .layoutWeight(1);

      Text(this.packSourceTag(p))
        .id(`ConfigPackSource_${p.id}`)
        .fontSize(11).fontColor('#FFFFFF')
        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
        .backgroundColor(this.packSourceColor(p))
        .borderRadius(4);

      // Pin toggle — only meaningful when pack is active. A pinned
      // pack is exempt from the perfect-rotation auto-swap.
      Button(this.pinnedPackIds.indexOf(p.id) >= 0 ? '📌' : '·')
        .id(`ConfigPackPin_${p.id}`)
        .width(36).height(36).fontSize(16)
        .backgroundColor(this.pinnedPackIds.indexOf(p.id) >= 0 ? '#FEF3C7' : '#F3F4F6')
        .fontColor(this.pinnedPackIds.indexOf(p.id) >= 0 ? '#B45309' : '#9CA3AF')
        .borderRadius(8)
        .onClick((): void => {
          this.togglePackPin(p.id).catch((err: BusinessError): void => {
            console.error(`ConfigPage.togglePackPin promise failed: ${JSON.stringify(err)}`);
          });
        });
    }
    .width('100%')
    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
    .alignItems(VerticalAlign.Center);
  }

  build(): void {
    // Scroll wrapper: the form's natural height exceeds the landscape
    // viewport once ArkUI applies its minimum-tap-target sizing to the
    // stepper/timer/category buttons. Without Scroll the Save/Cancel
    // row ends up past the Column's bottom clip boundary and swallows
    // touch events — see the regression hunted down in Task 7.
    Scroll() {
      Column() {
        Text('游戏设置')
          .id('ConfigTitle')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .margin({ bottom: 12 });

        this.stepperRow(
          '玩家血量', 'ConfigPlayerHpValue', this.draft.playerMaxHp,
          'ConfigPlayerHpDec', (): void => this.decPlayerHp(), this.draft.playerMaxHp > HP_MIN,
          'ConfigPlayerHpInc', (): void => this.incPlayerHp(), this.draft.playerMaxHp < HP_MAX);
        this.stepperRow(
          '怪物血量', 'ConfigMonsterHpValue', this.draft.monsterMaxHp,
          'ConfigMonsterHpDec', (): void => this.decMonsterHp(), this.draft.monsterMaxHp > HP_MIN,
          'ConfigMonsterHpInc', (): void => this.incMonsterHp(), this.draft.monsterMaxHp < HP_MAX);
        this.stepperRow(
          '怪物数量', 'ConfigMonstersTotalValue', this.draft.monstersTotal,
          'ConfigMonstersTotalDec', (): void => this.decMonstersTotal(), this.draft.monstersTotal > MONSTER_COUNT_MIN,
          'ConfigMonstersTotalInc', (): void => this.incMonstersTotal(), this.draft.monstersTotal < MONSTER_COUNT_MAX);

        this.timerRow();
        this.autoSpeakRow();
        this.packPickerSection();
        this.parentPinRow();
        this.parentAccountRow();
        this.cloudSyncRow();
        this.syncRow();
        this.adminRow();

        Row({ space: 16 }) {
          Button('取消')
            .id('ConfigCancelButton')
            .width(160).height(48)
            .backgroundColor('#BDBDBD')
            .onClick((): void => this.onCancel());
          Button('保存')
            .id('ConfigSaveButton')
            .width(160).height(48)
            .backgroundColor('#2ECC71')
            .onClick((): void => this.onSave());
        }
        .margin({ top: 8, bottom: 24 });
      }
      .width('100%')
      .padding({ top: 16, bottom: 24, left: 40, right: 40 })
      .alignItems(HorizontalAlign.Center);
    }
    .width('100%')
    .height('100%')
    .scrollable(ScrollDirection.Vertical)
    .backgroundColor('#FFFFFF')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM,
      SafeAreaEdge.START, SafeAreaEdge.END]);
  }
}
