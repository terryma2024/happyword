/**
 * BattleSessionFactory — assembles the BattleEngine and its question source
 * for one battle session (V1.1.0 Task 1.5 extraction).
 *
 * This is the construction block that used to live inline in
 * BattlePage.aboutToAppear. It moved into a service, with zero behavior
 * change, so the native BattlePage and the Cocos-scene CocosBattlePage build
 * battles through the exact same path: same GameConfig resolution, same
 * mode handling (normal / review / today), same plan + pack handoff, same
 * BattleConfig and catalog-index mapping.
 *
 * The factory owns no UI state: pages copy what they need out of the
 * returned {@link BattleSessionSetup} (engine, mode flags, plan, pack,
 * catalogIndexProvider) into their own fields.
 */
import { BusinessError } from '@ohos.base';
import { common } from '@kit.AbilityKit';
import { WordRepository } from './WordRepository';
import { WordPackBootstrapper, BootstrapDeps } from './WordPackBootstrapper';
import { QuestionGenerator } from './QuestionGenerator';
import { FillLetterGenerator } from './FillLetterGenerator';
import { SpellGenerator } from './SpellGenerator';
import { IQuestionSource } from './IQuestionSource';
import { PlanQuestionSource } from './PlanQuestionSource';
import { BattleQuestionScheduler } from './BattleQuestionScheduler';
import { BattleStageScheduler } from './BattleStageScheduler';
import { wordSupportsQuestionType } from './BattleQuestionTypePolicy';
import {
  BattleEngine,
  BattleConfig,
  CatalogIndexProvider,
} from './BattleEngine';
import {
  GameConfig,
  GAME_CONFIG_STORAGE_KEY,
  GAME_MODE_REVIEW,
  GAME_MODE_TODAY,
  TODAY_PLAN_STORAGE_KEY,
  TODAY_ACTIVE_PACK_KEY,
  cloneGameConfig,
} from '../models/GameConfig';
import { TodaySessionPlan, WordSlot, WordSource } from '../models/AdventureRegion';
import { Pack } from '../models/Pack';
import {
  HomeIntegrationBundle,
  loadHomeIntegration,
  resolveActivePacks,
} from './PackHomeIntegration';
import { WordEntry } from '../models/WordEntry';
import { getLearningRecorder, LearningRecorder } from './LearningRecorder';
import { getCoinAccount } from './CoinAccount';
import { getCheckInStore } from './CheckInStore';
import { getMonsterProgressStore } from './MonsterProgressStore';
import {
  DailyLearningState,
  DailyLearningStateService,
  DailyReviewSnapshot,
  getDailyLearningStateService,
  reviewMonsterCount,
} from './DailyLearningStateService';

/**
 * Review-mode battle overrides. Review battles use a 10-minute countdown;
 * monster count is computed from remaining words (moved from BattlePage).
 */
export const REVIEW_MODE_STARTING_SECONDS: number = 600;

function activeWordsFromBundle(bundle: HomeIntegrationBundle): WordEntry[] {
  const packs: Pack[] = resolveActivePacks(bundle);
  const out: WordEntry[] = [];
  for (let i = 0; i < packs.length; i++) {
    for (let j = 0; j < packs[i].words.length; j++) {
      out.push(packs[i].words[j]);
    }
  }
  return out;
}

function mergeWordEntries(primary: WordEntry[], secondary: WordEntry[]): WordEntry[] {
  const out: WordEntry[] = [];
  const seen: string[] = [];
  for (let i = 0; i < primary.length; i++) {
    if (primary[i].id.length > 0 && seen.indexOf(primary[i].id) < 0) {
      seen.push(primary[i].id);
      out.push(primary[i]);
    }
  }
  for (let i = 0; i < secondary.length; i++) {
    if (secondary[i].id.length > 0 && seen.indexOf(secondary[i].id) < 0) {
      seen.push(secondary[i].id);
      out.push(secondary[i]);
    }
  }
  return out;
}

/**
 * Build a focused review plan from today's stable review snapshot.
 * Already-reviewed ids are skipped so returning to review mode only
 * shows the remaining daily work (moved from BattlePage.buildReviewPlan).
 */
function buildReviewPlan(
  dailyStateService: DailyLearningStateService,
  universe: WordEntry[],
): TodaySessionPlan {
  const plan: TodaySessionPlan = new TodaySessionPlan();
  plan.regionId = 'review-daily';
  plan.isFirstToday = false;
  const daily: DailyLearningState = dailyStateService.snapshot();
  const review: DailyReviewSnapshot = daily.reviewSnapshot;
  if (review.wordIds.length === 0) {
    return plan;
  }
  const reviewed: string[] = review.reviewedWordIds;
  const lookup: Map<string, WordEntry> = new Map<string, WordEntry>();
  for (let i = 0; i < universe.length; i++) {
    lookup.set(universe[i].id, universe[i]);
  }
  for (let i = 0; i < review.wordIds.length; i++) {
    const wordId: string = review.wordIds[i];
    if (reviewed.indexOf(wordId) >= 0) {
      continue;
    }
    const hit: WordEntry | undefined = lookup.get(wordId);
    if (hit !== undefined) {
      const slot: WordSlot = new WordSlot();
      slot.wordId = hit.id;
      slot.source = WordSource.Review;
      plan.wordPlan.push(slot);
    }
  }
  return plan;
}

/** Everything a battle page needs out of the assembled session. */
export class BattleSessionSetup {
  readonly engine: BattleEngine;
  readonly cfg: GameConfig;
  /** Same closure handed to BattleConfig — pages/bridges reuse it. */
  readonly catalogIndexProvider: CatalogIndexProvider;
  isReviewMode: boolean = false;
  isTodayMode: boolean = false;
  todayPlan: TodaySessionPlan | undefined = undefined;
  todayStageScheduler: BattleStageScheduler | undefined = undefined;
  activePack: Pack | undefined = undefined;

  constructor(
    engine: BattleEngine,
    cfg: GameConfig,
    catalogIndexProvider: CatalogIndexProvider,
  ) {
    this.engine = engine;
    this.cfg = cfg;
    this.catalogIndexProvider = catalogIndexProvider;
  }
}

/**
 * Fire-and-forget store boot shared by both battle pages (moved from
 * BattlePage.aboutToAppear). init() calls are idempotent; beginSession
 * resets the recorder's per-session counters so the ResultPage footer
 * reflects THIS battle only.
 */
export function initBattleSessionStores(ctx: common.UIAbilityContext): void {
  const recorder: LearningRecorder = getLearningRecorder();
  recorder.init(ctx).then((): void => {
    recorder.beginSession();
  }).catch((err: BusinessError): void => {
    console.error(`BattleSession: LearningRecorder.init failed: ${JSON.stringify(err)}`);
  });
  getCoinAccount().init(ctx).catch((err: BusinessError): void => {
    console.error(`BattleSession: CoinAccount.init failed: ${JSON.stringify(err)}`);
  });
  getCheckInStore().init(ctx).catch((err: BusinessError): void => {
    console.error(`BattleSession: CheckInStore.init failed: ${JSON.stringify(err)}`);
  });
  getMonsterProgressStore().init(ctx).catch((err: BusinessError): void => {
    console.error(`BattleSession: MonsterProgressStore.init failed: ${JSON.stringify(err)}`);
  });
}

/**
 * Load the word universe, resolve the game mode, pick the question source,
 * build the engine, and start it. Mirrors the original BattlePage block
 * line-for-line; see the class doc above.
 *
 * @param onConfigReady invoked as soon as the GameConfig is resolved —
 *        BattlePage uses it to enter its audio mixer at the same point in
 *        the sequence as before the extraction.
 */
export async function buildBattleSessionSetup(
  ctx: common.UIAbilityContext,
  onConfigReady?: (cfg: GameConfig) => void,
): Promise<BattleSessionSetup> {
  const deps: BootstrapDeps = await WordPackBootstrapper.forContext(ctx);
  const repo: WordRepository = await new WordPackBootstrapper().bootstrap(deps);
  const storedCfg: GameConfig | undefined =
    AppStorage.get<GameConfig>(GAME_CONFIG_STORAGE_KEY);
  const cfg: GameConfig = cloneGameConfig(storedCfg !== undefined ? storedCfg : new GameConfig());
  if (onConfigReady !== undefined) {
    onConfigReady(cfg);
  }
  const dailyStateService: DailyLearningStateService = getDailyLearningStateService();
  await dailyStateService.init(ctx);
  const isReviewMode: boolean = cfg.mode === GAME_MODE_REVIEW;
  let isTodayMode: boolean = cfg.mode === GAME_MODE_TODAY;
  let todayPlan: TodaySessionPlan | undefined = undefined;
  let todayStageScheduler: BattleStageScheduler | undefined = undefined;
  let activePack: Pack | undefined = undefined;

  // Universe pool: every word the player could be shown.
  // V0.6.6 — the legacy enabledCategories / customWordsRaw filter was
  // removed when ConfigPage moved to the three-layer pack model. Normal /
  // review mode consume the full built-in repo. Today mode also keeps the
  // full universe so PlanQuestionSource can resolve any wordId that ended
  // up in plan.wordPlan; the active pack's words are layered in below via
  // `bundleEntries`.
  let universe: WordEntry[] = repo.all();
  if (isReviewMode) {
    try {
      const bundle: HomeIntegrationBundle = await loadHomeIntegration(ctx);
      universe = mergeWordEntries(universe, activeWordsFromBundle(bundle));
    } catch (err) {
      console.error(`BattleSession: load review universe failed: ${JSON.stringify(err as BusinessError)}`);
    }
  }
  const finalEntries: WordEntry[] = universe;

  const finalRepo: WordRepository = new WordRepository();
  finalRepo.setEntries(finalEntries);

  const choiceGen: QuestionGenerator = new QuestionGenerator(finalRepo);

  // Pick the IQuestionSource. Today mode uses PlanQuestionSource backed by
  // the plan stored in AppStorage; everything else falls back to the V0.2
  // QuestionGenerator path.
  let source: IQuestionSource = choiceGen;
  let planMonsters: number = -1;
  let reviewPlanWordCount: number = 0;
  if (isReviewMode) {
    const reviewPlan: TodaySessionPlan = buildReviewPlan(dailyStateService, universe);
    if (reviewPlan.wordPlan.length > 0) {
      reviewPlanWordCount = reviewPlan.wordPlan.length;
      const reviewWordIds: string[] = [];
      for (let wi: number = 0; wi < reviewPlan.wordPlan.length; wi++) {
        reviewWordIds.push(reviewPlan.wordPlan[wi].wordId);
      }
      const fillGen: FillLetterGenerator = new FillLetterGenerator();
      const spellGen: SpellGenerator = new SpellGenerator();
      const reviewScheduler: BattleQuestionScheduler =
        new BattleQuestionScheduler(reviewWordIds, cfg.enabledQuestionTypes);
      source = new PlanQuestionSource(
        reviewPlan,
        finalRepo,
        choiceGen,
        fillGen,
        spellGen,
        reviewScheduler,
      );
    }
  }
  if (isTodayMode) {
    const plan: TodaySessionPlan | undefined =
      AppStorage.get<TodaySessionPlan>(TODAY_PLAN_STORAGE_KEY);
    if (plan !== undefined && plan.wordPlan.length > 0) {
      todayPlan = plan;
      // V0.6.5.1: prefer the Pack handed over by HomePage as the source of
      // truth for the bundleRepo. Pack.words is the exhaustive set the plan
      // was built against, so PlanQuestionSource can always resolve every
      // wordId even when the bundled rawfile no longer carries the same
      // category (e.g. a family pack with custom words).
      const handoff: Pack | undefined = AppStorage.get<Pack>(TODAY_ACTIVE_PACK_KEY);
      let bundleEntries: WordEntry[];
      if (handoff !== undefined && handoff.words.length > 0) {
        activePack = handoff;
        bundleEntries = handoff.words.slice();
      } else {
        // Legacy fallback: HomePage was on a synthetic Pack with no words,
        // so use the global rawfile-loaded repo.
        bundleEntries = repo.all();
      }
      const bundleRepo: WordRepository = new WordRepository();
      bundleRepo.setEntries(bundleEntries);
      const fillGen: FillLetterGenerator = new FillLetterGenerator();
      const spellGen: SpellGenerator = new SpellGenerator();
      const planChoiceGen: QuestionGenerator = new QuestionGenerator(bundleRepo);
      const planWordIds: string[] = [];
      for (let wi: number = 0; wi < plan.wordPlan.length; wi++) {
        planWordIds.push(plan.wordPlan[wi].wordId);
      }
      const stageScheduler: BattleStageScheduler = new BattleStageScheduler(
        planWordIds,
        cfg.enabledQuestionTypes,
        (wordId: string, kind: string): boolean => {
          const w: WordEntry | undefined = bundleRepo.findById(wordId);
          return w !== undefined && wordSupportsQuestionType(w, kind);
        },
      );
      todayStageScheduler = stageScheduler;
      const planSource: PlanQuestionSource = new PlanQuestionSource(
        plan, bundleRepo, planChoiceGen, fillGen, spellGen, undefined, stageScheduler);
      source = planSource;
      planMonsters = plan.monsterSlots.length;
      // The provider is wired right after engine construction so the
      // closure captures the engine reference below.
    } else {
      // Plan is missing — degrade gracefully to normal mode so the player
      // isn't stuck on a black screen.
      isTodayMode = false;
    }
  }

  const bc: BattleConfig = new BattleConfig();
  bc.playerMaxHp = cfg.playerMaxHp;
  bc.monsterMaxHp = cfg.monsterMaxHp;
  // Review mode: 10 minutes, with monster count scaled to the remaining
  // daily review words and the configured monster HP.
  if (isReviewMode) {
    bc.monstersTotal = reviewMonsterCount(
      reviewPlanWordCount,
      cfg.monsterMaxHp,
      cfg.monstersTotal,
      new GameConfig().monsterMaxHp,
    );
    bc.startingSeconds = REVIEW_MODE_STARTING_SECONDS;
  } else if (isTodayMode && planMonsters > 0) {
    bc.monstersTotal = cfg.monstersTotal;
    bc.startingSeconds = cfg.startingSeconds;
  } else {
    bc.monstersTotal = cfg.monstersTotal;
    bc.startingSeconds = cfg.startingSeconds;
  }

  // The provider reads the engine lazily (it is constructed right below),
  // mirroring the original closure over BattlePage's `this.engine`.
  let engineRef: BattleEngine | undefined = undefined;
  const planForCatalog: TodaySessionPlan | undefined = todayPlan;
  const stageSchedulerForCatalog: BattleStageScheduler | undefined = todayStageScheduler;
  const todayModeForCatalog: boolean = isTodayMode;
  const catalogIndexProvider: CatalogIndexProvider = (): number => {
    const eng: BattleEngine | undefined = engineRef;
    const idx1: number = eng !== undefined ? eng.getState().monsterIndex : 1;
    if (todayModeForCatalog && stageSchedulerForCatalog !== undefined) {
      return stageSchedulerForCatalog.catalogIndexForMonster(idx1);
    }
    if (planForCatalog !== undefined && planForCatalog.monsterSlots.length > 0) {
      const slotIdx: number = idx1 <= 0 ? 0 : (idx1 - 1) % planForCatalog.monsterSlots.length;
      return planForCatalog.monsterSlots[slotIdx].catalogIndex;
    }
    return idx1 <= 0 ? 1 : idx1;
  };
  bc.catalogIndexProvider = catalogIndexProvider;

  const engine: BattleEngine = new BattleEngine(source, bc);
  engineRef = engine;
  // Now that the engine exists, wire the monster-index provider so
  // PlanQuestionSource can switch question kind per slot.
  if (isTodayMode && source instanceof PlanQuestionSource) {
    const planSource: PlanQuestionSource = source as PlanQuestionSource;
    planSource.setMonsterIndexProvider((): number => engine.getState().monsterIndex);
  }
  engine.start();

  const setup: BattleSessionSetup = new BattleSessionSetup(engine, cfg, catalogIndexProvider);
  setup.isReviewMode = isReviewMode;
  setup.isTodayMode = isTodayMode;
  setup.todayPlan = todayPlan;
  setup.todayStageScheduler = todayStageScheduler;
  setup.activePack = activePack;
  return setup;
}
