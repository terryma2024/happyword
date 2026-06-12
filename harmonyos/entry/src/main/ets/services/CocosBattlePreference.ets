/**
 * CocosBattlePreference — battle-route decision layer (V1.1.0 Task 1.3).
 *
 * Decision table (all four inputs must hold for Cocos routing):
 *
 *   runtimeAvailable  prefEnabled  fallbackActive  forceNative  → route
 *   ────────────────  ───────────  ──────────────  ───────────  ───────
 *   true              true         false           false        cocos
 *   any               false        any             any          native
 *   false             any          any             any          native
 *   any               any          true            any          native
 *   any               any          any             true         native
 *
 * AppStorage keys used at runtime:
 *   'cocosBattleFallback'  boolean  set by CocosBattlePage when the engine
 *                                    crashes mid-session; subsequent battles
 *                                    stay native for the process lifetime.
 *   'forceNativeBattle'    boolean  set in EntryAbility.onCreate from the
 *                                    `forceNativeBattle` want parameter
 *                                    (debug builds only); used by ohosTest
 *                                    to keep the native BattlePage exercised.
 *
 * Preference store:
 *   File : wordmagic_cocos_battle_prefs  (one-key bag)
 *   Key  : battle.useCocosScene
 *   Type : string ('true' | 'false'); absent key → 'true' (default ON,
 *           matching iOS semantics — object(forKey:) == nil → true).
 */

import preferences from '@ohos.data.preferences';
import { BusinessError } from '@ohos.base';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;
const PREFS_NAME: string = 'wordmagic_cocos_battle_prefs';

/**
 * Exported for test assertion and ConfigPage (Task 1.4).
 *
 * NOTE: this constant serves as BOTH the @ohos.data.preferences file key
 * (where the value is stored as the string 'true' | 'false') AND the
 * AppStorage key (where the value is stored as a boolean).
 */
export const COCOS_BATTLE_PREF_KEY: string = 'battle.useCocosScene';

/** AppStorage key written by CocosBattlePage on engine crash (Task 1.5). */
export const COCOS_BATTLE_FALLBACK_KEY: string = 'cocosBattleFallback';

/** AppStorage key written by EntryAbility from the debug-only want parameter. */
export const FORCE_NATIVE_BATTLE_KEY: string = 'forceNativeBattle';

// ─── Runtime-availability seam ───────────────────────────────────────────────

/**
 * Returns true when the Cocos battle runtime is considered usable.
 *
 * Task 1.5: libcocos.so is always bundled and dlopened at app start on this
 * platform, so "library present" is implicit — the only observable failure
 * modes are runtime ones (engine boot throw, scene never sending
 * battle/ready). CocosBattlePage records those by latching
 * AppStorage[COCOS_BATTLE_FALLBACK_KEY] = true, so that flag IS the probe
 * outcome for the rest of the process lifetime.
 *
 * Note this intentionally overlaps with decideBattleRoute's `fallbackActive`
 * input: routing already stays native via that input, while this function
 * additionally hides the ConfigPage Cocos switch row once the runtime has
 * proven broken in this session.
 *
 * @returns {boolean} true = Cocos runtime is usable; false = it failed at
 *          runtime this session.
 */
export function isCocosRuntimeAvailable(): boolean {
  return AppStorage.get<boolean>(COCOS_BATTLE_FALLBACK_KEY) !== true;
}

// ─── Pure decision function ───────────────────────────────────────────────────

/**
 * Pure, side-effect-free routing decision.
 *
 * @param runtimeAvailable  Engine libs loadable (isCocosRuntimeAvailable()).
 * @param prefEnabled       User toggled Cocos scene on (default true).
 * @param fallbackActive    Engine crashed at runtime this session.
 * @param forceNative       Debug-only want parameter via EntryAbility.
 */
export function decideBattleRoute(
  runtimeAvailable: boolean,
  prefEnabled: boolean,
  fallbackActive: boolean,
  forceNative: boolean,
): 'cocos' | 'native' {
  if (runtimeAvailable && prefEnabled && !fallbackActive && !forceNative) {
    return 'cocos';
  }
  return 'native';
}

// ─── Preference helpers ───────────────────────────────────────────────────────

/**
 * Decode a raw string value from preferences into a boolean.
 * Absent key (empty string default) → true (iOS parity: nil → ON).
 * Explicit 'false' → false. Everything else (including 'true') → true.
 */
export function cocosBattlePrefEnabledFromRaw(raw: string): boolean {
  return raw !== 'false';
}

/**
 * Persist the Cocos-scene preference.  Fire-and-forget — failures are
 * logged but not surfaced to the caller (UI parity with BackendEnv).
 *
 * Also updates AppStorage immediately so battleRouteUrl() reflects the
 * new value without an app restart.
 */
export async function saveCocosScenePref(
  ctx: common.UIAbilityContext,
  enabled: boolean,
): Promise<void> {
  // Update AppStorage immediately so battleRouteUrl() picks up the new
  // value on the next call (no restart required).
  AppStorage.setOrCreate<boolean>(COCOS_BATTLE_PREF_KEY, enabled);
  try {
    const handle: preferences.Preferences =
      await preferences.getPreferences(ctx, PREFS_NAME);
    await handle.put(COCOS_BATTLE_PREF_KEY, enabled ? 'true' : 'false');
    await handle.flush();
  } catch (err) {
    hilog.warn(
      DOMAIN,
      'CocosPrefs',
      'saveCocosScenePref failed: %{public}s',
      JSON.stringify(err as BusinessError),
    );
  }
}

/**
 * Load and return the raw string value.  Callers pass it to
 * `cocosBattlePrefEnabledFromRaw` to get a boolean.  Exposed as a
 * separate step so tests can verify the raw → boolean conversion without
 * a real Context.
 */
export async function loadCocosScenePrefRaw(
  ctx: common.UIAbilityContext,
): Promise<string> {
  try {
    const handle: preferences.Preferences =
      await preferences.getPreferences(ctx, PREFS_NAME);
    const raw: preferences.ValueType =
      await handle.get(COCOS_BATTLE_PREF_KEY, '');
    return typeof raw === 'string' ? raw : '';
  } catch (err) {
    hilog.warn(
      DOMAIN,
      'CocosPrefs',
      'loadCocosScenePrefRaw failed: %{public}s',
      JSON.stringify(err as BusinessError),
    );
    return '';
  }
}

// ─── Integrated resolver ──────────────────────────────────────────────────────

/**
 * Assemble all inputs and return the page URL to navigate to.
 *
 * This is the single call-site used by HomePage and ResultPage.
 * It reads:
 *   1. isCocosRuntimeAvailable() — false once the runtime failed this session.
 *   2. AppStorage 'battle.useCocosScene' — hydrated by
 *      `hydrateCocosScenePref` on app start (call from EntryAbility after
 *      preferences are ready, Task 1.4).  Falls back to true when absent
 *      (default ON).
 *   3. AppStorage COCOS_BATTLE_FALLBACK_KEY  — written by CocosBattlePage.
 *   4. AppStorage FORCE_NATIVE_BATTLE_KEY    — written by EntryAbility.
 */
export function battleRouteUrl(): string {
  const runtimeAvailable: boolean = isCocosRuntimeAvailable();

  const prefStored: boolean | undefined =
    AppStorage.get<boolean>(COCOS_BATTLE_PREF_KEY);
  const prefEnabled: boolean = prefStored !== undefined ? prefStored : true;

  const fallbackActive: boolean =
    AppStorage.get<boolean>(COCOS_BATTLE_FALLBACK_KEY) === true;

  const forceNative: boolean =
    AppStorage.get<boolean>(FORCE_NATIVE_BATTLE_KEY) === true;

  const route: 'cocos' | 'native' = decideBattleRoute(
    runtimeAvailable,
    prefEnabled,
    fallbackActive,
    forceNative,
  );

  return route === 'cocos' ? 'pages/CocosBattlePage' : 'pages/BattlePage';
}

/**
 * Boot helper: read the persisted preference and write it to AppStorage
 * so `battleRouteUrl()` can read it synchronously afterwards.
 *
 * Called from onWindowStageCreate concurrently with other hydrates.
 * setOrCreate overwrites any existing value, so a second call in the
 * same process will re-apply the persisted preference (not a no-op).
 */
export async function hydrateCocosScenePref(
  ctx: common.UIAbilityContext,
): Promise<void> {
  const raw: string = await loadCocosScenePrefRaw(ctx);
  const enabled: boolean = cocosBattlePrefEnabledFromRaw(raw);
  AppStorage.setOrCreate<boolean>(COCOS_BATTLE_PREF_KEY, enabled);
}
