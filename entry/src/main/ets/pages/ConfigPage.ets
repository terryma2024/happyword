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
  KNOWN_CATEGORIES,
  CUSTOM_CATEGORY_KEY,
  MIN_POOL_SIZE,
  cloneGameConfig,
  computeFinalPool
} from '../models/GameConfig';
import { WordRepository } from '../services/WordRepository';
import { WordPackBootstrapper, BootstrapDeps } from '../services/WordPackBootstrapper';
import { WordEntry } from '../models/WordEntry';
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
import { effectiveServerBaseUrl } from '../services/RemoteWordPackConfig';
import { getLearningRecorder, LearningRecorder } from '../services/LearningRecorder';
import { CloudSyncLike, CloudSyncResult } from '../services/CloudSyncTypes';
import { router } from '@kit.ArkUI';

/**
 * ConfigPage exposes five battle knobs plus a custom-words category.
 * All non-custom edits happen on a local @State draft and are only
 * written to AppStorage when the user taps 保存 AND the resulting
 * pool size ≥ MIN_POOL_SIZE. 取消 returns to HomePage without
 * touching stored state. The custom-words raw text is owned by
 * CustomWordsPage (spec §3.4 / §4.5).
 */
@Entry
@Component
struct ConfigPage {
  @State private draft: GameConfig = new GameConfig();
  @State private showValidationHint: boolean = false;
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
  private builtinEntries: WordEntry[] = [];
  private adminPinDialog: CustomDialogController | null = null;

  aboutToAppear(): void {
    const stored: GameConfig | undefined =
      AppStorage.get<GameConfig>(GAME_CONFIG_STORAGE_KEY);
    this.draft = cloneGameConfig(stored !== undefined ? stored : new GameConfig());

    // Load built-in entries for Save-time validation. Form renders
    // without waiting — validation only runs on the Save click.
    const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    WordPackBootstrapper.forContext(ctx).then(async (deps: BootstrapDeps): Promise<void> => {
      const repo: WordRepository = await new WordPackBootstrapper().bootstrap(deps);
      this.builtinEntries = repo.all();
    }).catch((err: BusinessError): void => {
      console.error(`ConfigPage: bootstrap failed: ${JSON.stringify(err)}`);
    });

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
  }

  private async refreshBindingState(): Promise<void> {
    const snap: CloudCredentialsSnapshot = await this.cloudCreds.load();
    this.bindingPresent = snap.isBound();
    this.bindingNickname = snap.nickname.length > 0 ? snap.nickname : '宝贝';
    this.bindingDeviceIdSource = snap.deviceIdSource;
  }

  onPageShow(): void {
    // Re-sync draft fields owned by other pages so reading them on
    // this page (validation / row labels) reflects the latest value.
    // ConfigPage never mutates these fields itself.
    //   - customWordsRaw: owned by CustomWordsPage
    //   - parentPin: owned by ParentPinSetupPage (V0.3.9)
    const stored: GameConfig | undefined =
      AppStorage.get<GameConfig>(GAME_CONFIG_STORAGE_KEY);
    if (stored !== undefined) {
      this.draft.customWordsRaw = stored.customWordsRaw;
      this.draft.parentPin = stored.parentPin;
      this.showValidationHint = false;
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
    .width('100%').alignItems(HorizontalAlign.Start).margin({ bottom: 16 });
  }

  private openScanBinding(): void {
    router.pushUrl({ url: 'pages/ScanBindingPage' }).catch((err: BusinessError): void => {
      console.error(`ConfigPage.openScanBinding: ${JSON.stringify(err)}`);
    });
  }

  private openBoundDeviceInfo(): void {
    router.pushUrl({ url: 'pages/BoundDeviceInfoPage' }).catch((err: BusinessError): void => {
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

  private runUnbind(): void {
    this.unbindBusy = true;
    const adapter: RealParentFetchAdapter = new RealParentFetchAdapter();
    const baseUrl: string = effectiveServerBaseUrl();
    const client: DeviceUnbindClient = new DeviceUnbindClient(this.cloudCreds, adapter, baseUrl);
    client.unbind().then((out: DeviceUnbindOutcome): void => {
      this.unbindBusy = false;
      if (out.ok) {
        this.showUnbindToast('已解除设备绑定');
        // Detach cloud sync / wishlist services that may still hold the
        // old binding so HomePage falls back to local-only mode.
        const recorder: LearningRecorder = getLearningRecorder();
        recorder.attachCloudSync(undefined);
        this.refreshBindingState().catch((err: BusinessError): void => {
          console.error(`ConfigPage.runUnbind.refresh failed: ${JSON.stringify(err)}`);
        });
      } else {
        this.showUnbindToast(`解除失败 (HTTP ${out.status})`);
      }
    }).catch((err: BusinessError): void => {
      console.error(`ConfigPage.runUnbind failed: ${JSON.stringify(err)}`);
      this.unbindBusy = false;
      this.showUnbindToast('解除失败 (网络错误)');
    });
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
      .width('100%').alignItems(HorizontalAlign.Start).margin({ bottom: 16 });
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
      this.showValidationHint = false;
      this.forceRerender();
    }
  }
  private incPlayerHp(): void {
    if (this.draft.playerMaxHp < HP_MAX) {
      this.draft.playerMaxHp += 1;
      this.showValidationHint = false;
      this.forceRerender();
    }
  }
  private decMonsterHp(): void {
    if (this.draft.monsterMaxHp > HP_MIN) {
      this.draft.monsterMaxHp -= 1;
      this.showValidationHint = false;
      this.forceRerender();
    }
  }
  private incMonsterHp(): void {
    if (this.draft.monsterMaxHp < HP_MAX) {
      this.draft.monsterMaxHp += 1;
      this.showValidationHint = false;
      this.forceRerender();
    }
  }
  private decMonstersTotal(): void {
    if (this.draft.monstersTotal > MONSTER_COUNT_MIN) {
      this.draft.monstersTotal -= 1;
      this.showValidationHint = false;
      this.forceRerender();
    }
  }
  private incMonstersTotal(): void {
    if (this.draft.monstersTotal < MONSTER_COUNT_MAX) {
      this.draft.monstersTotal += 1;
      this.showValidationHint = false;
      this.forceRerender();
    }
  }

  private selectTimer(seconds: number): void {
    if (this.draft.startingSeconds === seconds) {
      return;
    }
    this.draft.startingSeconds = seconds;
    this.showValidationHint = false;
    this.forceRerender();
  }

  private toggleAutoSpeak(): void {
    this.draft.autoSpeak = !this.draft.autoSpeak;
    this.showValidationHint = false;
    this.forceRerender();
  }

  private toggleCategory(key: string): void {
    const idx: number = this.draft.enabledCategories.indexOf(key);
    if (idx >= 0) {
      // Silently refuse if this would leave zero categories selected
      // (spec §4.2 — "last-chip tap has no reaction").
      if (this.draft.enabledCategories.length <= 1) {
        return;
      }
      this.draft.enabledCategories.splice(idx, 1);
    } else {
      this.draft.enabledCategories.push(key);
    }
    this.showValidationHint = false;
    this.forceRerender();
  }

  private openCustomWords(): void {
    this.getUIContext().getRouter().pushUrl({ url: 'pages/CustomWordsPage' }).catch((err: BusinessError): void => {
      console.error(`ConfigPage: pushUrl CustomWordsPage failed: ${JSON.stringify(err)}`);
    });
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
    // Read current stored customWordsRaw so validation matches what
    // BattlePage will actually use (spec §5.7).
    const storedNow: GameConfig | undefined =
      AppStorage.get<GameConfig>(GAME_CONFIG_STORAGE_KEY);
    const currentCustomRaw: string =
      storedNow !== undefined ? storedNow.customWordsRaw : '';

    const finalPool: WordEntry[] = computeFinalPool(
      this.builtinEntries, this.draft.enabledCategories, currentCustomRaw);

    if (finalPool.length < MIN_POOL_SIZE) {
      this.showValidationHint = true;
      this.forceRerender();
      return;
    }

    // Merge: keep stored customWordsRaw (owned by CustomWordsPage),
    // overlay draft's stepper/timer/category/autoSpeak edits.
    const merged: GameConfig =
      cloneGameConfig(storedNow !== undefined ? storedNow : new GameConfig());
    merged.playerMaxHp = this.draft.playerMaxHp;
    merged.monsterMaxHp = this.draft.monsterMaxHp;
    merged.monstersTotal = this.draft.monstersTotal;
    merged.startingSeconds = this.draft.startingSeconds;
    merged.enabledCategories = this.draft.enabledCategories.slice();
    merged.autoSpeak = this.draft.autoSpeak;

    AppStorage.set<GameConfig>(GAME_CONFIG_STORAGE_KEY, merged);
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

  /**
   * Prefix active category chip labels with "✓". Same rationale as
   * timerChipLabel: gives tests a reliable way to read selection state.
   */
  private categoryChipLabel(baseLabel: string, key: string): string {
    return this.draft.enabledCategories.indexOf(key) >= 0 ? `✓${baseLabel}` : baseLabel;
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

  private builtinCategoryLabel(key: string): string {
    if (key === 'fruit') return '水果';
    if (key === 'place') return '地点';
    if (key === 'home') return '家居';
    return key;
  }

  private builtinCategoryId(key: string): string {
    if (key === 'fruit') return 'ConfigCategoryFruit';
    if (key === 'place') return 'ConfigCategoryPlace';
    if (key === 'home') return 'ConfigCategoryHome';
    return `ConfigCategory${key}`;
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

  @Builder
  private categoryRow() {
    Row() {
      Text('词库类别').fontSize(18).width(120);
      Row({ space: 8 }) {
        ForEach(KNOWN_CATEGORIES, (key: string) => {
          Button(this.categoryChipLabel(this.builtinCategoryLabel(key), key))
            .id(this.builtinCategoryId(key))
            .width(80).height(40)
            .fontSize(16)
            .backgroundColor(this.draft.enabledCategories.indexOf(key) >= 0 ? '#FFF4D0' : '#F0F0F0')
            .fontColor(this.draft.enabledCategories.indexOf(key) >= 0 ? '#B8860B' : '#666666')
            .borderWidth(this.draft.enabledCategories.indexOf(key) >= 0 ? 2 : 0)
            .borderColor('#FFB400')
            .onClick((): void => this.toggleCategory(key));
        }, (key: string) => key);

        // Custom chip + edit icon
        Button(this.categoryChipLabel('自定义', CUSTOM_CATEGORY_KEY))
          .id('ConfigCategoryCustom')
          .width(80).height(40)
          .fontSize(16)
          .backgroundColor(this.draft.enabledCategories.indexOf(CUSTOM_CATEGORY_KEY) >= 0 ? '#FFF4D0' : '#F0F0F0')
          .fontColor(this.draft.enabledCategories.indexOf(CUSTOM_CATEGORY_KEY) >= 0 ? '#B8860B' : '#666666')
          .borderWidth(this.draft.enabledCategories.indexOf(CUSTOM_CATEGORY_KEY) >= 0 ? 2 : 0)
          .borderColor('#FFB400')
          .onClick((): void => this.toggleCategory(CUSTOM_CATEGORY_KEY));
        Button('✎')
          .id('ConfigCategoryCustomEdit')
          .width(40).height(40)
          .fontSize(18)
          .backgroundColor('#EAF2F8')
          .fontColor('#457B9D')
          .onClick((): void => this.openCustomWords());
      };
    }
    .margin({ bottom: 16 })
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
        this.categoryRow();
        this.parentPinRow();
        this.parentAccountRow();
        this.cloudSyncRow();
        this.syncRow();
        this.adminRow();

        if (this.showValidationHint) {
          Text('单词池太小（少于 3 个），请启用更多类别或添加自定义词')
            .id('ConfigValidationHint')
            .fontSize(14)
            .fontColor('#E63946')
            .margin({ bottom: 12 });
        }

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
    .scrollable(ScrollDirection.Vertical);
  }
}
