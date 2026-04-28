import { MagicWish, WishState } from '../models/MagicWish';
import { ParentLongPressGate } from './ParentLongPressGate';

/**
 * WishCard — single wish row used by WishlistPage. Three visible
 * states drive the bottom slot:
 *   Idle      — Either "申请兑换" button (balance OK) or a "还差 N ✨"
 *               hint that shows how much more the child needs.
 *   Pending   — A ParentLongPressGate that fires onParentConfirm
 *               after a 3-second hold.
 *   Confirmed — Static "已兑换 ✓" badge until WishlistPage calls
 *               WishlistStore.acknowledge to recycle it back to Idle.
 */
@Component
export struct WishCard {
  @Prop wish: MagicWish = new MagicWish();
  @Prop balance: number = 0;
  onApply: (wishId: string) => void = (_id: string): void => {};
  onParentConfirm: (wishId: string) => void = (_id: string): void => {};

  build(): void {
    Column({ space: 8 }) {
      Row({ space: 12 }) {
        Text(this.wish.iconEmoji)
          .fontSize(32);
        Column({ space: 4 }) {
          Text(this.wish.displayName)
            .id(`WishName_${this.wish.id}`)
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor('#1D3557');
          Text(`${this.wish.costCoins} ✨`)
            .fontSize(14)
            .fontColor('#FFB400');
        }
        .alignItems(HorizontalAlign.Start);
      }
      .width('100%')
      .alignItems(VerticalAlign.Center);
      this.bottomBuilder();
    }
    .id(`WishCard_${this.wish.id}`)
    .width('92%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor('#FFFFFF')
    .borderRadius(14)
    .shadow({ radius: 8, color: '#11000000', offsetX: 0, offsetY: 2 });
  }

  @Builder
  private bottomBuilder() {
    if (this.wish.state === WishState.Idle) {
      this.idleBottom();
    } else if (this.wish.state === WishState.Pending) {
      this.pendingBottom();
    } else {
      this.confirmedBottom();
    }
  }

  @Builder
  private idleBottom() {
    if (this.balance >= this.wish.costCoins) {
      Button('申请兑换')
        .id(`WishApply_${this.wish.id}`)
        .width(140)
        .height(40)
        .backgroundColor('#E63946')
        .fontColor('#FFFFFF')
        .onClick((): void => {
          this.onApply(this.wish.id);
        });
    } else {
      Text(`还差 ${this.wish.costCoins - this.balance} ✨`)
        .id(`WishGap_${this.wish.id}`)
        .fontSize(13)
        .fontColor('#888888');
    }
  }

  @Builder
  private pendingBottom() {
    Column({ space: 4 }) {
      Text('等待家长确认 ⏳')
        .fontSize(13)
        .fontColor('#457B9D');
      ParentLongPressGate({
        label: '长按 3 秒由家长确认',
        onConfirm: (): void => {
          this.onParentConfirm(this.wish.id);
        },
      });
    }
    .alignItems(HorizontalAlign.Center);
  }

  @Builder
  private confirmedBottom() {
    Text('已兑换 ✓')
      .id(`WishConfirmed_${this.wish.id}`)
      .fontSize(14)
      .fontColor('#2ECC71');
  }
}
