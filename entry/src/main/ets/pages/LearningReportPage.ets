import { router } from '@kit.ArkUI';
import { BusinessError } from '@ohos.base';
import { common } from '@kit.AbilityKit';
import { WordRepository } from '../services/WordRepository';
import { WordPackBootstrapper, BootstrapDeps } from '../services/WordPackBootstrapper';
import { getLearningRecorder, LearningRecorder } from '../services/LearningRecorder';
import {
  LearningReportBuilder,
  LearningReport,
  CategoryReport,
} from '../services/LearningReportBuilder';

/**
 * V0.4.5 — local learning report. Pure read-only view of:
 *   - overall accuracy (correct / seen)
 *   - mastered word count
 *   - today's review completion (done-today / due)
 *   - per-category breakdown + weakest 1-3 categories
 *
 * No persistence here; the source of truth is `LearningRecorder`.
 * No charts in this version — V0.4.5 lays the groundwork; richer
 * visuals (trend lines, heatmaps) are future-V0.4.x work.
 */
@Entry
@Component
struct LearningReportPage {
  @State private accuracyPct: number = 0;
  @State private totalSeen: number = 0;
  @State private totalCorrect: number = 0;
  @State private masteredCount: number = 0;
  @State private familiarCount: number = 0;
  @State private learningCount: number = 0;
  @State private newCount: number = 0;
  @State private reviewDoneTodayCount: number = 0;
  @State private reviewDueCount: number = 0;
  @State private reviewCompletionPct: number = 0;
  @State private categories: CategoryReport[] = [];
  @State private weakCategories: CategoryReport[] = [];
  @State private loaded: boolean = false;

  aboutToAppear(): void {
    const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    WordPackBootstrapper.forContext(ctx).then(async (deps: BootstrapDeps): Promise<void> => {
      const repo: WordRepository = await new WordPackBootstrapper().bootstrap(deps);
      const recorder: LearningRecorder = getLearningRecorder();
      recorder.init(ctx).then((): void => {
        this.populateView(repo, recorder);
      }).catch((err: BusinessError): void => {
        console.error(`LearningReportPage: recorder.init failed: ${JSON.stringify(err)}`);
        this.populateView(repo, recorder);
      });
    }).catch((err: BusinessError): void => {
      console.error(`LearningReportPage: bootstrap failed: ${JSON.stringify(err)}`);
      this.loaded = true;
    });
  }

  private populateView(repo: WordRepository, recorder: LearningRecorder): void {
    const report: LearningReport =
      new LearningReportBuilder().build(repo, recorder, Date.now());
    this.accuracyPct = report.accuracyPct;
    this.totalSeen = report.totalSeen;
    this.totalCorrect = report.totalCorrect;
    this.masteredCount = report.masteredCount;
    this.familiarCount = report.familiarCount;
    this.learningCount = report.learningCount;
    this.newCount = report.newCount;
    this.reviewDoneTodayCount = report.reviewDoneTodayCount;
    this.reviewDueCount = report.reviewDueCount;
    this.reviewCompletionPct = report.reviewCompletionPct;
    this.categories = report.categories;
    this.weakCategories = report.weakCategories;
    this.loaded = true;
  }

  build() {
    Column() {
      this.topBar();
      Scroll() {
        Column({ space: 12 }) {
          this.accuracyCard();
          this.statesCard();
          this.reviewCard();
          if (this.weakCategories.length > 0) {
            this.weakCard();
          }
          this.categoryBreakdown();
          if (this.loaded && this.totalSeen === 0) {
            this.emptyState();
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
        .id('LearningReportBackButton')
        .type(ButtonType.Circle)
        .width(40)
        .height(40)
        .fontSize(20)
        .fontColor('#1D3557')
        .backgroundColor('#FFFFFF')
        .onClick((): void => {
          router.back();
        });

      Text('学习报告')
        .id('LearningReportTitle')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1D3557')
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
        .margin({ right: 40 });
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 16, bottom: 12 });
  }

  @Builder
  private accuracyCard() {
    Column({ space: 6 }) {
      Text('总正确率')
        .fontSize(14)
        .fontColor('#7B7B7B');
      Text(`${this.accuracyPct}%`)
        .id('LearningReportAccuracy')
        .fontSize(40)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1D3557');
      Text(`已答 ${this.totalCorrect} / ${this.totalSeen} 题`)
        .id('LearningReportAccuracySub')
        .fontSize(14)
        .fontColor('#5A4A35');
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#FFFFFF')
    .borderRadius(16)
    .alignItems(HorizontalAlign.Start)
    .border({ width: 1, color: '#E0E0E0' });
  }

  @Builder
  private statesCard() {
    Column({ space: 8 }) {
      Text('单词掌握情况')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1D3557');
      Row({ space: 8 }) {
        this.statePill('掌握', this.masteredCount, '#2A9D8F', 'LearningReportMastered');
        this.statePill('熟悉', this.familiarCount, '#457B9D', 'LearningReportFamiliar');
        this.statePill('学习中', this.learningCount, '#E9C46A', 'LearningReportLearning');
        this.statePill('新词', this.newCount, '#A8DADC', 'LearningReportNewCount');
      }
      .width('100%');
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#FFFFFF')
    .borderRadius(16)
    .alignItems(HorizontalAlign.Start)
    .border({ width: 1, color: '#E0E0E0' });
  }

  @Builder
  private statePill(label: string, value: number, color: string, id: string) {
    Column({ space: 4 }) {
      Text(`${value}`)
        .id(id)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF');
      Text(label)
        .fontSize(12)
        .fontColor('#FFFFFF');
    }
    .layoutWeight(1)
    .padding(12)
    .backgroundColor(color)
    .borderRadius(12)
    .alignItems(HorizontalAlign.Center);
  }

  @Builder
  private reviewCard() {
    Column({ space: 8 }) {
      Row() {
        Text('今日复习进度')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1D3557');
        Blank();
        Text(`${this.reviewDoneTodayCount} / ${Math.max(this.reviewDueCount, this.reviewDoneTodayCount)}`)
          .id('LearningReportReviewCount')
          .fontSize(14)
          .fontColor('#5A4A35');
      }
      .width('100%');
      // Simple progress bar — Stack(background) + foreground sized
      // proportional to completion. ArkUI's <Progress> would also
      // work but the styling story for it is more constrained. We
      // hold the test-id on the outer Stack so the bar stays
      // discoverable even at 0% completion (when the inner Row
      // collapses to zero width and falls out of the visible tree).
      Stack() {
        Row()
          .width('100%')
          .height(12)
          .backgroundColor('#EAEAEA')
          .borderRadius(6);
        Row()
          .width(`${Math.max(1, this.reviewCompletionPct)}%`)
          .height(12)
          .backgroundColor(this.reviewCompletionPct > 0 ? '#2A9D8F' : '#EAEAEA')
          .borderRadius(6);
      }
      .id('LearningReportReviewBar')
      .alignContent(Alignment.Start)
      .width('100%')
      .height(12);
      Text(`${this.reviewCompletionPct}% 完成`)
        .id('LearningReportReviewPct')
        .fontSize(13)
        .fontColor('#5A4A35');
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#FFFFFF')
    .borderRadius(16)
    .alignItems(HorizontalAlign.Start)
    .border({ width: 1, color: '#E0E0E0' });
  }

  @Builder
  private weakCard() {
    Column({ space: 8 }) {
      Text('需要加强的分类')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1D3557');
      ForEach(this.weakCategories, (cat: CategoryReport): void => {
        this.weakRow(cat);
      }, (cat: CategoryReport): string => `weak-${cat.category}`);
    }
    .width('100%')
    .id('LearningReportWeakSection')
    .padding(16)
    .backgroundColor('#FFFFFF')
    .borderRadius(16)
    .alignItems(HorizontalAlign.Start)
    .border({ width: 1, color: '#E0E0E0' });
  }

  @Builder
  private weakRow(cat: CategoryReport) {
    Row() {
      Text(cat.displayName)
        .fontSize(14)
        .fontColor('#1D3557');
      Blank();
      Text(`${cat.accuracyPct}%`)
        .fontSize(14)
        .fontColor(cat.accuracyPct >= 60 ? '#2A9D8F' : '#E63946');
    }
    .width('100%');
  }

  @Builder
  private categoryBreakdown() {
    Column({ space: 8 }) {
      Text('分类详情')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1D3557');
      ForEach(this.categories, (cat: CategoryReport): void => {
        this.categoryRow(cat);
      }, (cat: CategoryReport): string => `cat-${cat.category}`);
    }
    .width('100%')
    .padding(16)
    .id('LearningReportCategorySection')
    .backgroundColor('#FFFFFF')
    .borderRadius(16)
    .alignItems(HorizontalAlign.Start)
    .border({ width: 1, color: '#E0E0E0' });
  }

  @Builder
  private categoryRow(cat: CategoryReport) {
    Row() {
      Text(cat.displayName)
        .fontSize(14)
        .fontColor('#1D3557');
      Blank();
      Text(`${cat.totalCorrect} / ${cat.totalSeen}`)
        .fontSize(13)
        .fontColor('#5A4A35')
        .margin({ right: 12 });
      Text(cat.totalSeen > 0 ? `${cat.accuracyPct}%` : '—')
        .fontSize(13)
        .fontColor('#5A4A35');
    }
    .width('100%');
  }

  @Builder
  private emptyState() {
    Column() {
      Text('还没有学习记录，先去玩一局冒险吧！')
        .id('LearningReportEmptyText')
        .fontSize(14)
        .fontColor('#7B7B7B')
        .textAlign(TextAlign.Center);
    }
    .width('100%')
    .padding({ top: 16, bottom: 16 });
  }
}
