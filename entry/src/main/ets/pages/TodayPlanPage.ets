import { router } from '@kit.ArkUI';
import { BusinessError } from '@ohos.base';
import { common } from '@kit.AbilityKit';
import { WordRepository } from '../services/WordRepository';
import { getLearningRecorder, LearningRecorder } from '../services/LearningRecorder';
import { ADVENTURE_REGIONS, DEFAULT_REGION_ID, getRegionById } from '../data/AdventureCatalog';
import { AdventureRegion, WordSource } from '../models/AdventureRegion';
import { TODAY_REGION_ID_KEY } from '../models/GameConfig';
import {
  TodayPlanService,
  TodayPlanView,
  TodayPlanRow,
  describeMemoryState,
  describeWordSource,
} from '../services/TodayPlanService';

/**
 * V0.4.4 — read-only daily plan page. Shows the kid (and any parent
 * peering over their shoulder) which words today's adventure will
 * exercise, grouped by role (复习 / 学习 / 新词) and decorated with
 * a ✓ once the word has been answered correctly today.
 *
 * Empty state: a small empty-message line; we never crash on a
 * missing region or empty repo, since this is a visibility tool —
 * a blank list is a legitimate state for a brand-new install.
 *
 * ArkUI reactivity note (carried over from MonsterCodexPage):
 * @Builder bodies are parameter-less; they read @State directly so
 * ArkUI's dependency tracker re-renders correctly when the view
 * state lands.
 */
@Entry
@Component
struct TodayPlanPage {
  @State private regionDisplayName: string = '';
  @State private dayKey: string = '';
  @State private reviewRows: TodayPlanRow[] = [];
  @State private learningRows: TodayPlanRow[] = [];
  @State private newRows: TodayPlanRow[] = [];
  @State private totalCount: number = 0;
  @State private doneCount: number = 0;
  @State private loaded: boolean = false;

  aboutToAppear(): void {
    const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    const repo: WordRepository = new WordRepository();
    repo.loadFromRawfile(ctx).then((): void => {
      const recorder: LearningRecorder = getLearningRecorder();
      recorder.init(ctx).then((): void => {
        this.populateView(repo, recorder);
      }).catch((err: BusinessError): void => {
        console.error(`TodayPlanPage: recorder.init failed: ${JSON.stringify(err)}`);
        // Fall back to a recorder-less view so an init failure
        // doesn't strand the page on a permanent loading screen.
        this.populateView(repo, recorder);
      });
    }).catch((err: BusinessError): void => {
      console.error(`TodayPlanPage: loadFromRawfile failed: ${JSON.stringify(err)}`);
      this.loaded = true;
    });
  }

  private populateView(repo: WordRepository, recorder: LearningRecorder): void {
    const region: AdventureRegion = this.resolveRegion();
    const view: TodayPlanView =
      new TodayPlanService().build(region, repo, recorder, Date.now());
    this.regionDisplayName = view.regionDisplayName;
    this.dayKey = view.dayKey;
    this.reviewRows = view.review;
    this.learningRows = view.learning;
    this.newRows = view.freshNew;
    this.totalCount = view.total();
    this.doneCount = view.doneCount();
    this.loaded = true;
  }

  private resolveRegion(): AdventureRegion {
    const stored: string | undefined = AppStorage.get<string>(TODAY_REGION_ID_KEY);
    const id: string = stored !== undefined ? stored : DEFAULT_REGION_ID;
    return getRegionById(id);
  }

  build() {
    Column() {
      this.topBar();
      Scroll() {
        Column({ space: 12 }) {
          this.headerCard();
          if (this.loaded && this.totalCount === 0) {
            this.emptyState();
          }
          if (this.reviewRows.length > 0) {
            this.bucketSection('复习', WordSource.Review, this.reviewRows);
          }
          if (this.learningRows.length > 0) {
            this.bucketSection('学习中', WordSource.Learning, this.learningRows);
          }
          if (this.newRows.length > 0) {
            this.bucketSection('新词', WordSource.New, this.newRows);
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 24 });
      }
      .layoutWeight(1)
      .scrollBar(BarState.Auto);
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F8F9FA');
  }

  @Builder
  private topBar() {
    Row() {
      Button('←')
        .id('TodayPlanBackButton')
        .type(ButtonType.Circle)
        .width(40)
        .height(40)
        .fontSize(20)
        .fontColor('#1D3557')
        .backgroundColor('#FFFFFF')
        .onClick((): void => {
          router.back();
        });

      Text('今日学习计划')
        .id('TodayPlanTitle')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1D3557')
        .layoutWeight(1)
        .textAlign(TextAlign.Center);

      // V0.4.5: report entry. Pairs with TodayPlanPage as the
      // "what to learn / how am I doing" duo so HomePage's toolbar
      // budget stays at 5 buttons.
      Button('📊')
        .id('TodayPlanReportButton')
        .type(ButtonType.Circle)
        .width(40)
        .height(40)
        .fontSize(20)
        .backgroundColor('#FFFFFF')
        .onClick((): void => {
          router.pushUrl({ url: 'pages/LearningReportPage' }).catch((err: BusinessError): void => {
            console.error(`TodayPlanPage: pushUrl LearningReportPage failed: ${JSON.stringify(err)}`);
          });
        });
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 16, bottom: 12 });
  }

  @Builder
  private headerCard() {
    Column({ space: 6 }) {
      Row() {
        Text(this.regionDisplayName)
          .id('TodayPlanRegionName')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor('#3F2F1A');
        Blank();
        Text(this.dayKey)
          .id('TodayPlanDayKey')
          .fontSize(14)
          .fontColor('#7B7B7B');
      }
      .width('100%');

      Text(`今天的计划：${this.doneCount} / ${this.totalCount} 已完成`)
        .id('TodayPlanProgressText')
        .fontSize(16)
        .fontColor('#5A4A35');
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#FFFFFF')
    .borderRadius(16)
    .border({ width: 1, color: '#E0E0E0' });
  }

  @Builder
  private emptyState() {
    Column() {
      Text('今天没有可以学习的单词，先去玩一局冒险吧！')
        .id('TodayPlanEmptyText')
        .fontSize(15)
        .fontColor('#7B7B7B')
        .textAlign(TextAlign.Center);
    }
    .width('100%')
    .padding({ top: 32, bottom: 32 });
  }

  /**
   * Renders one bucketed section. ArkUI restricts @Builder to
   * positional value parameters; we pass `title`, the WordSource
   * key (used to drive the chip colour), and the row list. The
   * row list is `@State`-backed so updates inside ForEach still
   * propagate.
   */
  @Builder
  private bucketSection(title: string, source: WordSource, rows: TodayPlanRow[]) {
    Column({ space: 8 }) {
      Row() {
        Text(title)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1D3557');
        Blank();
        Text(`${rows.length}`)
          .fontSize(14)
          .fontColor('#7B7B7B');
      }
      .width('100%');

      ForEach(rows, (row: TodayPlanRow): void => {
        this.rowItem(row, source);
      }, (row: TodayPlanRow): string => `plan-${source}-${row.wordId}`);
    }
    .width('100%')
    .id(this.idForSection(source));
  }

  private idForSection(source: WordSource): string {
    if (source === WordSource.Review) return 'TodayPlanReviewSection';
    if (source === WordSource.Learning) return 'TodayPlanLearningSection';
    return 'TodayPlanNewSection';
  }

  @Builder
  private rowItem(row: TodayPlanRow, source: WordSource) {
    Row({ space: 8 }) {
      Column({ space: 4 }) {
        Row({ space: 6 }) {
          Text(row.word)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1D3557');
          if (row.doneToday) {
            Text('✓')
              .id(`TodayPlanRowDone-${row.wordId}`)
              .fontSize(14)
              .fontColor('#2A9D8F')
              .backgroundColor('#DCF7F2')
              .borderRadius(10)
              .padding({ left: 8, right: 8, top: 2, bottom: 2 });
          }
        }
        .width('100%');

        Text(row.meaningZh)
          .fontSize(13)
          .fontColor('#5A4A35');
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start);

      Text(describeWordSource(source))
        .fontSize(12)
        .fontColor('#FFFFFF')
        .backgroundColor(this.colorForSource(source))
        .borderRadius(10)
        .padding({ left: 8, right: 8, top: 2, bottom: 2 });

      Text(describeMemoryState(row.memoryState))
        .fontSize(12)
        .fontColor('#3F2F1A')
        .backgroundColor('#FFE7B5')
        .borderRadius(10)
        .padding({ left: 8, right: 8, top: 2, bottom: 2 });
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#FFFFFF')
    .borderRadius(12)
    .border({ width: 1, color: '#E0E0E0' });
  }

  private colorForSource(source: WordSource): string {
    if (source === WordSource.Review) return '#E63946';
    if (source === WordSource.Learning) return '#457B9D';
    return '#2A9D8F';
  }
}
