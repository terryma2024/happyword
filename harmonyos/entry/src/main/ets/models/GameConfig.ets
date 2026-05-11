import {
  DEFAULT_ENABLED_QUESTION_TYPES,
  sanitizeEnabledQuestionTypes,
} from '../services/BattleQuestionTypePolicy';

/**
 * Player-facing battle knobs (spec §3.1). Defaults mirror the engine
 * constants in BattleEngine.ets so cold-launch with no explicit save
 * behaves identically to the pre-ConfigPage build.
 *
 * Invariants:
 *   - playerMaxHp / monsterMaxHp / monstersTotal are integers in [1, 10].
 *   - startingSeconds is one of TIMER_CHOICES.
 *
 * GameConfig is a value object — ConfigPage's Save button always writes
 * a freshly-constructed instance (via cloneGameConfig + field edits)
 * because @StorageProp does not refire on same-reference updates.
 *
 * V0.6.6 cleanup: the legacy `enabledCategories` / `customWordsRaw`
 * fields and their `KNOWN_CATEGORIES` / `CUSTOM_CATEGORY_KEY` /
 * `parseCustomWords` / `computeFinalPool` helpers were removed —
 * the three-layer pack model (built-in / global / family) replaces
 * them end to end. Today's adventure consumes the active Pack.words
 * directly; non-today battles use the merged built-in repo pool.
 */
export class GameConfig {
  playerMaxHp: number = 5;
  monsterMaxHp: number = 3;
  monstersTotal: number = 5;
  startingSeconds: number = 300;
  /**
   * V0.2: auto-play English pronunciation on each new question. Default
   * on — pronunciation is only useful if it happens without the user
   * tapping the speaker every time. ConfigPage exposes a toggle chip.
   */
  autoSpeak: boolean = true;
  /**
   * V0.2: battle mode — 'normal' uses the built-in word repository,
   * 'review' sources prompts from the wrong-answer store (T14). Stays
   * 'normal' on fresh AppStorage; HomePage's review button flips it
   * to 'review' before routing to BattlePage, and BattlePage resets
   * it back to 'normal' on end-of-battle.
   */
  mode: string = 'normal';
  /**
   * V0.3.9: 6-digit parent PIN gate for wishlist redemption. Empty
   * string means "not configured" — wishlist's Apply button will
   * pop a hint dialog pointing at ConfigPage and refuse to open the
   * PIN entry dialog. Stored as plaintext (acceptable for a local
   * family device; v0.6 cloud sync may add hashing).
   */
  parentPin: string = '';
  /**
   * V0.6.8: battle question types selected by the parent. The order is
   * difficulty order and is normalized by BattleQuestionTypePolicy.
   */
  enabledQuestionTypes: string[] = DEFAULT_ENABLED_QUESTION_TYPES.slice();
}

/** Battle-mode string values to avoid typos at call sites. */
export const GAME_MODE_NORMAL: string = 'normal';
export const GAME_MODE_REVIEW: string = 'review';
/** V0.3: today's adventure mode — BattlePage consumes a TodaySessionPlan from AppStorage. */
export const GAME_MODE_TODAY: string = 'today';

export const GAME_CONFIG_STORAGE_KEY: string = 'gameConfig';
/** AppStorage key for the in-flight TodaySessionPlan handed off from HomePage to BattlePage. */
export const TODAY_PLAN_STORAGE_KEY: string = 'todayPlan';
/** AppStorage key for the day-key when the player last finished today's adventure. */
export const TODAY_LAST_COMPLETED_DAY_KEY: string = 'todayLastCompletedDayKey';
/** AppStorage key for the selected Today Adventure region id (V0.3.5). */
export const TODAY_REGION_ID_KEY: string = 'todayRegionId';
/**
 * V0.6.5.1: AppStorage key for the in-flight Pack handed off from HomePage
 * to BattlePage when launching today's adventure. Mirrors the same
 * "produce-once consume-once" hand-off as TODAY_PLAN_STORAGE_KEY.
 */
export const TODAY_ACTIVE_PACK_KEY: string = 'todayActivePack';

/**
 * V0.6.7.7: timer chip presets shown in `pages/ConfigPage.timerRow`.
 * Trimmed from the prior `[3, 15, 30, 60, 120, 300, 600]` set to a
 * small parent-friendly menu (30s, 3m, 5m, 10m). The previous fast
 * options (3s / 15s / 1m / 2m) were removed because they were
 * developer / QA shortcuts that confused first-time parents — now
 * exercised through the new 自定义 dialog (any positive integer in
 * [TIMER_CUSTOM_MIN, TIMER_CUSTOM_MAX] seconds), which UI tests use
 * to inject 3s for fast-timeout scenarios. Keep this array sorted in
 * ascending order so `ConfigPage.timerLabel`'s `${seconds}s` /
 * `${seconds / 60}m` formatter renders predictably.
 */
export const TIMER_CHOICES: number[] = [30, 180, 300, 600];

/**
 * V0.6.7.7: bounds for the 自定义 (custom seconds) dialog. The lower
 * bound is intentionally 1 — UI tests rely on injecting 3s to drive
 * fast `BattleEngine.tick` timeouts; allowing 0 would let parents
 * disable the timer entirely and break `BattleEngine.startingSeconds`
 * which expects a positive countdown. The upper bound (3600s = 1h) is
 * a defensive ceiling so a typo doesn't persist a multi-hour battle.
 */
export const TIMER_CUSTOM_MIN: number = 1;
export const TIMER_CUSTOM_MAX: number = 3600;

export const HP_MIN: number = 1;
export const HP_MAX: number = 10;
export const MONSTER_COUNT_MIN: number = 1;
export const MONSTER_COUNT_MAX: number = 10;

/**
 * Mirrors QuestionGenerator.MIN_REPO_SIZE. Used by review-mode pool
 * narrowing (BattlePage.buildReviewPool) and other validation paths
 * that need to reason about "this pool is too small to play". Kept
 * in sync with engine internals by the unit test
 * defaultsMatchEngineDefaults.
 */
export const MIN_POOL_SIZE: number = 3;

/** Deep-enough clone so draft edits don't leak into the stored reference. */
export function cloneGameConfig(src: GameConfig): GameConfig {
  const c: GameConfig = new GameConfig();
  c.playerMaxHp = src.playerMaxHp;
  c.monsterMaxHp = src.monsterMaxHp;
  c.monstersTotal = src.monstersTotal;
  c.startingSeconds = src.startingSeconds;
  c.autoSpeak = src.autoSpeak;
  c.mode = src.mode;
  c.enabledQuestionTypes = sanitizeEnabledQuestionTypes(src.enabledQuestionTypes);
  // V0.3.9: legacy AppStorage snapshots written before parentPin
  // existed will rehydrate as undefined; coerce to empty string so
  // the rest of the codebase can rely on a string contract.
  c.parentPin = (typeof src.parentPin === 'string') ? src.parentPin : '';
  return c;
}
