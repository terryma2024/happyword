/**
 * Persists {@link GameConfig} to device preferences so settings survive
 * app restart. AppStorage alone is process-memory only — parent PIN and
 * other knobs were lost after kill/relaunch until this layer existed.
 */

import { common } from '@kit.AbilityKit';
import { BusinessError } from '@ohos.base';
import { hilog } from '@kit.PerformanceAnalysisKit';
import preferences from '@ohos.data.preferences';
import {
  GameConfig,
  GAME_CONFIG_STORAGE_KEY,
  TIMER_CHOICES,
  HP_MIN,
  HP_MAX,
  MONSTER_COUNT_MIN,
  MONSTER_COUNT_MAX,
} from '../models/GameConfig';

const DOMAIN: number = 0x0000;
const PREFS_NAME: string = 'wordmagic_game_config_v1';
const KEY_JSON: string = 'game_config_json';

function clampInt(n: number, lo: number, hi: number): number {
  if (n < lo) {
    return lo;
  }
  if (n > hi) {
    return hi;
  }
  return n;
}

function sanitizeTimer(seconds: number): number {
  const choices: number[] = TIMER_CHOICES;
  let best: number = choices[0];
  let bestDist: number = Math.abs(seconds - best);
  for (let i: number = 1; i < choices.length; i++) {
    const d: number = Math.abs(seconds - choices[i]);
    if (d < bestDist) {
      bestDist = d;
      best = choices[i];
    }
  }
  return best;
}

/** Serializes {@link GameConfig} fields — keep in sync with {@link cloneGameConfig}. */
export function gameConfigToJson(cfg: GameConfig): string {
  return JSON.stringify({
    playerMaxHp: cfg.playerMaxHp,
    monsterMaxHp: cfg.monsterMaxHp,
    monstersTotal: cfg.monstersTotal,
    startingSeconds: cfg.startingSeconds,
    autoSpeak: cfg.autoSpeak,
    mode: cfg.mode,
    parentPin: cfg.parentPin,
  });
}

/** Parses persisted JSON; invalid fragments fall back to defaults (same idea as cloneGameConfig). */
export function gameConfigFromJson(raw: string): GameConfig {
  const parsed: Object = JSON.parse(raw) as Object;
  const rec: Record<string, Object> = parsed as Record<string, Object>;
  const out: GameConfig = new GameConfig();

  const pm: Object | undefined = rec['playerMaxHp'];
  if (typeof pm === 'number') {
    out.playerMaxHp = clampInt(Math.floor(pm), HP_MIN, HP_MAX);
  }
  const mm: Object | undefined = rec['monsterMaxHp'];
  if (typeof mm === 'number') {
    out.monsterMaxHp = clampInt(Math.floor(mm), HP_MIN, HP_MAX);
  }
  const mt: Object | undefined = rec['monstersTotal'];
  if (typeof mt === 'number') {
    out.monstersTotal = clampInt(Math.floor(mt), MONSTER_COUNT_MIN, MONSTER_COUNT_MAX);
  }
  const ss: Object | undefined = rec['startingSeconds'];
  if (typeof ss === 'number') {
    out.startingSeconds = sanitizeTimer(Math.floor(ss));
  }
  // V0.6.6: legacy `enabledCategories` / `customWordsRaw` keys are
  // ignored on rehydrate. Older devices upgrading from <= v0.6.5
  // simply lose those fields silently — the three-layer pack model
  // owns word selection now.
  const ap: Object | undefined = rec['autoSpeak'];
  if (typeof ap === 'boolean') {
    out.autoSpeak = ap;
  }
  const md: Object | undefined = rec['mode'];
  if (typeof md === 'string') {
    out.mode = md;
  }
  const pin: Object | undefined = rec['parentPin'];
  if (typeof pin === 'string') {
    out.parentPin = pin;
  }
  return out;
}

/**
 * Loads persisted config (if any) into AppStorage, overwriting the default
 * empty GameConfig created in EntryAbility.onCreate.
 */
export async function hydrateGameConfigFromPrefs(ctx: common.UIAbilityContext): Promise<void> {
  try {
    const handle: preferences.Preferences = await preferences.getPreferences(ctx, PREFS_NAME);
    const rawVal: preferences.ValueType = await handle.get(KEY_JSON, '');
    const raw: string = typeof rawVal === 'string' ? rawVal : '';
    if (raw.length === 0) {
      return;
    }
    const cfg: GameConfig = gameConfigFromJson(raw);
    AppStorage.set<GameConfig>(GAME_CONFIG_STORAGE_KEY, cfg);
  } catch (err) {
    hilog.warn(
      DOMAIN,
      'GameCfg',
      'hydrateGameConfigFromPrefs failed: %{public}s',
      JSON.stringify(err as BusinessError),
    );
  }
}

/** Writes the current snapshot to preferences (flush). */
export async function persistGameConfig(ctx: common.UIAbilityContext, cfg: GameConfig): Promise<void> {
  try {
    const handle: preferences.Preferences = await preferences.getPreferences(ctx, PREFS_NAME);
    try {
      await handle.put(KEY_JSON, gameConfigToJson(cfg));
    } catch (err) {
      hilog.warn(DOMAIN, 'GameCfg', 'prefs.put failed: %{public}s', JSON.stringify(err as BusinessError));
      return;
    }
    try {
      await handle.flush();
    } catch (err) {
      hilog.warn(DOMAIN, 'GameCfg', 'prefs.flush failed: %{public}s', JSON.stringify(err as BusinessError));
    }
  } catch (err) {
    hilog.warn(DOMAIN, 'GameCfg', 'persistGameConfig failed: %{public}s', JSON.stringify(err as BusinessError));
  }
}

/**
 * Fire-and-forget persist — call after every AppStorage write of GameConfig.
 */
export function persistGameConfigBestEffort(ctx: common.UIAbilityContext | undefined, cfg: GameConfig): void {
  if (ctx === undefined) {
    return;
  }
  persistGameConfig(ctx, cfg).catch((err: BusinessError): void => {
    hilog.warn(
      DOMAIN,
      'GameCfg',
      'persistGameConfig failed: %{public}s',
      JSON.stringify(err),
    );
  });
}
