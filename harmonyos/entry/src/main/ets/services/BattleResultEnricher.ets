/**
 * BattleResultEnricher — post-battle SessionResult enrichment + store flushes
 * (V1.1.0 Task 1.5 extraction).
 *
 * This is the body of BattlePage.navigateToResult (minus the router call)
 * plus its helpers applyTodayAdventureRewards / resetModeToNormal /
 * recordPerfectAdventure / syncCheckInsBestEffort, moved verbatim into a
 * service so the native BattlePage and the Cocos-scene CocosBattlePage run
 * the exact same enrichment before handing the result to ResultPage:
 *
 *   - learning-record totals (newly learned / total learned),
 *   - today-adventure coin rewards, check-in recording, completion badge,
 *   - mode reset back to 'normal',
 *   - recorder / coin / check-in / monster-progress flushes,
 *   - perfect-adventure pack rotation and best-effort check-in cloud sync.
 *
 * Pages stay responsible for their own navigation guard (one replaceUrl per
 * session) and call this exactly once.
 */
import { BusinessError } from '@ohos.base';
import { common } from '@kit.AbilityKit';
import { SessionResult } from '../models/SessionResult';
import { BattleStatus } from '../models/BattleState';
import { TodaySessionPlan, WordSource } from '../models/AdventureRegion';
import { AdventureRegion } from '../models/AdventureRegion';
import { getRegionById } from '../data/AdventureCatalog';
import { Pack } from '../models/Pack';
import {
  GameConfig,
  GAME_CONFIG_STORAGE_KEY,
  GAME_MODE_NORMAL,
  TODAY_LAST_COMPLETED_DAY_KEY,
  cloneGameConfig,
} from '../models/GameConfig';
import { persistGameConfigBestEffort } from './GameConfigPersistence';
import { CoinAccount, getCoinAccount, COIN_REASON_TODAY_FIRST } from './CoinAccount';
import { CoinSnapshot, DAILY_CAP, formatDayKeyLocal } from '../models/CoinSnapshot';
import { CheckInRecordResult, CheckInStore, getCheckInStore } from './CheckInStore';
import { CloudCheckInService } from './CloudCheckInService';
import { CloudCredentials } from './CloudCredentials';
import { RealParentFetchAdapter } from './ParentApiClient';
import { computeMonsterLevelCoinAward } from './BattleRewardCalc';
import { getLearningRecorder, LearningRecorder } from './LearningRecorder';
import { getMonsterProgressStore } from './MonsterProgressStore';
import { getDailyLearningStateService } from './DailyLearningStateService';
import { WordPackBootstrapper } from './WordPackBootstrapper';
import { PackLibrary } from './PackLibrary';
import { PackSelectionService, PerfectAdventureResult } from './PackSelectionService';
import { LibraryCandidateProvider } from './PackHomeIntegration';

/** Mode/plan context the enrichment needs from the battle page. */
export class BattleResultEnrichmentInputs {
  isTodayMode: boolean = false;
  todayPlan: TodaySessionPlan | undefined = undefined;
  activePack: Pack | undefined = undefined;
}

function countByWordSource(plan: TodaySessionPlan, src: WordSource): number {
  let n: number = 0;
  for (let i = 0; i < plan.wordPlan.length; i++) {
    if (plan.wordPlan[i].source === src) {
      n += 1;
    }
  }
  return n;
}

/**
 * Review mode is always a single-battle affordance — reset the stored
 * GameConfig back to 'normal' so the next HomePage launch doesn't
 * accidentally start another review session. Done even when we weren't in
 * review mode so a stale flag from a crashed previous session gets cleaned
 * up on any battle end.
 */
function resetModeToNormal(ctx: common.UIAbilityContext): void {
  const storedCfg: GameConfig | undefined =
    AppStorage.get<GameConfig>(GAME_CONFIG_STORAGE_KEY);
  if (storedCfg === undefined) {
    return;
  }
  if (storedCfg.mode === GAME_MODE_NORMAL) {
    return;
  }
  const next: GameConfig = cloneGameConfig(storedCfg);
  next.mode = GAME_MODE_NORMAL;
  AppStorage.setOrCreate<GameConfig>(GAME_CONFIG_STORAGE_KEY, next);
  persistGameConfigBestEffort(ctx, next);
}

/**
 * V0.6.5.1 — fire-and-forget perfect-adventure recorder. Runs asynchronously
 * after the synchronous result-page navigation has already been posted, so
 * the player never waits on the prefs write. Errors are logged but never
 * block.
 */
function recordPerfectAdventure(ctx: common.UIAbilityContext, packId: string): void {
  (async (): Promise<void> => {
    try {
      const lib: PackLibrary = await WordPackBootstrapper.bootstrapPackLibrary(ctx);
      const sel: PackSelectionService = new PackSelectionService();
      await sel.init(ctx, lib.builtinIds());
      const provider: LibraryCandidateProvider = new LibraryCandidateProvider(lib);
      const out: PerfectAdventureResult =
        await sel.recordPerfectAdventure(packId, provider);
      if (out.rotated) {
        console.info(`BattleResult: pack rotation ${out.swappedOutId} -> ${out.swappedInId}`);
      }
    } catch (err) {
      console.error(`BattleResult: recordPerfectAdventure failed: ${JSON.stringify(err as BusinessError)}`);
    }
  })();
}

function syncCheckInsBestEffort(ctx: common.UIAbilityContext): void {
  const creds: CloudCredentials = new CloudCredentials();
  creds.init(ctx).then((): void => {
    const svc: CloudCheckInService = new CloudCheckInService(
      getCheckInStore(),
      getCoinAccount(),
      creds,
      new RealParentFetchAdapter(),
      (): string => CloudCheckInService.defaultBaseUrlResolver(),
    );
    svc.syncOnce().catch((err: BusinessError): void => {
      console.error(`BattleResult: CloudCheckInService.syncOnce failed: ${JSON.stringify(err)}`);
    });
  }).catch((err: BusinessError): void => {
    console.error(`BattleResult: CloudCredentials.init for check-in failed: ${JSON.stringify(err)}`);
  });
}

/**
 * Compute today-adventure coin awards, mark today as completed for the
 * home-page badge, and write the result into the SessionResult. Coin awards
 * are clamped to the daily cap inside CoinAccount.earn — `dailyCapHit`
 * mirrors that state.
 *
 * V0.8.6 — reward formula is defeated monster level score:
 * Σ count(level) × levelValue. Stars and Bonus kills remain visible
 * combat/result signals, but no longer contribute coins.
 */
function applyTodayAdventureRewards(
  ctx: common.UIAbilityContext,
  result: SessionResult,
  plan: TodaySessionPlan,
  activePack: Pack | undefined,
): void {
  const coinAccount: CoinAccount = getCoinAccount();
  const checkInStore: CheckInStore = getCheckInStore();
  const now: number = Date.now();
  coinAccount.beginToday(now);

  const region: AdventureRegion = getRegionById(plan.regionId);
  result.isTodayAdventure = true;
  result.regionId = plan.regionId;
  result.bossName = region.bossName;
  result.reviewWordCount = countByWordSource(plan, WordSource.Review);
  result.newWordCount = countByWordSource(plan, WordSource.New);

  const awardAmount: number = computeMonsterLevelCoinAward(result.monsterLevelScore);
  result.coinsBaseFromStars = awardAmount;
  let earned: number = 0;
  if (plan.isFirstToday && result.status === BattleStatus.Won) {
    earned = coinAccount.earn(COIN_REASON_TODAY_FIRST, awardAmount, now);
  } else if (awardAmount > 0) {
    earned = coinAccount.earn('stars', awardAmount, now);
  }
  result.coinsEarned = earned;
  if (result.status === BattleStatus.Won) {
    const checkIn: CheckInRecordResult = checkInStore.recordWinSync(now);
    result.checkInRecorded = checkIn.changed;
    result.checkInCurrentStreak = checkIn.currentStreak;
    if (checkIn.bonusCoins > 0 && checkIn.bonusDayKey.length > 0) {
      const txnId: string = `checkin-weekly-bonus:${checkIn.bonusDayKey}`;
      const applied: boolean = coinAccount.applyExternalTxn(
        txnId,
        checkIn.bonusCoins,
        txnId,
        now,
      );
      result.checkInBonusCoins = applied ? checkIn.bonusCoins : 0;
    }
  }
  const snap: CoinSnapshot = coinAccount.snapshot();
  result.coinsTotal = snap.totalCoins - snap.spentCoins;
  result.dailyCapHit = snap.todayCoinsEarned >= DAILY_CAP;

  // Mark today as completed so HomePage can light the "已完成" badge
  // immediately on return from ResultPage. Persistence to disk happens via
  // flushNow on the coin account; the day-key flag is session-only
  // AppStorage state read by HomePage.
  AppStorage.setOrCreate<string>(TODAY_LAST_COMPLETED_DAY_KEY, formatDayKeyLocal(now));
  if (result.status === BattleStatus.Won) {
    getDailyLearningStateService().markPackBattleWon(now).catch((err: BusinessError): void => {
      console.error(`BattleResult: markPackBattleWon failed: ${JSON.stringify(err)}`);
    });
  }

  coinAccount.flushNow().catch((err: BusinessError): void => {
    console.error(`BattleResult: CoinAccount.flushNow failed: ${JSON.stringify(err)}`);
  });
  checkInStore.flushNow().catch((err: BusinessError): void => {
    console.error(`BattleResult: CheckInStore.flushNow failed: ${JSON.stringify(err)}`);
  });
  syncCheckInsBestEffort(ctx);
  // V0.6.5.1: perfect-adventure rotation hook. Fires only when the session
  // was launched from a real Pack chip (activePack populated) AND the
  // player won with all 3 stars (no mistakes per spec §4.4). The actual
  // rotation decision (counter + pinned check + candidate provider) lives
  // in PackSelectionService.
  if (activePack !== undefined &&
      result.status === BattleStatus.Won &&
      result.stars >= 3) {
    recordPerfectAdventure(ctx, activePack.id);
  }
}

/**
 * Enrich the engine-built SessionResult with learning-record totals,
 * today-adventure rewards, mode reset, and store flushes. The caller then
 * routes to ResultPage with the enriched result as router params.
 */
export function enrichAndFlushSessionResult(
  ctx: common.UIAbilityContext,
  result: SessionResult,
  inputs: BattleResultEnrichmentInputs,
): void {
  // Learning-record totals: the engine doesn't know about the recorder, so
  // this is the integration point.
  const recorder: LearningRecorder = getLearningRecorder();
  result.newlyLearnedCount = recorder.newlyLearnedCount;
  result.totalLearnedCount = recorder.totalLearnedCount;
  // Today-adventure coin earnings + result enrichment. Runs only when the
  // engine actually consumed a TodaySessionPlan; in any other mode the new
  // SessionResult fields stay at their defaults.
  if (inputs.isTodayMode && inputs.todayPlan !== undefined) {
    applyTodayAdventureRewards(ctx, result, inputs.todayPlan, inputs.activePack);
  }
  resetModeToNormal(ctx);
  // Force a final flush so counters survive a force-stop — disk errors are
  // swallowed inside flushNow() so nothing is leaked.
  recorder.flushNow().catch((err: BusinessError): void => {
    console.error(`BattleResult: LearningRecorder.flushNow failed: ${JSON.stringify(err)}`);
  });
  getMonsterProgressStore().flushNow().catch((err: BusinessError): void => {
    console.error(`BattleResult: MonsterProgressStore.flushNow failed: ${JSON.stringify(err)}`);
  });
}
