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

/** Exported for test assertion and ConfigPage (Task 1.4). */
export const COCOS_BATTLE_PREF_KEY: string = 'battle.useCocosScene';

/** AppStorage key written by CocosBattlePage on engine crash (Task 1.5). */
export const COCOS_BATTLE_FALLBACK_KEY: string = 'cocosBattleFallback';

/** AppStorage key written by EntryAbility from the debug-only want parameter. */
export const FORCE_NATIVE_BATTLE_KEY: string = 'forceNativeBattle';

// ─── Runtime-availability seam ───────────────────────────────────────────────

/**
 * Returns true when the Cocos engine shared library is available.
 *
 * Task 1.5 integration point: replace this stub with a real probe that
 * checks whether libcocos.so loaded successfully (e.g. a boolean flag
 * written by CocosEngineHost after the first XComponent bind succeeds,
 * or after a boot-time `System.loadLibrary` try/catch). Until that
 * probe exists, the library is always bundled so we return `true`
 * unconditionally.
 *
 * @returns {boolean} true = Cocos runtime is usable; false = unavailable.
 */
export function isCocosRuntimeAvailable(): boolean {
  // TODO (Task 1.5): read a flag set by CocosEngineHost on successful init.
  return true;
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
 */
export async function saveCocosScenePref(
  ctx: common.UIAbilityContext,
  enabled: boolean,
): Promise<void> {
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
 *   1. isCocosRuntimeAvailable() — compile-time stub, Task 1.5 flips it.
 *   2. AppStorage 'battle.useCocosScene' — hydrated by
 *      `hydrateCocosScenePref` on app start (call from EntryAbility after
 *      preferences are ready, Task 1.4).  Falls back to true when absent
 *      (default ON).
 *   3. AppStorage COCOS_BATTLE_FALLBACK_KEY  — written by CocosBattlePage.
 *   4. AppStorage FORCE_NATIVE_BATTLE_KEY    — written by EntryAbility.
 */
export function battleRouteUrl(): string {
  const runtimeAvailable: boolean = isCocosRuntimeAvailable();

  const prefRaw: string | undefined =
    AppStorage.get<string>(COCOS_BATTLE_PREF_KEY);
  const prefEnabled: boolean =
    cocosBattlePrefEnabledFromRaw(prefRaw !== undefined ? prefRaw : '');

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
 * Call once from EntryAbility.onCreate (after initBackendEnvPrefs, before
 * loadHome).  Idempotent — second call from the same process is a no-op
 * because AppStorage already has the key.
 */
export async function hydrateCocosScenePref(
  ctx: common.UIAbilityContext,
): Promise<void> {
  const raw: string = await loadCocosScenePrefRaw(ctx);
  const enabled: boolean = cocosBattlePrefEnabledFromRaw(raw);
  AppStorage.setOrCreate<string>(COCOS_BATTLE_PREF_KEY, enabled ? 'true' : 'false');
}
