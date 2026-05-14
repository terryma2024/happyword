import { BusinessError } from '@ohos.base';
import { common } from '@kit.AbilityKit';
import display from '@ohos.display';
import { WordPackBootstrapper, BootstrapDeps } from '../services/WordPackBootstrapper';
import { getLearningRecorder, LearningRecorder } from '../services/LearningRecorder';
import {
  LearningReportBuilder,
  LearningReport,
  PackReport,
} from '../services/LearningReportBuilder';
import {
  HomeIntegrationBundle,
  loadHomeIntegration,
} from '../services/PackHomeIntegration';
import { PageTopChrome } from '../components/PageTopChrome';

/**
 * V0.6.7.8 — local learning report. Pure read-only view of:
 *   - overall accuracy (correct / seen)
 *   - mastered word count
 *   - today's review completion (done-today / due)
 *   - per-pack breakdown table (V0.4.5 keyed reports by category;
 *     V0.6.7.8 rewrites them around the three-layer pack model so
 *     the parent's mental model matches the rest of the app)
 *
 * No persistence here; the source of truth is `LearningRecorder`.
 * No charts in this version — V0.4.5 laid the groundwork; richer
 * visuals (trend lines, heatmaps) remain future work.
 *
 * Responsive layout (added 2026-05-06): on pad-class screens (shorter
 * edge ≥ 600 vp, MatePad/foldable) the cards are capped to ~720 vp
 * and horizontally centred in the scroll viewport so the content
 * doesn't stretch edge-to-edge across the whole tablet. Phones keep
 * the legacy full-width rendering. Mirrors MonsterCodexPage's pad
 * adaptation pattern to keep the visual language consistent.
 */
const PAD_BREAKPOINT_VP: number = 600;
const PAD_CONTENT_WIDTH_VP: number = 720;

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
  @State private packs: PackReport[] = [];
  @State private loaded: boolean = false;
  /**
   * Shorter screen edge in vp. Phone-class default keeps the first
   * frame compact if the display query throws. Mirrors
   * MonsterCodexPage's pad-detection seam.
   */
  @State private shortEdgeVp: number = 360;

  aboutToAppear(): void {
    try {
      const d: display.Display = display.getDefaultDisplaySync();
      const widthVp: number = this.getUIContext().px2vp(d.width);
      const heightVp: number = this.getUIContext().px2vp(d.height);
      this.shortEdgeVp = Math.min(widthVp, heightVp);
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      console.error(`LearningReportPage: display query failed: ${JSON.stringify(e)}`);
      // Keep the phone-class default; the page is still usable.
    }
    const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    // V0.6.7.8: report aggregates per-pack, so we need the same
    // (PackLibrary + PackSelectionService) bundle that HomePage and
    // PackManagerPage already build via loadHomeIntegration. Run
    // bootstrap (recorder hydration deps + word cache warmup) and
    // loadHomeIntegration (library + selection) in parallel — both
    // are idempotent and read the same preferences / rawfile state.
    Promise.all([
      WordPackBootstrapper.forContext(ctx),
      loadHomeIntegration(ctx),
    ]).then((results: [BootstrapDeps, HomeIntegrationBundle]): void => {
      const bundle: HomeIntegrationBundle = results[1];
      const recorder: LearningRecorder = getLearningRecorder();
      recorder.init(ctx).then((): void => {
        this.populateView(bundle, recorder);
      }).catch((err: BusinessError): void => {
        console.error(`LearningReportPage: recorder.init failed: ${JSON.stringify(err)}`);
        this.populateView(bundle, recorder);
      });
    }).catch((err: BusinessError): void => {
      console.error(`LearningReportPage: bootstrap or loadHomeIntegration failed: ${JSON.stringify(err)}`);
      this.loaded = true;
    });
  }

  private isPad(): boolean {
    return this.shortEdgeVp >= PAD_BREAKPOINT_VP;
  }

  /** Width applied to the inner card column. On phones we keep the
   *  legacy full-width behaviour; on pads we cap so cards don't
   *  stretch edge-to-edge across the whole tablet viewport. */
  private contentWidth(): Length {
    return this.isPad() ? PAD_CONTENT_WIDTH_VP : '100%';
  }

  private populateView(bundle: HomeIntegrationBundle, recorder: LearningRecorder): void {
    const report: LearningReport = new LearningReportBuilder().build(
      bundle.library,
      bundle.selection.getActiveIds(),
      recorder,
      Date.now(),
    );
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
    this.packs = report.packs;
    this.loaded = true;
  }

  build() {
    Column() {
      PageTopChrome({
        backButtonId: 'LearningReportBackButton',
        title: '学习报告',
        titleId: 'LearningReportTitle',
        onBack: (): void => {
          this.getUIContext().getRouter().back();
        },
        trailing: (): void => {
          this.learningReportTrailingBalance();
        },
      });
      Scroll() {
        // Outer Column fills the scroll viewport horizontally and
        // alignItems-centers the inner cards Column. On pads
        // `contentWidth()` returns a fixed vp value (< 100% of the
        // landscape MatePad), creating the visual margin; on phones
        // it returns '100%' and the centering is a no-op.
        Column() {
          Column({ space: 12 }) {
            this.accuracyCard();
            this.statesCard();
            this.reviewCard();
            this.packBreakdown();
            if (this.loaded && this.totalSeen === 0) {
              this.emptyState();
            }
          }
          .width(this.contentWidth())
          .padding({ left: 16, right: 16, bottom: 24 });
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center);
      }
      .layoutWeight(1)
      .scrollBar(BarState.Auto);
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F8F9FA')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM,
      SafeAreaEdge.START, SafeAreaEdge.END]);
  }

  @Builder
  private learningReportTrailingBalance(): void {
    Blank().width(40).height(40);
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
  private packBreakdown() {
    Column({ space: 8 }) {
      Text('词包详情')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1D3557');
      ForEach(this.packs, (p: PackReport): void => {
        this.packRow(p);
      }, (p: PackReport): string => `pack-${p.packId}`);
    }
    .width('100%')
    .padding(16)
    .id('LearningReportPackSection')
    .backgroundColor('#FFFFFF')
    .borderRadius(16)
    .alignItems(HorizontalAlign.Start)
    .border({ width: 1, color: '#E0E0E0' });
  }

  @Builder
  private packRow(p: PackReport) {
    Row() {
      Text(p.name)
        .fontSize(14)
        .fontColor('#1D3557');
      Blank();
      Text(`${p.totalCorrect} / ${p.totalSeen}`)
        .fontSize(13)
        .fontColor('#5A4A35')
        .margin({ right: 12 });
      Text(p.totalSeen > 0 ? `${p.accuracyPct}%` : '—')
        .fontSize(13)
        .fontColor('#5A4A35');
    }
    .id(`pack-${p.packId}`)
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
