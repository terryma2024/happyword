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
import { ParentPinDialog } from '../components/ParentPinDialog';
import { CustomTimerDialog } from '../components/CustomTimerDialog';
import { CloudCredentials, CloudCredentialsSnapshot } from '../services/CloudCredentials';
import { persistGameConfigBestEffort } from '../services/GameConfigPersistence';
import { getLearningRecorder, LearningRecorder } from '../services/LearningRecorder';
import { CloudSyncLike, CloudSyncResult } from '../services/CloudSyncTypes';
import {
  HomeIntegrationBundle,
  loadHomeIntegration,
} from '../services/PackHomeIntegration';
import { MAX_ACTIVE_PACKS } from '../services/PackSelectionService';
/**
 * ConfigPage exposes the five battle knobs (HP / monster count / timer /
 * autoSpeak / parent PIN) plus a single entry row that pushes
 * `pages/PackManagerPage` for three-layer pack selection. All edits
 * happen on a local @State draft; 保存 writes the snapshot to
 * AppStorage and 取消 returns to HomePage untouched.
 *
 * V0.6.6 cleanup: the legacy 词库类别 (enabledCategories) row and
 * its 自定义 / CustomWordsPage entry point were removed when
 * GameConfig dropped those fields.
 *
 * V0.6.7: the inline pack picker section was extracted to
 * `pages/PackManagerPage` so the ConfigPage form stays scannable
 * and the picker can grow independently. The legacy 词库同步 row
 * (powered by `WordPackSyncService`) was also removed — pack
 * synchronisation is now consolidated under PackManagerPage's
 * 🔄 同步词包 button, which drives the three-layer
 * GlobalPackService + FamilyPackService stack.
 *
 * V0.6.7.2: the 解除设备绑定 row was removed too — its full
 * PIN-gated server unbind moved into BoundDeviceInfoPage
 * (孩子档案页), reachable via ConfigBoundDeviceInfoButton above.
 */
@Entry
@Component
struct ConfigPage {
  @State private draft: GameConfig = new GameConfig();
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
  private cloudCreds: CloudCredentials = new CloudCredentials();
  private adminPinDialog: CustomDialogController | null = null;
  // V0.6.7.7: 自定义 timer dialog controller. Created lazily on first
  // tap so the @State `draft.startingSeconds` snapshot fed into the
  // dialog reflects the live value, not whatever was on screen during
  // aboutToAppear. See `openCustomTimerDialog` for the wiring.
  private customTimerDialog: CustomDialogController | null = null;
  /**
   * V0.6.7 — pack-picker entry row state. The inline picker moved to
   * `pages/PackManagerPage`; here we only need the active count to
   * render a hint on the entry row. `loadHomeIntegration` runs in
   * aboutToAppear and again on onPageShow so the count refreshes
   * after the user comes back from the manager page.
   */
  @State private activePackCount: number = 0;
  @State private packPickerStatusText: string = '';
  private homeIntegration: HomeIntegrationBundle = new HomeIntegrationBundle();

  aboutToAppear(): void {
    const stored: GameConfig | undefined =
      AppStorage.get<GameConfig>(GAME_CONFIG_STORAGE_KEY);
    this.draft = cloneGameConfig(stored !== undefined ? stored : new GameConfig());

    const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;

    this.cloudCreds.init(ctx).then((): Promise<void> => this.refreshBindingState())
      .catch((err: BusinessError): void => {
        console.error(`ConfigPage: CloudCredentials.init failed: ${JSON.stringify(err)}`);
      });

    // V0.6.7: bootstrap the unified pack library + selection so the
    // entry row can show "已激活 X/5". The full picker UI lives on
    // `pages/PackManagerPage`.
    loadHomeIntegration(ctx).then((bundle: HomeIntegrationBundle): void => {
      this.homeIntegration = bundle;
      this.refreshPackPickerState();
    }).catch((err: BusinessError): void => {
      console.error(`ConfigPage: loadHomeIntegration failed: ${JSON.stringify(err)}`);
    });
  }

  /** Mirror selection count into @State so the entry row re-renders. */
  private refreshPackPickerState(): void {
    const activeIds: string[] = this.homeIntegration.selection.getActiveIds();
    this.activePackCount = activeIds.length;
    const limit: number = MAX_ACTIVE_PACKS;
    this.packPickerStatusText = `已激活 ${activeIds.length} / ${limit}`;
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
    // V0.6.7: PackManagerPage may have edited the active set; reload
    // so the entry row's "已激活 X/5" text mirrors the persisted state.
    const ctx: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    loadHomeIntegration(ctx).then((bundle: HomeIntegrationBundle): void => {
      this.homeIntegration = bundle;
      this.refreshPackPickerState();
    }).catch((err: BusinessError): void => {
      console.error(`ConfigPage.onPageShow: loadHomeIntegration failed: ${JSON.stringify(err)}`);
    });
  }

  private forceRerender(): void {
    this.draft = cloneGameConfig(this.draft);
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
      // V0.6.7.2 — 解除设备绑定 lives on BoundDeviceInfoPage now (孩子档案页),
      // reachable via ConfigBoundDeviceInfoButton above. Removing the
      // duplicate ConfigPage row keeps a single canonical entry point and
      // avoids the prior "(本地)" vs "服务端 unbind" divergence.
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
    // pool-size validation. The pack picker (我的词包) enforces
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

  /**
   * V0.6.7.7: the 自定义 button is "selected" whenever
   * `draft.startingSeconds` is NOT one of the four preset chips. Its
   * label echoes the live custom value (e.g. `✓自定义 (3s)`) so the
   * parent can see at a glance what was dialled in without re-opening
   * the dialog. Same `✓` prefix convention as the preset chips so UI
   * tests can read selection state via `getText()`.
   */
  private isCustomTimer(): boolean {
    return TIMER_CHOICES.indexOf(this.draft.startingSeconds) < 0;
  }

  private customTimerButtonLabel(): string {
    if (this.isCustomTimer()) {
      return `✓自定义 (${this.timerLabel(this.draft.startingSeconds)})`;
    }
    return '自定义';
  }

  @Builder
  private timerRow() {
    Row() {
      Text('倒计时').fontSize(18).width(120);
      Row({ space: 8 }) {
        // V0.6.7.7: chips dropped the old `width(64)` because at
        // fontSize(16) the active prefix `✓` plus a 3-char body like
        // `5m` / `10m` overflowed and rendered as `✓...` / `1...`.
        // Padding-based intrinsic sizing (matching the 自定义 button
        // below) lets every chip take exactly the room its label
        // needs while keeping the row compact.
        ForEach(TIMER_CHOICES, (sec: number) => {
          Button(this.timerChipLabel(sec))
            .id(this.timerChipId(sec))
            .height(40)
            .padding({ left: 12, right: 12 })
            .fontSize(16)
            .backgroundColor(this.draft.startingSeconds === sec ? '#FFB400' : '#EAF2F8')
            .fontColor(this.draft.startingSeconds === sec ? '#FFFFFF' : '#457B9D')
            .onClick((): void => this.selectTimer(sec));
        }, (sec: number) => `${sec}`);
        // V0.6.7.7: 自定义 button — opens CustomTimerDialog so the
        // parent can dial in any positive integer in [TIMER_CUSTOM_MIN,
        // TIMER_CUSTOM_MAX] seconds. UI tests rely on this for the
        // 3s-fast-timeout flow (see PackManagerFlow's battle-timeout
        // companion test).
        Button(this.customTimerButtonLabel())
          .id('ConfigTimerCustom')
          .height(40)
          .padding({ left: 12, right: 12 })
          .fontSize(16)
          .backgroundColor(this.isCustomTimer() ? '#FFB400' : '#EAF2F8')
          .fontColor(this.isCustomTimer() ? '#FFFFFF' : '#457B9D')
          .onClick((): void => this.openCustomTimerDialog());
      };
    }
    .margin({ bottom: 12 })
    .alignItems(VerticalAlign.Center);
  }

  /**
   * V0.6.7.7: open the 自定义 dialog, seeded with the current
   * draft.startingSeconds. The controller is rebuilt on every tap
   * because @CustomDialog props are captured at construction time —
   * a stale controller would feed the dialog an old initialSeconds
   * if the parent picked a chip after the previous open.
   */
  private openCustomTimerDialog(): void {
    let ctrl: CustomDialogController | null = null;
    ctrl = new CustomDialogController({
      builder: CustomTimerDialog({
        initialSeconds: this.draft.startingSeconds,
        onSubmit: (seconds: number): void => {
          this.draft.startingSeconds = seconds;
          this.forceRerender();
        },
        onCancel: (): void => {},
      }),
      autoCancel: true,
      customStyle: true,
    });
    this.customTimerDialog = ctrl;
    ctrl.open();
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

  // V0.6.7 — pack picker entry row; full picker UI lives in
  // `pages/PackManagerPage`.

  private openPackManager(): void {
    this.getUIContext().getRouter().pushUrl({ url: 'pages/PackManagerPage' })
      .catch((err: BusinessError): void => {
        console.error(`ConfigPage: pushUrl PackManagerPage failed: ${JSON.stringify(err)}`);
      });
  }

  @Builder
  private packPickerSection() {
    Row() {
      // V0.6.7.7: dropped the leading 📦 to match the rest of the
      // ConfigPage row labels (玩家血量 / 怪物血量 / 怪物数量 /
      // 倒计时 / 发音播放 / 家长密码 / 家长账户 / 学习记录 / 家长)
      // — none of those carry a leading emoji.
      Text('我的词包').fontSize(18).width(120);
      Row() {
        Text(this.packPickerStatusText.length > 0
          ? this.packPickerStatusText
          : `已激活 ${this.activePackCount} / ${MAX_ACTIVE_PACKS}`)
          .id('ConfigPackPickerStatus')
          .fontSize(15)
          .fontColor('#1f2937')
          .layoutWeight(1)
          .textAlign(TextAlign.Start);
        Text('管理 ›')
          .fontSize(15)
          .fontColor('#457B9D')
          .margin({ left: 8 });
      }
      .id('ConfigPackManagerEntry')
      .width(220).height(40)
      .padding({ left: 12, right: 12 })
      .backgroundColor('#EAF2F8')
      .borderRadius(8)
      .alignItems(VerticalAlign.Center)
      .onClick((): void => this.openPackManager());
    }
    .margin({ bottom: 12 })
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
