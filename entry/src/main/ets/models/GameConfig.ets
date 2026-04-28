import { WordEntry } from './WordEntry';

/**
 * Player-facing battle knobs (spec §3.1). Defaults mirror the engine
 * constants in BattleEngine.ets so cold-launch with no explicit save
 * behaves identically to the pre-ConfigPage build.
 *
 * Invariants:
 *   - playerMaxHp / monsterMaxHp / monstersTotal are integers in [1, 10].
 *   - startingSeconds is one of TIMER_CHOICES.
 *   - enabledCategories is a non-empty subset of
 *     KNOWN_CATEGORIES ∪ {CUSTOM_CATEGORY_KEY}.
 *   - customWordsRaw is arbitrary text — parsed lazily by parseCustomWords.
 *
 * GameConfig is a value object — ConfigPage's Save button always writes
 * a freshly-constructed instance (via cloneGameConfig + field edits)
 * because @StorageProp does not refire on same-reference updates.
 */
export class GameConfig {
  playerMaxHp: number = 5;
  monsterMaxHp: number = 3;
  monstersTotal: number = 5;
  startingSeconds: number = 300;
  enabledCategories: string[] = ['fruit', 'place', 'home'];
  customWordsRaw: string = '';
  /**
   * V0.2: auto-play English pronunciation on each new question. Default
   * on — pronunciation is only useful if it happens without the user
   * tapping the speaker every time. ConfigPage exposes a toggle chip.
   */
  autoSpeak: boolean = true;
  /**
   * V0.2: battle mode — 'normal' uses the configured category pool,
   * 'review' sources prompts from the wrong-answer store (T14). Stays
   * 'normal' on fresh AppStorage; HomePage's review button flips it
   * to 'review' before routing to BattlePage, and BattlePage resets
   * it back to 'normal' on end-of-battle.
   */
  mode: string = 'normal';
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

export const TIMER_CHOICES: number[] = [3, 15, 30, 60, 120, 300, 600];

export const HP_MIN: number = 1;
export const HP_MAX: number = 10;
export const MONSTER_COUNT_MIN: number = 1;
export const MONSTER_COUNT_MAX: number = 10;

export const KNOWN_CATEGORIES: string[] = ['fruit', 'place', 'home'];
export const CUSTOM_CATEGORY_KEY: string = 'custom';

/**
 * Mirrors QuestionGenerator.MIN_REPO_SIZE. Duplicated here so ConfigPage
 * validation can reason about "final pool" size without reaching into
 * engine internals. Kept in sync by unit test defaultsMatchEngineDefaults.
 */
export const MIN_POOL_SIZE: number = 3;

/** Deep-enough clone so draft edits don't leak into the stored reference. */
export function cloneGameConfig(src: GameConfig): GameConfig {
  const c: GameConfig = new GameConfig();
  c.playerMaxHp = src.playerMaxHp;
  c.monsterMaxHp = src.monsterMaxHp;
  c.monstersTotal = src.monstersTotal;
  c.startingSeconds = src.startingSeconds;
  c.enabledCategories = src.enabledCategories.slice();
  c.customWordsRaw = src.customWordsRaw;
  c.autoSpeak = src.autoSpeak;
  c.mode = src.mode;
  return c;
}

/**
 * Parse raw CustomWordsPage text into WordEntry[]. Tolerant:
 *   - Accepts ':' (ASCII) and '：' (fullwidth); first occurrence wins.
 *   - Silently skips blank / malformed lines.
 *   - Assigns sequential ids 'custom-0', 'custom-1', ... over valid lines.
 */
export function parseCustomWords(raw: string): WordEntry[] {
  const out: WordEntry[] = [];
  if (raw.length === 0) {
    return out;
  }
  const lines: string[] = raw.split('\n');
  for (let i = 0; i < lines.length; i++) {
    const trimmed: string = lines[i].trim();
    if (trimmed.length === 0) {
      continue;
    }
    let sep: number = trimmed.indexOf(':');
    if (sep < 0) {
      sep = trimmed.indexOf('：');
    }
    if (sep <= 0 || sep >= trimmed.length - 1) {
      continue;
    }
    const zh: string = trimmed.substring(0, sep).trim();
    const en: string = trimmed.substring(sep + 1).trim();
    if (zh.length === 0 || en.length === 0) {
      continue;
    }
    const e: WordEntry = new WordEntry();
    e.id = `custom-${out.length}`;
    e.word = en;
    e.meaningZh = zh;
    e.category = CUSTOM_CATEGORY_KEY;
    e.difficulty = 1;
    out.push(e);
  }
  return out;
}

/**
 * Single source of truth for the battle-time word pool. Used by both
 * BattlePage (runtime) and ConfigPage (Save-time validation) so the
 * two can never disagree on pool size.
 */
export function computeFinalPool(
  allBuiltin: WordEntry[],
  enabledCategories: string[],
  customWordsRaw: string
): WordEntry[] {
  const out: WordEntry[] = [];
  for (let i = 0; i < allBuiltin.length; i++) {
    if (enabledCategories.indexOf(allBuiltin[i].category) >= 0) {
      out.push(allBuiltin[i]);
    }
  }
  if (enabledCategories.indexOf(CUSTOM_CATEGORY_KEY) >= 0) {
    const customs: WordEntry[] = parseCustomWords(customWordsRaw);
    for (let i = 0; i < customs.length; i++) {
      out.push(customs[i]);
    }
  }
  return out;
}
