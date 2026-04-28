import { describeMonsterKind } from '../services/TodayAdventureBuilder';
import { AdventureRegion, MonsterSlot } from '../models/AdventureRegion';

/**
 * AdventureCard — HomePage's "今日冒险" preview card. Pure-display:
 * the parent supplies the region and a badge ("已完成" / "今日"),
 * the card emits onTap when the player commits.
 */
@Component
export struct AdventureCard {
  @Prop region: AdventureRegion = new AdventureRegion();
  @Prop completedToday: boolean = false;
  onTap: () => void = (): void => {};

  build(): void {
    Column({ space: 10 }) {
      Row() {
        Text(this.region.displayName)
          .id('AdventureCardTitle')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor('#3F2F1A');
        Blank();
        Text(this.completedToday ? '已完成' : '今日')
          .id('AdventureCardBadge')
          .fontSize(14)
          .fontColor(this.completedToday ? '#7B7B7B' : '#FFFFFF')
          .backgroundColor(this.completedToday ? '#E5E5E5' : '#E63946')
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .borderRadius(12);
      }
      .width('100%');

      Row({ space: 8 }) {
        ForEach(this.region.monsterPlan.slots, (slot: MonsterSlot): void => {
          Text(describeMonsterKind(slot.kind))
            .fontSize(13)
            .fontColor('#3F2F1A')
            .backgroundColor('#FFE7B5')
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .borderRadius(10);
        }, (slot: MonsterSlot, index: number): string => `slot-${index}-${slot.kind}`);
      }
      .width('100%');

      Text('今天的冒险包含 5 关卡，含拼写、复习与首领关')
        .fontSize(14)
        .fontColor('#5A4A35');

      Button(this.completedToday ? '再战一局' : '开始今日冒险')
        .id('AdventureCardCta')
        .fontSize(18)
        .width('100%')
        .height(48)
        .backgroundColor('#E63946')
        .fontColor('#FFFFFF')
        .onClick((): void => {
          this.onTap();
        });
    }
    .id('AdventureCard')
    .width('100%')
    .padding(16)
    .backgroundColor(this.region.bgPrimary)
    .borderRadius(20)
    .border({ width: 1, color: this.region.bgAccent });
  }
}
