import { router } from '@kit.ArkUI';
import { BusinessError } from '@ohos.base';
import { common } from '@kit.AbilityKit';
import { MagicWish } from '../models/MagicWish';
import { CoinSnapshot } from '../models/CoinSnapshot';
import { WishlistStore, getWishlistStore } from '../services/WishlistStore';
import { CoinAccount, getCoinAccount } from '../services/CoinAccount';
import { WishCard } from '../components/WishCard';

/** Auto-acknowledge delay after parent confirmation. */
const ACK_DELAY_MS: number = 1500;

/**
 * WishlistPage — child-facing list of magic wishes. Tapping
 * "申请兑换" moves a wish to Pending; the ParentLongPressGate
 * inside the WishCard fires onParentConfirm after a 3s hold,
 * which redeems through CoinAccount and shows "已兑换" briefly
 * before recycling the card back to Idle.
 */
@Entry
@Component
struct WishlistPage {
  @State private wishes: MagicWish[] = [];
  @State private balance: number = 0;
  private store: WishlistStore = getWishlistStore();
  private coins: CoinAccount = getCoinAccount();

  aboutToAppear(): void {
    const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    Promise.all<void>([this.coins.init(ctx), this.store.init(ctx)])
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

  build(): void {
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
            WishCard({
              wish: w,
              balance: this.balance,
              onApply: (id: string): void => {
                this.onApply(id);
              },
              onParentConfirm: (id: string): void => {
                this.onParentConfirm(id);
              },
            });
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
  }

  @Builder
  private headerRow() {
    Row() {
      Button('← 返回')
        .id('WishlistBackButton')
        .type(ButtonType.Normal)
        .backgroundColor(Color.Transparent)
        .fontColor('#457B9D')
        .onClick((): void => {
          try {
            router.back();
          } catch (err) {
            console.error(`WishlistPage.back failed: ${JSON.stringify(err as BusinessError)}`);
          }
        });
      Blank()
        .layoutWeight(1);
      Text(`我的魔法币: ${this.balance} ✨`)
        .id('WishlistBalance')
        .fontSize(16)
        .fontColor('#FFB400');
    }
    .width('100%');
  }

  private refresh(): void {
    this.wishes = this.store.list();
    const snap: CoinSnapshot = this.coins.snapshot();
    this.balance = snap.totalCoins - snap.spentCoins;
  }

  private onApply(wishId: string): void {
    const ok: boolean = this.store.request(wishId, this.coins, Date.now());
    if (!ok) {
      console.warn(`WishlistPage.onApply rejected for ${wishId}`);
    }
    this.refresh();
  }

  private onParentConfirm(wishId: string): void {
    const ok: boolean = this.store.confirmByParent(wishId, this.coins, Date.now());
    if (!ok) {
      console.warn(`WishlistPage.onParentConfirm rejected for ${wishId}`);
      this.refresh();
      return;
    }
    this.refresh();
    setTimeout((): void => {
      this.store.acknowledge(wishId);
      this.refresh();
    }, ACK_DELAY_MS);
  }
}
