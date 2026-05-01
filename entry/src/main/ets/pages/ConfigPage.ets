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
