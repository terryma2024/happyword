import { BusinessError } from '@ohos.base';
import { common } from '@kit.AbilityKit';
import { Pack } from '../models/Pack';
import { WordEntry } from '../models/WordEntry';
import { WordStat } from '../services/WrongAnswerStore';
import { getLearningRecorder, LearningRecorder } from '../services/LearningRecorder';
import { CoinAccount, getCoinAccount } from '../services/CoinAccount';
import {
  HomeIntegrationBundle,
  loadHomeIntegration,
} from '../services/PackHomeIntegration';
import {
  SPELLBOOK_REWARD_COINS,
  SpellbookCard,
  SpellbookCardState,
  SpellbookPackProgress,
  buildSpellbookCards,
  spellbookProgressForPack,
  spellbookRewardTxnId,
} from '../services/SpellbookService';
import {
  SpellbookRewardSnapshot,
  SpellbookRewardStore,
} from '../services/SpellbookRewardStore';
import {
  SpellbookCoverSource,
  SpellbookCoverSourceKind,
  spellbookCoverSourceForPack,
} from '../services/SpellbookCoverResolver';
import {
  CachedSpellbookCover,
  cachedSpellbookCoverPathsForPacks,
} from '../services/SpellbookCoverCache';
import { PageTopChrome } from '../components/PageTopChrome';
import { PAGE_BODY_EDGE_VP } from '../constants/PageLayoutInsets';
import { requestPageOrientation } from '../utils/orientation';

@Entry
@Component
struct SpellbookPage {
  @State private packs: Pack[] = [];
  @State private stats: WordStat[] = [];
  @State private claimedPackIds: string[] = [];
  @State private loading: boolean = true;
  @State private lockedTipText: string = '';
  @State private detailVisible: boolean = false;
  @State private detailWord: WordEntry = new WordEntry();
  @State private detailState: SpellbookCardState = SpellbookCardState.Locked;
  @State private pageVersion: number = 0;
  @State private cachedSpellbookCovers: CachedSpellbookCover[] = [];
  private rewardStore: SpellbookRewardStore = new SpellbookRewardStore();
  private coins: CoinAccount = getCoinAccount();
  private lockedTipTimer: number = -1;

  private applyOrientationPolicy(): void {
    requestPageOrientation(
      this.getUIContext().getHostContext() as common.UIAbilityContext,
      'SpellbookPage',
      (px: number): number => this.getUIContext().px2vp(px),
    );
  }

  aboutToAppear(): void {
    this.applyOrientationPolicy();
    this.loadData();
  }

  onPageShow(): void {
    this.applyOrientationPolicy();
  }

  aboutToDisappear(): void {
    if (this.lockedTipTimer >= 0) {
      clearTimeout(this.lockedTipTimer);
      this.lockedTipTimer = -1;
    }
  }

  private loadData(): void {
    const ctx: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    const recorder: LearningRecorder = getLearningRecorder();
    Promise.all([
      loadHomeIntegration(ctx),
      recorder.init(ctx),
      this.rewardStore.init(ctx),
      this.coins.init(ctx),
    ]).then((values: [HomeIntegrationBundle, void, void, void]): void => {
      const bundle: HomeIntegrationBundle = values[0];
      this.packs = bundle.library.allPacks();
      this.refreshCachedSpellbookCovers(ctx);
      this.stats = recorder.allStats();
      this.rewardStore.load().then((snap: SpellbookRewardSnapshot): void => {
        this.claimedPackIds = snap.claimedPackIds;
        this.loading = false;
        this.pageVersion += 1;
      }).catch((err: BusinessError): void => {
        console.error(`SpellbookPage.rewardStore.load failed: ${JSON.stringify(err)}`);
        this.loading = false;
      });
    }).catch((err: BusinessError): void => {
      console.error(`SpellbookPage.loadData failed: ${JSON.stringify(err)}`);
      this.loading = false;
    });
  }

  private progress(pack: Pack): SpellbookPackProgress {
    return spellbookProgressForPack(pack, this.stats);
  }

  private hasClaimed(packId: string): boolean {
    return this.claimedPackIds.indexOf(packId) >= 0;
  }

  private refreshCachedSpellbookCovers(ctx: common.UIAbilityContext): void {
    cachedSpellbookCoverPathsForPacks(ctx, this.packs).then((items: CachedSpellbookCover[]): void => {
      this.cachedSpellbookCovers = items;
      this.pageVersion += 1;
    }).catch((err: BusinessError): void => {
      console.error(`SpellbookPage.refreshCachedSpellbookCovers failed: ${JSON.stringify(err)}`);
    });
  }

  private cachedSpellbookCoverPath(packId: string): string {
    for (let i = 0; i < this.cachedSpellbookCovers.length; i++) {
      if (this.cachedSpellbookCovers[i].packId === packId) {
        return this.cachedSpellbookCovers[i].path;
      }
    }
    return '';
  }

  private claimReward(pack: Pack): void {
    const progress: SpellbookPackProgress = this.progress(pack);
    if (!progress.complete || this.hasClaimed(pack.id)) {
      return;
    }
    const now: number = Date.now();
    const applied: boolean = this.coins.applyExternalTxn(
      spellbookRewardTxnId(pack.id),
      SPELLBOOK_REWARD_COINS,
      'spellbook_pack_complete',
      now,
    );
    if (!applied) {
      return;
    }
    this.coins.flushNow().then((): Promise<boolean> => {
      return this.rewardStore.claimPackId(pack.id);
    }).then((_claimed: boolean): void => {
      this.claimedPackIds = this.claimedPackIds.concat([pack.id]);
      this.pageVersion += 1;
    }).catch((err: BusinessError): void => {
      console.error(`SpellbookPage.claimReward failed: ${JSON.stringify(err)}`);
    });
  }

  private showLockedTip(word: WordEntry): void {
    if (this.lockedTipTimer >= 0) {
      clearTimeout(this.lockedTipTimer);
    }
    this.lockedTipText = `${word.word} 还没有点亮，去冒险里遇见它吧`;
    this.lockedTipTimer = setTimeout((): void => {
      this.lockedTipText = '';
      this.lockedTipTimer = -1;
    }, 1600);
  }

  private openDetail(card: SpellbookCard): void {
    if (card.state === SpellbookCardState.Locked) {
      this.showLockedTip(card.word);
      return;
    }
    this.detailWord = card.word;
    this.detailState = card.state;
    this.detailVisible = true;
  }

  private stateLabel(state: SpellbookCardState): string {
    if (state === SpellbookCardState.Mastered) return '已掌握';
    if (state === SpellbookCardState.Seen) return '已遇见';
    return '未点亮';
  }

  private cardBackground(state: SpellbookCardState): string {
    if (state === SpellbookCardState.Mastered) return '#FFF6D6';
    if (state === SpellbookCardState.Seen) return '#ECEFF3';
    return '#F3F4F6';
  }

  private cardBorder(state: SpellbookCardState): string {
    if (state === SpellbookCardState.Mastered) return '#F59E0B';
    if (state === SpellbookCardState.Seen) return '#A7B0BD';
    return '#9CA3AF';
  }

  build(): void {
    Stack() {
      Column() {
        PageTopChrome({
          backButtonId: 'SpellbookBackButton',
          title: '魔法书图鉴',
          titleId: 'SpellbookTitle',
          onBack: (): void => {
            this.getUIContext().getRouter().back();
          },
        })
        Scroll() {
          Column({ space: 16 }) {
            if (this.loading) {
              Text('魔法书正在翻页...')
                .fontSize(16)
                .fontColor('#6B7280')
                .margin({ top: 40 });
            } else {
              ForEach(this.packs, (pack: Pack): void => {
                this.packSection(pack);
              }, (pack: Pack): string => pack.id);
            }
          }
          .width('100%')
          .padding({ left: PAGE_BODY_EDGE_VP, right: PAGE_BODY_EDGE_VP, bottom: 32 });
        }
        .layoutWeight(1)
        .width('100%');
      }
      .id('SpellbookPage')
      .width('100%')
      .height('100%')
      .backgroundColor('#F8FAFC')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM,
        SafeAreaEdge.START, SafeAreaEdge.END]);

      if (this.lockedTipText.length > 0) {
        Text(this.lockedTipText)
          .id('SpellbookLockedTip')
          .fontSize(14)
          .fontColor('#FFFFFF')
          .backgroundColor('#CC111827')
          .borderRadius(18)
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .align(Alignment.Top)
          .margin({ top: 96 });
      }

      if (this.detailVisible) {
        this.detailSheet();
      }
    }
  }

  @Builder
  private packSection(pack: Pack) {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        this.coverImage(pack, `SpellbookPackCover_${pack.id}`, 56);
        Column({ space: 4 }) {
          Text(pack.name.length > 0 ? pack.name : pack.id)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1F2937')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
          Text(`${this.progress(pack).mastered} / ${this.progress(pack).total} 已掌握`)
            .id(`SpellbookPackProgress_${pack.id}`)
            .fontSize(13)
            .fontColor('#6B7280');
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start);

        if (this.hasClaimed(pack.id)) {
          Text('已兑换')
            .id(`SpellbookPackRewardClaimed_${pack.id}`)
            .fontSize(13)
            .fontColor('#047857')
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .backgroundColor('#D1FAE5')
            .borderRadius(14);
        } else if (this.progress(pack).complete) {
          Button(`+${SPELLBOOK_REWARD_COINS}`)
            .id(`SpellbookPackRewardButton_${pack.id}`)
            .height(34)
            .width(78)
            .fontSize(13)
            .backgroundColor('#B91C1C')
            .fontColor('#FFFFFF')
            .onClick((): void => this.claimReward(pack));
        } else {
          Text(`+${SPELLBOOK_REWARD_COINS}`)
            .id(`SpellbookPackRewardButton_${pack.id}`)
            .height(34)
            .width(78)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor('#4B5563')
            .backgroundColor('#E5E7EB')
            .borderRadius(17)
            .textAlign(TextAlign.Center);
        }
      }
      .width('100%');

      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
        ForEach(buildSpellbookCards(pack, this.stats), (card: SpellbookCard): void => {
          this.wordCard(card);
        }, (card: SpellbookCard): string => `${card.packId}:${card.word.id}`);
      }
      .width('100%');
    }
    .width('100%')
    .padding(14)
    .backgroundColor('#FFFFFF')
    .borderRadius(8)
    .border({ width: 1, color: '#E5E7EB' });
  }

  @Builder
  private coverImage(pack: Pack, imageId: string, size: number) {
    Stack() {
      if (this.cachedSpellbookCoverPath(pack.id).length > 0) {
        Image(this.cachedSpellbookCoverPath(pack.id))
          .width(size)
          .height(size)
          .objectFit(ImageFit.Contain)
          .syncLoad(true);
      } else if (spellbookCoverSourceForPack(pack).kind === SpellbookCoverSourceKind.RemoteUrl) {
        Image(spellbookCoverSourceForPack(pack).value)
          .width(size)
          .height(size)
          .objectFit(ImageFit.Contain);
      } else {
        Image($rawfile(this.rawCoverAsset(pack)))
          .width(size)
          .height(size)
          .objectFit(ImageFit.Contain)
          .syncLoad(true);
      }
    }
    .id(imageId)
    .width(size)
    .height(size);
  }

  private rawCoverAsset(pack: Pack): string {
    const source: SpellbookCoverSource = spellbookCoverSourceForPack(pack);
    return source.kind === SpellbookCoverSourceKind.Rawfile ? source.value : 'spellbook_covers/default.png';
  }

  @Builder
  private wordCard(card: SpellbookCard) {
    Column({ space: 3 }) {
      Text(card.state === SpellbookCardState.Locked ? '？' : card.word.word)
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor(card.state === SpellbookCardState.Locked ? '#374151' : '#1F2937')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis });
      if (card.state !== SpellbookCardState.Locked) {
        Text(card.word.meaningZh)
          .fontSize(11)
          .fontColor('#6B7280')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
      }
    }
    .id(`SpellbookCard_${card.packId}_${card.word.id}`)
    .width(86)
    .height(54)
    .margin({ right: 8, bottom: 8 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(this.cardBackground(card.state))
    .borderRadius(8)
    .border({ width: 1, color: this.cardBorder(card.state) })
    .onClick((): void => this.openDetail(card));

    Text('')
      .id(this.stateSpecificCardId(card))
      .width(0)
      .height(0);
  }

  private stateSpecificCardId(card: SpellbookCard): string {
    if (card.state === SpellbookCardState.Mastered) {
      return `SpellbookCardMastered_${card.packId}_${card.word.id}`;
    }
    if (card.state === SpellbookCardState.Seen) {
      return `SpellbookCardSeen_${card.packId}_${card.word.id}`;
    }
    return `SpellbookCardLocked_${card.packId}_${card.word.id}`;
  }

  @Builder
  private detailSheet() {
    Column() {
      Column({ space: 10 }) {
        Text(this.detailWord.word)
          .id('SpellbookWordDetailTitle')
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor('#111827');
        Text(this.detailWord.meaningZh)
          .fontSize(18)
          .fontColor('#374151');
        Text(this.stateLabel(this.detailState))
          .id('SpellbookWordDetailState')
          .fontSize(14)
          .fontColor('#92400E')
          .backgroundColor('#FEF3C7')
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .borderRadius(12);
        if (this.detailWord.example !== undefined) {
          Text(this.detailWord.example.en)
            .fontSize(14)
            .fontColor('#4B5563')
            .textAlign(TextAlign.Center);
          Text(this.detailWord.example.zh)
            .fontSize(14)
            .fontColor('#6B7280')
            .textAlign(TextAlign.Center);
        }
        Button('关闭')
          .id('SpellbookWordDetailClose')
          .height(40)
          .width('100%')
          .backgroundColor('#1D3557')
          .fontColor('#FFFFFF')
          .onClick((): void => {
            this.detailVisible = false;
          });
      }
      .id('SpellbookWordDetailSheet')
      .width(360)
      .constraintSize({ maxWidth: '86%' })
      .padding(22)
      .backgroundColor('#FFFFFF')
      .borderRadius(8)
      .border({ width: 1, color: '#E5E7EB' });
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('#80000000');
  }
}
