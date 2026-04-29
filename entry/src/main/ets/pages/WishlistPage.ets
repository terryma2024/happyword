import { router } from '@kit.ArkUI';
import { BusinessError } from '@ohos.base';
import { common } from '@kit.AbilityKit';
import { MagicWish, WishState } from '../models/MagicWish';
import { CoinSnapshot } from '../models/CoinSnapshot';
import { WishlistStore, getWishlistStore } from '../services/WishlistStore';
import { CoinAccount, getCoinAccount } from '../services/CoinAccount';
import { ParentLongPressGate } from '../components/ParentLongPressGate';

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
          // ArkUI reactivity note (v0.3.6 letter-spacing lesson, also seen
          // when "申请兑换" silently no-op'd in v0.3.8): a parameterised
          // @Builder body (e.g. `wishCard(wish: MagicWish)` reading
          // `wish.state`) is NOT re-evaluated when the parameter object's
          // properties change, because ArkUI's compile-time dependency
          // analysis only tracks @State reads inside the Builder body's
          // source. The cell stays frozen on its initial branch.
          //
          // Workaround: inline the per-cell layout + state-driven if/else
          // directly inside the ForEach iterator lambda. ForEach's diff
          // (keyed by w.id) re-runs the lambda for each item every time
          // `this.wishes` is reassigned in `refresh()`, so the new item
          // value (with updated `state`) drives a fresh sub-tree. No
          // nested @Builder hop, no stale capture.
          ForEach(this.wishes, (w: MagicWish): void => {
            Column({ space: 8 }) {
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
                .alignItems(HorizontalAlign.Start);
              }
              .width('100%')
              .alignItems(VerticalAlign.Center);

              if (w.state === WishState.Idle) {
                if (this.balance >= w.costCoins) {
                  Button('申请兑换')
                    .id(`WishApply_${w.id}`)
                    .width(140)
                    .height(40)
                    .backgroundColor('#E63946')
                    .fontColor('#FFFFFF')
                    .onClick((): void => {
                      this.onApply(w.id);
                    });
                } else {
                  Text(`还差 ${w.costCoins - this.balance} ✨`)
                    .id(`WishGap_${w.id}`)
                    .fontSize(13)
                    .fontColor('#888888');
                }
              } else if (w.state === WishState.Pending) {
                Column({ space: 4 }) {
                  Text('等待家长确认 ⏳')
                    .fontSize(13)
                    .fontColor('#457B9D');
                  ParentLongPressGate({
                    label: '长按 3 秒由家长确认',
                    onConfirm: (): void => {
                      this.onParentConfirm(w.id);
                    },
                  });
                }
                .alignItems(HorizontalAlign.Center);
              } else {
                Text('已兑换 ✓')
                  .id(`WishConfirmed_${w.id}`)
                  .fontSize(14)
                  .fontColor('#2ECC71');
              }
            }
            .id(`WishCard_${w.id}`)
            .width('92%')
            .padding({ left: 16, right: 16, top: 12, bottom: 12 })
            .backgroundColor('#FFFFFF')
            .borderRadius(14)
            .shadow({ radius: 8, color: '#11000000', offsetX: 0, offsetY: 2 });
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
