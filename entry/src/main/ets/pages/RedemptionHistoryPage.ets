import { BusinessError } from '@ohos.base';
import { common } from '@kit.AbilityKit';
import {
  RedemptionRecord,
  formatLocalTimestamp,
} from '../models/RedemptionRecord';
import {
  RedemptionHistoryStore,
  getRedemptionHistoryStore,
} from '../services/RedemptionHistoryStore';

/**
 * V0.3.9: history of every successful wishlist redemption. Reached
 * from the 📜 button on WishlistPage. Newest record first
 * (RedemptionHistoryStore returns ts-desc), capped at
 * REDEMPTION_HISTORY_CAP entries (oldest shifted out by the store).
 *
 * Read-only — no edit / delete / search per spec §9.3 ("history
 * is read-only, cap 50 滚动"). Empty state renders a single line
 * pointing the parent back to the wishlist.
 */
@Entry
@Component
struct RedemptionHistoryPage {
  @State private records: RedemptionRecord[] = [];
  private store: RedemptionHistoryStore = getRedemptionHistoryStore();

  aboutToAppear(): void {
    const ctx: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.store.init(ctx)
      .then((): void => {
        this.records = this.store.list();
      })
      .catch((err: BusinessError): void => {
        console.error(`RedemptionHistoryPage init failed: ${JSON.stringify(err)}`);
        this.records = this.store.list();
      });
  }

  onPageShow(): void {
    this.records = this.store.list();
  }

  build(): void {
    Column({ space: 12 }) {
      this.headerRow();
      Text('兑换记录')
        .id('RedemptionHistoryTitle')
        .fontSize(26)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1D3557');

      if (this.records.length === 0) {
        Column() {
          Text('还没有兑换记录')
            .id('RedemptionHistoryEmpty')
            .fontSize(16)
            .fontColor('#888888');
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center);
      } else {
        Scroll() {
          Column({ space: 10 }) {
            ForEach(this.records, (r: RedemptionRecord): void => {
              this.recordCardInline(r);
            }, (r: RedemptionRecord): string => r.id);
          }
          .padding({ top: 8, bottom: 24 });
        }
        .layoutWeight(1);
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: 24 })
    .backgroundColor('#F8F9FA');
  }

  @Builder
  private recordCardInline(r: RedemptionRecord) {
    Row() {
      Text(r.iconEmoji)
        .fontSize(28);
      Column({ space: 4 }) {
        Text(r.displayName)
          .id(`RedemptionRecordName_${r.id}`)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor('#1D3557');
        Text(formatLocalTimestamp(r.ts))
          .id(`RedemptionRecordTime_${r.id}`)
          .fontSize(13)
          .fontColor('#888888');
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .padding({ left: 12 });
      Text(`-${r.costCoins} ✨`)
        .id(`RedemptionRecordCost_${r.id}`)
        .fontSize(15)
        .fontColor('#E63946');
    }
    .id(`RedemptionRecordCard_${r.id}`)
    .width('92%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor('#FFFFFF')
    .borderRadius(12)
    .alignItems(VerticalAlign.Center)
    .shadow({ radius: 6, color: '#11000000', offsetX: 0, offsetY: 2 });
  }

  @Builder
  private headerRow() {
    Row() {
      Button('← 返回')
        .id('RedemptionHistoryBackButton')
        .type(ButtonType.Normal)
        .backgroundColor(Color.Transparent)
        .fontColor('#457B9D')
        .onClick((): void => {
          try {
            this.getUIContext().getRouter().back();
          } catch (err) {
            console.error(`RedemptionHistoryPage.back failed: ${JSON.stringify(err as BusinessError)}`);
          }
        });
      Blank()
        .layoutWeight(1);
    }
    .width('100%');
  }
}
