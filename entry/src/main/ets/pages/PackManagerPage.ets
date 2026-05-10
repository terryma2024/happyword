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
  @State private loaded: boolean = false;
  private packPickerToastTimer: number = -1;
  private homeIntegration: HomeIntegrationBundle = new HomeIntegrationBundle();
  private cloudCreds: CloudCredentials = new CloudCredentials();

  aboutToAppear(): void {
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

  /** Toggle a pack in/out of the active selection. Enforces the cap. */
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
      console.error(`PackManagerPage.togglePackActive failed: ${JSON.stringify(err as BusinessError)}`);
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
        const fOut: FamilyPackEnsureResult = await fps.ensureLatest(snap.deviceToken);
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
  private headerBar() {
    Row() {
      Button('←')
        .id('PackManagerBack')
        .width(44).height(44)
        .fontSize(22)
        .fontColor('#1f2937')
        .backgroundColor('#F3F4F6')
        .borderRadius(22)
        .onClick((): void => {
          this.getUIContext().getRouter().back();
        });
      Text('📦 我的词包')
        .id('PackManagerTitle')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1f2937')
        .margin({ left: 12 });
      Blank().layoutWeight(1);
      Button(this.packSyncBusy ? '同步中…' : '🔄 同步词包')
        .id('PackManagerSyncButton')
        .height(40).fontSize(15)
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
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 8 })
    .alignItems(VerticalAlign.Center);
  }

  @Builder
  private statusRow() {
    Row() {
      Text(this.packSyncStatusText)
        .id('PackManagerStatus')
        .fontSize(14).fontColor('#6B7280');
      Blank().layoutWeight(1);
      Text('点击右侧开关切换激活；📌 防止满分自动轮换')
        .fontSize(12).fontColor('#9CA3AF');
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 4, bottom: 12 });
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

      // Pin toggle — only meaningful when pack is active. A pinned
      // pack is exempt from the perfect-rotation auto-swap.
      Button(this.isPinned(p.id) ? '📌' : '·')
        .id(`PackPin_${p.id}`)
        .width(36).height(36).fontSize(16)
        .backgroundColor(this.isPinned(p.id) ? '#FEF3C7' : '#F3F4F6')
        .fontColor(this.isPinned(p.id) ? '#B45309' : '#9CA3AF')
        .borderRadius(8)
        .onClick((): void => {
          this.togglePackPin(p.id).catch((err: BusinessError): void => {
            console.error(`PackManagerPage.togglePackPin promise failed: ${JSON.stringify(err)}`);
          });
        });

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
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .alignItems(VerticalAlign.Center)
    .borderRadius(10)
    .backgroundColor('#FFFFFF');
  }

  build(): void {
    Column() {
      this.headerBar();
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
        .padding({ left: 12, right: 12, top: 4, bottom: 24 });
      }
      .layoutWeight(1)
      .scrollable(ScrollDirection.Vertical);

      if (this.packSyncToastText.length > 0) {
        Text(this.packSyncToastText)
          .id('PackManagerSyncToast')
          .fontSize(13).fontColor('#1D3557')
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .backgroundColor('#FFF4D0')
          .borderRadius(6)
          .margin({ left: 16, right: 16, bottom: 12 });
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F8FAFC')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM,
      SafeAreaEdge.START, SafeAreaEdge.END]);
  }
}
