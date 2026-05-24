import { common } from '@kit.AbilityKit';
import { BusinessError } from '@ohos.base';

import { Pack } from '../models/Pack';
import {
  HomeIntegrationBundle,
  loadHomeIntegration,
} from '../services/PackHomeIntegration';
import { MAX_ACTIVE_PACKS } from '../services/PackSelectionService';
import { GlobalPackService, GlobalPackEnsureResult } from '../services/GlobalPackService';
import { FamilyPackService, FamilyPackEnsureResult } from '../services/FamilyPackService';
import { PackNetworkFetchAdapter } from '../services/PackNetworkFetchAdapter';
import { CloudCredentials, CloudCredentialsSnapshot } from '../services/CloudCredentials';
import { effectiveServerBaseUrl } from '../services/RemoteWordPackConfig';
import { PAGE_BODY_EDGE_VP } from '../constants/PageLayoutInsets';
import { PageTopChrome } from '../components/PageTopChrome';
import { requestPageOrientation } from '../utils/orientation';

/**
 * V0.6.7 — dedicated page for the three-layer pack picker. Extracted
 * from the V0.6.5.1 ConfigPage `packPickerSection` so the form stays
 * scannable and the picker can grow independently (English pack names
 * + tag-style source label + iOS-style switch toggle + sync button).
 *
 * State model mirrors ConfigPage's prior section verbatim — same
 * `loadHomeIntegration` cold-start, same `togglePackActive` /
 * `togglePackPin` / `onPackSyncTap` flow — so existing PackSelection
 * Service tests continue to apply unchanged.
 *
 * V0.6.7.3: the 📌 pin button now only renders for already-active
 * packs (the previous "·" placeholder on inactive rows looked like
 * noise and tapping it only ever produced an error toast). Inactive
 * rows fall back to a `Blank` spacer so the Toggle column stays
 * aligned across all rows.
 */
@Entry
@Component
struct PackManagerPage {
  @State private availablePacks: Pack[] = [];
  @State private activePackIds: string[] = [];
  @State private pinnedPackIds: string[] = [];
  @State private packPickerVersion: number = 0;
  @State private packSyncBusy: boolean = false;
  @State private packSyncStatusText: string = '';
  @State private packSyncToastText: string = '';
  @State private packToastId: string = 'PackManagerSyncToast';
  @State private loaded: boolean = false;
  private packPickerToastTimer: number = -1;
  private homeIntegration: HomeIntegrationBundle = new HomeIntegrationBundle();
  private cloudCreds: CloudCredentials = new CloudCredentials();

  private applyOrientationPolicy(): void {
    requestPageOrientation(
      this.getUIContext().getHostContext() as common.UIAbilityContext,
      'PackManagerPage',
      (px: number): number => this.getUIContext().px2vp(px),
    );
  }

  aboutToAppear(): void {
    this.applyOrientationPolicy();
    const ctx: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.cloudCreds.init(ctx).catch((err: BusinessError): void => {
      console.error(`PackManagerPage: CloudCredentials.init failed: ${JSON.stringify(err)}`);
    });
    loadHomeIntegration(ctx).then((bundle: HomeIntegrationBundle): void => {
      this.homeIntegration = bundle;
      this.refreshPackPickerState();
      this.loaded = true;
    }).catch((err: BusinessError): void => {
      console.error(`PackManagerPage: loadHomeIntegration failed: ${JSON.stringify(err)}`);
      this.loaded = true;
    });
  }

  aboutToDisappear(): void {
    if (this.packPickerToastTimer >= 0) {
      clearTimeout(this.packPickerToastTimer);
      this.packPickerToastTimer = -1;
    }
  }

  onPageShow(): void {
    this.applyOrientationPolicy();
    if (!this.loaded) {
      return;
    }
    const ctx: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    loadHomeIntegration(ctx).then((bundle: HomeIntegrationBundle): void => {
      this.homeIntegration = bundle;
      this.refreshPackPickerState();
    }).catch((err: BusinessError): void => {
      console.error(`PackManagerPage.onPageShow: loadHomeIntegration failed: ${JSON.stringify(err)}`);
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

  private forceRerender(): void {
    this.packPickerVersion = this.packPickerVersion + 1;
  }

  /** Toggle a pack in/out of the active selection. At cap, auto-closes earliest unpinned. */
  private async togglePackActive(packId: string): Promise<void> {
    const idx: number = this.activePackIds.indexOf(packId);
    if (idx >= 0) {
      const next: string[] = this.activePackIds.slice();
      next.splice(idx, 1);
      try {
        await this.homeIntegration.selection.setActiveIds(next);
        this.refreshPackPickerState();
      } catch (err) {
        console.error(`PackManagerPage.togglePackActive failed: ${JSON.stringify(err as BusinessError)}`);
        this.showPackToast('保存失败，请重试', 'PackManagerSyncToast');
      }
      return;
    }
    try {
      const outcome = await this.homeIntegration.selection.appendOrRotate(packId);
      if (outcome.result === 'refused-all-pinned') {
        this.showPackToast('请先取消固定一个词包', 'PackManagerCapRefuseToast');
        return;
      }
      this.refreshPackPickerState();
      if (outcome.autoClosed !== null) {
        const closedName: string = this.packDisplayNameById(outcome.autoClosed);
        const addedName: string = this.packDisplayNameById(packId);
        this.showPackToast(
          `已关闭 '${closedName}' 以激活 '${addedName}'`,
          'PackManagerAutoRotateToast',
        );
        console.info(
          `pack.selection.auto-rotated victimId=${outcome.autoClosed} addedId=${packId}`,
        );
      }
    } catch (err) {
      console.error(`PackManagerPage.togglePackActive failed: ${JSON.stringify(err as BusinessError)}`);
      this.showPackToast('保存失败，请重试', 'PackManagerSyncToast');
    }
  }

  private async togglePackPin(packId: string): Promise<void> {
    // V0.6.7.3: the pin button is now only rendered for active packs
    // (see `packRow`), so this branch is unreachable from the UI.
    // Kept as a defensive guard for future callers (e.g. a possible
    // long-press gesture on inactive rows) and unit tests.
    if (this.activePackIds.indexOf(packId) < 0) {
      this.showPackToast('只有已激活的词包才能 📌 固定');
      return;
    }
    try {
      await this.homeIntegration.selection.togglePin(packId);
      this.refreshPackPickerState();
    } catch (err) {
      console.error(`PackManagerPage.togglePackPin failed: ${JSON.stringify(err as BusinessError)}`);
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
    const ctx: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
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
      console.error(`PackManagerPage.onPackSyncTap (global) failed: ${JSON.stringify(err as BusinessError)}`);
    }
    try {
      const snap: CloudCredentialsSnapshot = await this.cloudCreds.load();
      if (snap.deviceToken.length > 0) {
        familyAttempted = true;
        await fps.init(ctx);
        const fOut: FamilyPackEnsureResult =
          await fps.ensureLatest(snap.deviceToken, snap.familyId);
        familyUpdated = fOut.status === 'updated' || fOut.status === 'cleared';
      }
    } catch (err) {
      console.error(`PackManagerPage.onPackSyncTap (family) failed: ${JSON.stringify(err as BusinessError)}`);
    }

    // Re-load the merged library so newly fetched packs appear without
    // bouncing back to ConfigPage. Selection is preserved.
    try {
      this.homeIntegration = await loadHomeIntegration(ctx);
      this.refreshPackPickerState();
    } catch (err) {
      console.error(`PackManagerPage.onPackSyncTap reload failed: ${JSON.stringify(err as BusinessError)}`);
    }
    this.packSyncBusy = false;
    this.showPackToast(PackManagerPage.formatPackSyncToast(globalsUpdated, familyUpdated, familyAttempted));
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

  private showPackToast(text: string, toastId: string = 'PackManagerSyncToast'): void {
    this.packSyncToastText = text;
    this.packToastId = toastId;
    if (this.packPickerToastTimer >= 0) {
      clearTimeout(this.packPickerToastTimer);
    }
    this.packPickerToastTimer = setTimeout((): void => {
      this.packSyncToastText = '';
      this.packToastId = 'PackManagerSyncToast';
      this.packPickerToastTimer = -1;
      this.forceRerender();
    }, 2400);
  }

  /**
   * V0.6.7: prefer the English `name` for display. Falls back to the
   * Chinese override or the pack id only when name is empty (e.g. a
   * malformed family pack draft).
   */
  private packDisplayName(p: Pack): string {
    if (p.name.length > 0) return p.name;
    if (p.labelZh.length > 0) return p.labelZh;
    return p.id;
  }

  private packDisplayNameById(packId: string): string {
    for (let i = 0; i < this.availablePacks.length; i++) {
      if (this.availablePacks[i].id === packId) {
        return this.packDisplayName(this.availablePacks[i]);
      }
    }
    return packId;
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

  private isActive(packId: string): boolean {
    return this.activePackIds.indexOf(packId) >= 0;
  }

  private isPinned(packId: string): boolean {
    return this.pinnedPackIds.indexOf(packId) >= 0;
  }

  @Builder
  private packManagerSyncTrailing(): void {
    Button(this.packSyncBusy ? '同步中…' : '🔄 同步词包')
      .id('PackManagerSyncButton')
      .height(40)
      .fontSize(15)
      .padding({ left: 14, right: 14 })
      .backgroundColor(this.packSyncBusy ? '#F0F0F0' : '#EAF2F8')
      .fontColor(this.packSyncBusy ? '#999999' : '#457B9D')
      .enabled(!this.packSyncBusy)
      .onClick((): void => {
        this.onPackSyncTap().catch((err: BusinessError): void => {
          console.error(`PackManagerPage.onPackSyncTap promise failed: ${JSON.stringify(err)}`);
        });
      });
  }

  @Builder
  private statusRow() {
    Row() {
      Text(this.packSyncStatusText)
        .id('PackManagerStatus')
        .fontSize(14).fontColor('#6B7280');
      Blank().layoutWeight(1);
      Text('固定：防止满分自动轮换 · 开关：切换激活')
        .fontSize(12).fontColor('#9CA3AF');
    }
    .width('100%')
    .padding({
      left: PAGE_BODY_EDGE_VP,
      right: PAGE_BODY_EDGE_VP,
      top: 4,
      bottom: 12,
    });
  }

  @Builder
  private packRow(p: Pack) {
    Row({ space: 10 }) {
      // V0.6.7: source tag is rendered as a small pill to the LEFT of
      // the pack name, so the row reads "[内置] Fruit Forest" rather
      // than burying the badge near the right edge.
      Text(this.packSourceTag(p))
        .id(`PackSourceTag_${p.id}`)
        .fontSize(11)
        .fontColor('#FFFFFF')
        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
        .backgroundColor(this.packSourceColor(p))
        .borderRadius(4);

      Text(this.packDisplayName(p))
        .id(`PackLabel_${p.id}`)
        .fontSize(16)
        .fontColor('#1F2937')
        .layoutWeight(1);

      // V0.6.7.3: pin toggle is rendered ONLY for already-active packs.
      // Pinning an inactive pack was a no-op anyway (togglePackPin
      // bails with a toast), and the prior "·" placeholder on inactive
      // rows just looked like noise. For inactive packs we drop in a
      // matching-size Blank so the Toggle column stays vertically
      // aligned with the active rows.
      //
      // The button uses an explicit text label ("📌 固定" / "已固定")
      // rather than a bare emoji icon — the 📌 glyph alone rendered
      // illegibly small inside a 36-vp square in earlier screenshots
      // and looked indistinguishable from the dim "·" placeholder it
      // was meant to replace. The yellow background (#FEF3C7) plus the
      // copy change make the pinned state unambiguous at a glance.
      if (this.isActive(p.id)) {
        Button(this.isPinned(p.id) ? '已固定' : '📌 固定')
          .id(`PackPin_${p.id}`)
          .height(36).fontSize(13)
          .padding({ left: 10, right: 10 })
          .backgroundColor(this.isPinned(p.id) ? '#FEF3C7' : '#F3F4F6')
          .fontColor(this.isPinned(p.id) ? '#B45309' : '#6B7280')
          .borderRadius(8)
          .onClick((): void => {
            this.togglePackPin(p.id).catch((err: BusinessError): void => {
              console.error(`PackManagerPage.togglePackPin promise failed: ${JSON.stringify(err)}`);
            });
          });
      } else {
        Blank().height(36);
      }

      // V0.6.7: replaces the prior dim "✓ / blank" button with a
      // platform-style switch. `Toggle` fires `onChange` whenever the
      // user flips it; togglePackActive idempotently adds/removes the
      // id from the active set so a fast double-tap never desyncs.
      Toggle({ type: ToggleType.Switch, isOn: this.isActive(p.id) })
        .id(`PackToggle_${p.id}`)
        .selectedColor('#FFB400')
        .switchPointColor('#FFFFFF')
        .width(48).height(28)
        .onChange((isOn: boolean): void => {
          if (isOn === this.isActive(p.id)) {
            return;
          }
          this.togglePackActive(p.id).catch((err: BusinessError): void => {
            console.error(`PackManagerPage.togglePackActive promise failed: ${JSON.stringify(err)}`);
          });
        });
    }
    .width('100%')
    .padding({
      left: PAGE_BODY_EDGE_VP,
      right: PAGE_BODY_EDGE_VP,
      top: 10,
      bottom: 10,
    })
    .alignItems(VerticalAlign.Center)
    .borderRadius(10)
    .backgroundColor('#FFFFFF');
  }

  build(): void {
    Column() {
      PageTopChrome({
        backButtonId: 'PackManagerBack',
        title: '📦 我的词包',
        titleId: 'PackManagerTitle',
        onBack: (): void => {
          this.getUIContext().getRouter().back();
        },
        trailing: (): void => {
          this.packManagerSyncTrailing();
        },
      });
      this.statusRow();
      Scroll() {
        Column({ space: 6 }) {
          if (!this.loaded || this.availablePacks.length === 0) {
            Text(this.loaded ? '暂无词包，可点击右上角「同步词包」' : '正在加载词包…')
              .id('PackManagerLoading')
              .fontSize(13).fontColor('#9CA3AF')
              .margin({ top: 24 });
          } else {
            ForEach(this.availablePacks, (p: Pack): void => {
              this.packRow(p);
            }, (p: Pack): string => p.id);
          }
        }
        .width('100%')
        .padding({
          left: PAGE_BODY_EDGE_VP,
          right: PAGE_BODY_EDGE_VP,
          bottom: PAGE_BODY_EDGE_VP,
        });
      }
      .layoutWeight(1)
      .scrollable(ScrollDirection.Vertical);

      if (this.packSyncToastText.length > 0) {
        Text(this.packSyncToastText)
          .id(this.packToastId)
          .fontSize(13).fontColor('#1D3557')
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .backgroundColor('#FFF4D0')
          .borderRadius(6)
          .margin({ left: PAGE_BODY_EDGE_VP, right: PAGE_BODY_EDGE_VP, bottom: 12 });
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F8FAFC')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM,
      SafeAreaEdge.START, SafeAreaEdge.END]);
  }
}
