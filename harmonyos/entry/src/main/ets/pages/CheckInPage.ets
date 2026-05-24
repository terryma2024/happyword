import { BusinessError } from '@ohos.base';
import { common } from '@kit.AbilityKit';
import { CheckInSnapshot } from '../models/CheckInSnapshot';
import { CheckInStore, getCheckInStore } from '../services/CheckInStore';
import { PAGE_BODY_EDGE_VP } from '../constants/PageLayoutInsets';
import { PageTopChrome } from '../components/PageTopChrome';
import {
  buildCheckInMonthWeeks,
  CheckInDayCell,
  CheckInWeekRow,
  monthAnchorMs,
  monthLabel,
  monthRowKey,
  shiftMonth,
} from '../services/CheckInCalendarView';

@Entry
@Component
struct CheckInPage {
  private store: CheckInStore = getCheckInStore();
  @State private currentStreak: number = 0;
  @State private bestStreak: number = 0;
  @State private cloudState: string = '本地保存';
  @State private checkedDayKeys: string[] = [];
  @State private latestBonusText: string = '';
  @State private displayedMonthMs: number = monthAnchorMs(Date.now());
  @State private visibleWeeks: CheckInWeekRow[] = buildCheckInMonthWeeks(monthAnchorMs(Date.now()), []);

  aboutToAppear(): void {
    const ctx: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.store.init(ctx).then((): void => {
      this.refreshFromStore();
    }).catch((err: BusinessError): void => {
      console.error(`CheckInPage: CheckInStore.init failed: ${JSON.stringify(err)}`);
      this.refreshFromStore();
    });
  }

  onPageShow(): void {
    this.refreshFromStore();
  }

  private refreshFromStore(): void {
    const snap: CheckInSnapshot = this.store.snapshot();
    this.currentStreak = snap.currentStreak;
    this.bestStreak = snap.bestStreak;
    this.checkedDayKeys = snap.checkedDayKeys.slice();
    this.refreshVisibleWeeks();
    this.latestBonusText = snap.weeklyBonusDayKeys.length > 0
      ? `最近一次连续奖励：${snap.weeklyBonusDayKeys[snap.weeklyBonusDayKeys.length - 1]} +50`
      : '连续 7 天后额外奖励 50 积分';
    if (snap.pendingSync) {
      this.cloudState = '等待同步';
    } else if (snap.lastSyncedAtMs > 0) {
      this.cloudState = '云端已同步';
    } else {
      this.cloudState = '本地保存';
    }
  }

  private showPreviousMonth(): void {
    this.displayedMonthMs = shiftMonth(this.displayedMonthMs, -1);
    this.refreshVisibleWeeks();
  }

  private showNextMonth(): void {
    this.displayedMonthMs = shiftMonth(this.displayedMonthMs, 1);
    this.refreshVisibleWeeks();
  }

  private refreshVisibleWeeks(): void {
    this.visibleWeeks = buildCheckInMonthWeeks(this.displayedMonthMs, this.checkedDayKeys);
  }

  build() {
    Column() {
      PageTopChrome({
        backButtonId: 'CheckInBackButton',
        title: '打卡日历',
        titleId: 'CheckInPageTitle',
        onBack: (): void => {
          this.getUIContext().getRouter().back();
        },
      });

      Scroll() {
        Column({ space: 18 }) {
          Row({ space: 10 }) {
            Column({ space: 4 }) {
              Text(`连续 ${this.currentStreak} 天`)
                .id('CheckInCurrentStreak')
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor('#065F46');
              Text('当前连击')
                .fontSize(12)
                .fontColor('#64748B');
            }
            .layoutWeight(1)
            .padding(14)
            .backgroundColor('#ECFDF5')
            .borderRadius(12);

            Column({ space: 4 }) {
              Text(`${this.bestStreak} 天`)
                .id('CheckInBestStreak')
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor('#7C2D12');
              Text('最佳连续')
                .fontSize(12)
                .fontColor('#64748B');
            }
            .layoutWeight(1)
            .padding(14)
            .backgroundColor('#FFF7ED')
            .borderRadius(12);

            Column({ space: 4 }) {
              Text(this.cloudState)
                .id('CheckInCloudState')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor('#1D4ED8');
              Text('同步状态')
                .fontSize(12)
                .fontColor('#64748B');
            }
            .layoutWeight(1)
            .padding(14)
            .backgroundColor('#EFF6FF')
            .borderRadius(12);
          }
          .width('100%');

          Text(this.latestBonusText)
            .id('CheckInWeeklyBonusBanner')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor('#92400E')
            .width('100%')
            .padding({ left: 14, right: 14, top: 10, bottom: 10 })
            .backgroundColor('#FEF3C7')
            .borderRadius(12);

          Column({ space: 8 }) {
            Row({ space: 12 }) {
              Button({ type: ButtonType.Circle, stateEffect: true }) {
                Text('←')
                  .fontSize(18)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#065F46');
              }
                .id('CheckInPrevMonthButton')
                .width(36)
                .height(36)
                .backgroundColor('#DCFCE7')
                .onClick((): void => {
                  this.showPreviousMonth();
                });

              Text(monthLabel(this.displayedMonthMs))
                .id('CheckInMonthLabel')
                .layoutWeight(1)
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor('#0F172A')
                .textAlign(TextAlign.Center);

              Button({ type: ButtonType.Circle, stateEffect: true }) {
                Text('→')
                  .fontSize(18)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#065F46');
              }
                .id('CheckInNextMonthButton')
                .width(36)
                .height(36)
                .backgroundColor('#DCFCE7')
                .onClick((): void => {
                  this.showNextMonth();
                });
            }
            .width('100%')
            .alignItems(VerticalAlign.Center);

            Row() {
              ForEach(['日', '一', '二', '三', '四', '五', '六'], (label: string): void => {
                Text(label)
                  .fontSize(12)
                  .fontColor('#64748B')
                  .fontWeight(FontWeight.Medium)
                  .textAlign(TextAlign.Center)
                  .layoutWeight(1);
              }, (label: string): string => label)
            }
            .width('100%');

            ForEach(this.visibleWeeks, (week: CheckInWeekRow, rowIndex: number): void => {
              Row({ space: 6 }) {
                ForEach(week.cells, (cell: CheckInDayCell, colIndex: number): void => {
                  Text(cell.inMonth ? (cell.checked ? `${cell.label} ✓` : cell.label) : '')
                    .id(cell.inMonth ? `CheckInDay_${cell.dayKey}` : `CheckInBlank_${rowIndex}_${colIndex}`)
                    .fontSize(13)
                    .fontWeight(cell.checked ? FontWeight.Bold : FontWeight.Regular)
                    .fontColor(cell.checked ? '#FFFFFF' : '#334155')
                    .textAlign(TextAlign.Center)
                    .height(38)
                    .layoutWeight(1)
                    .backgroundColor(cell.checked ? '#22C55E' : (cell.inMonth ? '#F8FAFC' : '#FFFFFF'))
                    .borderRadius(10);
                }, (cell: CheckInDayCell, colIndex: number): string => {
                  return cell.inMonth ? cell.dayKey : `blank-${rowIndex}-${colIndex}`;
                })
              }
              .width('100%');
            }, (_week: CheckInWeekRow, rowIndex: number): string => monthRowKey(this.displayedMonthMs, rowIndex))
          }
          .id('CheckInCalendarGrid')
          .width('100%')
          .padding(12)
          .backgroundColor('#FFFFFF')
          .borderRadius(14);
        }
        .width('100%')
        .padding({
          left: PAGE_BODY_EDGE_VP,
          right: PAGE_BODY_EDGE_VP,
          bottom: PAGE_BODY_EDGE_VP,
        });
      }
      .layoutWeight(1)
      .scrollBar(BarState.Auto);
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F8FAFC')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM,
      SafeAreaEdge.START, SafeAreaEdge.END]);
  }
}
