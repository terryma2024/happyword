import { router, promptAction } from '@kit.ArkUI';
import { BusinessError } from '@ohos.base';
import { common } from '@kit.AbilityKit';
import { MagicWish, WishState } from '../models/MagicWish';
import { CoinSnapshot } from '../models/CoinSnapshot';
import {
  GameConfig,
  GAME_CONFIG_STORAGE_KEY,
} from '../models/GameConfig';
import { RedemptionRecord } from '../models/RedemptionRecord';
import { WishlistStore, getWishlistStore } from '../services/WishlistStore';
import { CoinAccount, getCoinAccount } from '../services/CoinAccount';
import {
  RedemptionHistoryStore,
  getRedemptionHistoryStore,
} from '../services/RedemptionHistoryStore';
import { ParentPinDialog, PIN_LENGTH } from '../components/ParentPinDialog';
import { GiftBox } from '../components/GiftBox';
import {
  AddCustomWishDialog,
  CustomWishFormResult,
} from '../components/AddCustomWishDialog';

/** Total time the GiftBox modal stays visible: anim cycle ~1.68s + 1.5s hold. */
const GIFTBOX_MODAL_TOTAL_MS: number = 3180;

/** Auto-acknowledge delay between Confirmed → Idle on the wish card. */
const ACK_DELAY_MS: number = 1500;

/**
 * V0.4.7 — what action the parent-PIN gate is currently guarding.
 * Used by the shared `onPinConfirmed` router so we don't keep three
 * near-identical PIN dialog ctors around.
 */
type PinIntent = 'redeem' | 'add-custom' | 'remove-custom';

/**
 * V0.3.9 WishlistPage — child-facing list of magic wishes.
 *
 * Redemption flow (replaces V0.3.8 Idle → Pending → ParentLongPressGate):
 *  1. Tap 申请兑换. If `GameConfig.parentPin` is unset, show an
 *     AlertDialog directing the parent to ConfigPage; refuse to open
 *     the PIN dialog.
 *  2. ParentPinDialog opens. Wrong PIN shakes + clears (no lockout).
 *     Right PIN dismisses the dialog and runs redeemNow.
 *  3. redeemNow calls `coins.redeem` → `store.markConfirmed` →
 *     appends a RedemptionRecord to the history store, then mounts
 *     the GiftBox modal overlay (3.18s blocking) and finally
 *     auto-acknowledges the card back to Idle 1.5s after the modal
 *     disappears.
 *
 * Header gains a 📜 icon button (left of "我的魔法币") that routes
 * to RedemptionHistoryPage. Cards are restructured: name + cost on
 * the left, prize emoji + 申请兑换 button right-aligned on a single
 * row (was: emoji+name on top, button centred below).
 */
@Entry
@Component
struct WishlistPage {
  @State private wishes: MagicWish[] = [];
  @State private balance: number = 0;
  @State private giftBoxVisible: boolean = false;
  @State private giftBoxTrigger: number = 0;
  private store: WishlistStore = getWishlistStore();
  private coins: CoinAccount = getCoinAccount();
  private history: RedemptionHistoryStore = getRedemptionHistoryStore();
  private pendingWishId: string = '';
  private pendingPinIntent: PinIntent = 'redeem';
  private pinDialog: CustomDialogController | null = null;
  private addDialog: CustomDialogController | null = null;

  aboutToAppear(): void {
    const ctx: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    Promise.all<void>([
      this.coins.init(ctx),
      this.store.init(ctx),
      this.history.init(ctx),
    ])
      .then((): void => {
        this.coins.beginToday(Date.now());
        this.refresh();
      })
      .catch((err: BusinessError): void => {
        console.error(`WishlistPage init failed: ${JSON.stringify(err)}`);
        this.refresh();
      });
  }

  onPageShow(): void {
    this.coins.beginToday(Date.now());
    this.refresh();
  }

  /**
   * V0.3.9: while the GiftBox modal is up the system Back press
   * must not pop the page (parent-vs-child intent: animations and
   * persistence have already committed; we only need to outlast
   * the celebration). Returning true from onBackPress consumes
   * the event so the router does not navigate.
   */
  onBackPress(): boolean {
    if (this.giftBoxVisible) {
      return true;
    }
    return false;
  }

  build(): void {
    Stack({ alignContent: Alignment.Center }) {
      Column({ space: 12 }) {
        this.headerRow();
        Text('魔法愿望单')
          .id('WishlistTitle')
          .fontSize(26)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1D3557');
        Scroll() {
          Column({ space: 12 }) {
            ForEach(this.wishes, (w: MagicWish): void => {
              this.wishCardInline(w);
            }, (w: MagicWish): string => w.id);
          }
          .padding({ top: 8, bottom: 24 });
        }
        .layoutWeight(1);
      }
      .width('100%')
      .height('100%')
      .padding({ left: 16, right: 16, top: 24 })
      .backgroundColor('#F8F9FA');

      if (this.giftBoxVisible) {
        this.giftBoxModal();
      }
    }
    .width('100%')
    .height('100%');
  }

  /**
   * Per-cell layout. Inlined into ForEach (not a parameterised
   * @Builder) because ArkUI's compile-time dependency analysis only
   * tracks @State reads inside an unparameterised builder body —
   * a parameter object's property reads (e.g. `w.state`) do NOT
   * register as deps, so a parameterised @Builder cell would stay
   * frozen on its initial state. See the v0.3.6 letter-spacing
   * lesson + v0.3.8 申请兑换 bug for prior incidents.
   */
  @Builder
  private wishCardInline(w: MagicWish) {
    Row({ space: 12 }) {
      Text(w.iconEmoji)
        .fontSize(32);
      Column({ space: 4 }) {
        Text(w.displayName)
          .id(`WishName_${w.id}`)
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor('#1D3557');
        Text(`${w.costCoins} ✨`)
          .fontSize(14)
          .fontColor('#FFB400');
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1);

      if (w.state === WishState.Idle) {
        if (this.balance >= w.costCoins) {
          Button('申请兑换')
            .id(`WishApply_${w.id}`)
            .width(108)
            .height(40)
            .backgroundColor('#E63946')
            .fontColor('#FFFFFF')
            .fontSize(15)
            .onClick((): void => {
              this.onApply(w.id);
            });
        } else {
          Text(`还差 ${w.costCoins - this.balance} ✨`)
            .id(`WishGap_${w.id}`)
            .fontSize(13)
            .fontColor('#888888');
        }
      } else if (w.state === WishState.Confirmed) {
        Text('已兑换 ✓')
          .id(`WishConfirmed_${w.id}`)
          .fontSize(15)
          .fontColor('#2ECC71');
      } else {
        // Legacy Pending should not occur after V0.3.9 migration;
        // render a neutral placeholder for safety.
        Text('…')
          .fontSize(14)
          .fontColor('#888888');
      }

      // V0.4.7: only parent-created custom wishes get a remove button.
      // The button itself opens a PIN gate before the actual delete.
      if (w.isCustom) {
        Button('✕')
          .id(`WishRemove_${w.id}`)
          .width(32)
          .height(32)
          .fontSize(14)
          .fontColor('#888888')
          .backgroundColor('#F1F2F4')
          .onClick((): void => {
            this.onTapRemoveCustom(w.id);
          });
      }
    }
    .id(`WishCard_${w.id}`)
    .width('92%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor('#FFFFFF')
    .borderRadius(14)
    .alignItems(VerticalAlign.Center)
    .shadow({ radius: 8, color: '#11000000', offsetX: 0, offsetY: 2 });
  }

  @Builder
  private headerRow() {
    Row({ space: 12 }) {
      Button('← 返回')
        .id('WishlistBackButton')
        .type(ButtonType.Normal)
        .backgroundColor(Color.Transparent)
        .fontColor('#457B9D')
        .onClick((): void => {
          if (this.giftBoxVisible) {
            return;
          }
          try {
            router.back();
          } catch (err) {
            console.error(`WishlistPage.back failed: ${JSON.stringify(err as BusinessError)}`);
          }
        });
      Blank()
        .layoutWeight(1);
      // V0.3.10: emoji-text 📜 replaced with the warm-parchment scroll
      // SVG; id / dimensions / background colour preserved so existing
      // by-id UI tests continue to match. borderRadius(8) explicitly
      // set because the container Button() syntax does not inherit the
      // default rectangular Button's soft-corner rounding.
      Button({ type: ButtonType.Normal, stateEffect: true }) {
        Image($rawfile('icons/scroll.svg'))
          .width(22)
          .height(22)
          .objectFit(ImageFit.Contain)
          .syncLoad(true);
      }
        .id('WishlistHistoryButton')
        .width(40)
        .height(36)
        .backgroundColor('#EAF2F8')
        .borderRadius(8)
        .onClick((): void => {
          if (this.giftBoxVisible) {
            return;
          }
          router.pushUrl({ url: 'pages/RedemptionHistoryPage' })
            .catch((err: BusinessError): void => {
              console.error(`WishlistPage: pushUrl history failed: ${JSON.stringify(err)}`);
            });
        });
      Button('+ 添加')
        .id('WishlistAddCustomButton')
        .type(ButtonType.Normal)
        .height(36)
        .padding({ left: 12, right: 12 })
        .backgroundColor('#EAF2F8')
        .fontColor('#1D3557')
        .borderRadius(8)
        .fontSize(14)
        .onClick((): void => {
          this.onTapAddCustom();
        });
      Text(`我的魔法币: ${this.balance} ✨`)
        .id('WishlistBalance')
        .fontSize(16)
        .fontColor('#FFB400');
    }
    .width('100%')
    .alignItems(VerticalAlign.Center);
  }

  /**
   * Top-level overlay shown while a redemption is celebrating. The
   * `HitTestMode.Block` on the backdrop swallows every touch under
   * it so taps on cards / header buttons are no-ops during the
   * 3.18 s window. `onBackPress` (above) handles the system back
   * press the same way. The GiftBox itself is centred and re-keyed
   * via `giftBoxTrigger` to ensure each modal mount runs a fresh
   * animation cycle.
   */
  @Builder
  private giftBoxModal() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0, 0, 0, 0.5)')
        .hitTestBehavior(HitTestMode.Block);
      GiftBox({ trigger: this.giftBoxTrigger })
        .id('WishlistGiftBoxModal');
    }
    .width('100%')
    .height('100%');
  }

  private refresh(): void {
    this.wishes = this.store.list();
    const snap: CoinSnapshot = this.coins.snapshot();
    this.balance = snap.totalCoins - snap.spentCoins;
  }

  private getParentPin(): string {
    const stored: GameConfig | undefined =
      AppStorage.get<GameConfig>(GAME_CONFIG_STORAGE_KEY);
    if (stored === undefined) {
      return '';
    }
    return stored.parentPin;
  }

  private onApply(wishId: string): void {
    if (this.giftBoxVisible) {
      return;
    }
    const expected: string = this.getParentPin();
    if (expected.length !== PIN_LENGTH) {
      this.showNoPinAlert();
      return;
    }
    this.pendingWishId = wishId;
    this.pendingPinIntent = 'redeem';
    this.openPinDialog(expected, '请输入家长密码以兑换');
  }

  private onTapAddCustom(): void {
    if (this.giftBoxVisible) {
      return;
    }
    const expected: string = this.getParentPin();
    if (expected.length !== PIN_LENGTH) {
      this.showNoPinAlert();
      return;
    }
    this.pendingWishId = '';
    this.pendingPinIntent = 'add-custom';
    this.openPinDialog(expected, '请输入家长密码以添加自定义愿望');
  }

  private onTapRemoveCustom(wishId: string): void {
    if (this.giftBoxVisible) {
      return;
    }
    const expected: string = this.getParentPin();
    if (expected.length !== PIN_LENGTH) {
      this.showNoPinAlert();
      return;
    }
    this.pendingWishId = wishId;
    this.pendingPinIntent = 'remove-custom';
    this.openPinDialog(expected, '请输入家长密码以删除该愿望');
  }

  private showNoPinAlert(): void {
    promptAction.showDialog({
      title: '尚未设置家长密码',
      message: '请先在设置页面配置家长密码（6 位数字），再使用此功能。',
      buttons: [{ text: '知道了', color: '#1D3557' }],
    }).catch((err: BusinessError): void => {
      console.error(`WishlistPage: showDialog failed: ${JSON.stringify(err)}`);
    });
  }

  private openPinDialog(expected: string, title: string): void {
    // Two-step ctor: declare `ctrl` first, then create the
    // CustomDialogController. This lets the onConfirm/onCancel
    // closures capture `ctrl` and close the dialog explicitly,
    // bypassing the @CustomDialog auto-bound `controller` field
    // (which has been observed not to bind reliably when the dialog
    // struct is instantiated with explicit named parameters under
    // customStyle: true). See V0.3.9 emulator regression.
    let ctrl: CustomDialogController | null = null;
    ctrl = new CustomDialogController({
      builder: ParentPinDialog({
        expectedPin: expected,
        title,
        onConfirm: (): void => {
          if (ctrl !== null) {
            ctrl.close();
          }
          this.dispatchPinConfirmed();
        },
        onCancel: (): void => {
          if (ctrl !== null) {
            ctrl.close();
          }
          this.pendingWishId = '';
        },
      }),
      autoCancel: true,
      customStyle: true,
    });
    this.pinDialog = ctrl;
    ctrl.open();
  }

  private dispatchPinConfirmed(): void {
    const intent: PinIntent = this.pendingPinIntent;
    if (intent === 'redeem') {
      this.redeemNow(this.pendingWishId);
      return;
    }
    if (intent === 'add-custom') {
      this.openAddCustomDialog();
      return;
    }
    if (intent === 'remove-custom') {
      this.confirmRemoveCustom(this.pendingWishId);
      return;
    }
  }

  private openAddCustomDialog(): void {
    let ctrl: CustomDialogController | null = null;
    ctrl = new CustomDialogController({
      builder: AddCustomWishDialog({
        onSubmit: (result: CustomWishFormResult): void => {
          if (ctrl !== null) {
            ctrl.close();
          }
          this.commitAddCustomWish(result);
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
    this.addDialog = ctrl;
    ctrl.open();
  }

  private commitAddCustomWish(result: CustomWishFormResult): void {
    const newId: string = this.store.addCustomWish(
      result.name,
      result.costCoins,
      result.iconEmoji,
      Date.now(),
    );
    if (newId.length === 0) {
      promptAction.showToast({ message: '添加失败，请检查输入', duration: 1500 });
      return;
    }
    this.refresh();
  }

  private confirmRemoveCustom(wishId: string): void {
    if (wishId.length === 0) {
      return;
    }
    const wish: MagicWish | undefined = this.findLocal(wishId);
    if (wish === undefined) {
      return;
    }
    promptAction.showDialog({
      title: '删除该愿望？',
      message: `「${wish.displayName}」将从愿望单中移除，已记录的兑换历史不受影响。`,
      buttons: [
        { text: '取消', color: '#888888' },
        { text: '删除', color: '#E63946' },
      ],
    }).then((confirm: promptAction.ShowDialogSuccessResponse): void => {
      // promptAction returns index 0 for the first button (取消), 1 for 删除.
      if (confirm.index !== 1) {
        this.pendingWishId = '';
        return;
      }
      const ok: boolean = this.store.removeCustomWish(wishId);
      if (!ok) {
        promptAction.showToast({ message: '删除失败', duration: 1500 });
      }
      this.refresh();
      this.pendingWishId = '';
    }).catch((err: BusinessError): void => {
      console.error(`WishlistPage.confirmRemove failed: ${JSON.stringify(err)}`);
      this.pendingWishId = '';
    });
  }

  private redeemNow(wishId: string): void {
    if (wishId.length === 0) {
      return;
    }
    const wish: MagicWish | undefined = this.findLocal(wishId);
    if (wish === undefined) {
      return;
    }
    const coinOk: boolean = this.coins.redeem(wish.id, wish.costCoins);
    if (!coinOk) {
      console.warn(`WishlistPage.redeemNow coin redeem refused for ${wishId}`);
      this.refresh();
      this.pendingWishId = '';
      return;
    }
    const stateOk: boolean = this.store.markConfirmed(wish.id, Date.now());
    if (!stateOk) {
      console.warn(`WishlistPage.redeemNow markConfirmed refused for ${wishId}`);
      // CoinAccount has already debited; refresh anyway so the user
      // sees the new balance and stale Confirmed state if any.
      this.refresh();
      this.pendingWishId = '';
      return;
    }
    this.history.add(this.makeRecord(wish, Date.now()));
    this.refresh();
    this.showGiftBoxModal();
    this.scheduleAcknowledge(wish.id);
    this.pendingWishId = '';
  }

  private makeRecord(wish: MagicWish, nowMs: number): RedemptionRecord {
    const r: RedemptionRecord = new RedemptionRecord();
    r.id = `${nowMs}-${Math.floor(Math.random() * 65536).toString(16)}`;
    r.ts = nowMs;
    r.wishId = wish.id;
    r.displayName = wish.displayName;
    r.iconEmoji = wish.iconEmoji;
    r.costCoins = wish.costCoins;
    return r;
  }

  private showGiftBoxModal(): void {
    // Two-step: mount the modal first, then increment trigger on the
    // next tick so GiftBox's `@Watch('onTriggerChanged')` actually
    // fires (a freshly-mounted instance sees its prop as the initial
    // value, not as a change, so an increment must happen *after*
    // aboutToAppear). The 60ms gap covers ArkUI's initial layout
    // pass without being perceptible to the user.
    this.giftBoxVisible = true;
    setTimeout((): void => {
      this.giftBoxTrigger = this.giftBoxTrigger + 1;
    }, 60);
    setTimeout((): void => {
      this.giftBoxVisible = false;
    }, GIFTBOX_MODAL_TOTAL_MS);
  }

  private scheduleAcknowledge(wishId: string): void {
    setTimeout((): void => {
      this.store.acknowledge(wishId);
      this.refresh();
    }, GIFTBOX_MODAL_TOTAL_MS + ACK_DELAY_MS);
  }

  private findLocal(wishId: string): MagicWish | undefined {
    for (let i = 0; i < this.wishes.length; i++) {
      if (this.wishes[i].id === wishId) {
        return this.wishes[i];
      }
    }
    return undefined;
  }
}
