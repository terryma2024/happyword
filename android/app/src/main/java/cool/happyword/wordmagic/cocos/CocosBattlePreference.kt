package cool.happyword.wordmagic.cocos

/**
 * CocosBattlePreference — battle-route decision layer (V1.1.0 Task 1.3).
 *
 * Decision table (all four inputs must hold for Cocos routing):
 *
 *   runtimeAvailable  prefEnabled  fallbackActive  forceNative  → route
 *   ────────────────  ───────────  ──────────────  ───────────  ───────
 *   true              true         false           false        COCOS
 *   any               false        any             any          NATIVE
 *   false             any          any             any          NATIVE
 *   any               any          true            any          NATIVE
 *   any               any          any             true         NATIVE
 *
 * Preference store:
 *   File : wordmagic_cocos_battle_prefs  (one-key bag, same name as HOS twin)
 *   Key  : battle.useCocosScene
 *   Type : String ("true" | "false"); absent key → "true" (default ON,
 *           matching iOS / HOS semantics — absent → true).
 *
 * Process-scoped flags:
 *   fallbackActive  — set by CocosBattleActivity (Task 1.4) when the engine
 *                     crashes or fails to send battle/ready in time; subsequent
 *                     battles stay native for the process lifetime.
 *   forceNativeBattle — debug-only flag for instrumentation tests.  Set it in
 *                       @Before so BattleLifecycleFlowTest exercises the native
 *                       BattleScreen regardless of the stored preference.
 *
 * isCocosRuntimeAvailable() note:
 *   On Android, libcocos.so is always bundled and loaded at process start by
 *   CocosActivity.  There is no "library missing" failure mode; only runtime
 *   failures (engine boot throw, scene never sends battle/ready) are
 *   observable.  Task 1.4 latches fallbackActive when such a failure occurs.
 *   isCocosRuntimeAvailable() therefore returns true UNLESS fallbackActive is
 *   set — the fallback flag IS the probe outcome for the rest of the process
 *   lifetime.  This mirrors the HOS CocosBattlePreference.ets design exactly.
 */

import android.content.Context
import android.content.SharedPreferences

// ─── Constants ────────────────────────────────────────────────────────────────

private const val PREFS_NAME = "wordmagic_cocos_battle_prefs"

/** SharedPreferences key for the user-visible Cocos-scene toggle. */
const val COCOS_BATTLE_PREF_KEY = "battle.useCocosScene"

// ─── Route enum ───────────────────────────────────────────────────────────────

/** The two possible routing destinations for a battle start. */
enum class BattleRoute {
    COCOS,
    NATIVE,
}

// ─── Process-scoped flags ─────────────────────────────────────────────────────

/**
 * Set to true by CocosBattleActivity (Task 1.4) when the Cocos engine fails
 * at runtime (boot exception, battle/ready timeout).  Once set, all
 * subsequent battles in this process stay native.
 *
 * This is intentionally a bare @Volatile top-level file property so that
 * instrumentation tests can reset it between test runs.
 */
@Volatile
var fallbackActive: Boolean = false

/**
 * Debug-only flag for instrumentation tests.  Apply [ForceNativeBattleRule] as
 * a `@get:Rule` to keep any battle-driving androidTest exercising the native
 * BattleScreen, regardless of the stored preference or runtime availability.
 * The rule sets this flag in [TestWatcher.starting] and intentionally does not
 * reset it, so the whole instrumentation process stays protected.
 */
@Volatile
var forceNativeBattle: Boolean = false

// ─── Runtime-availability seam ────────────────────────────────────────────────

/**
 * Returns true when the Cocos battle runtime is considered usable.
 *
 * See the module KDoc for the rationale: libcocos.so is always bundled, so
 * "library present" is implicit.  The only observable failures are runtime
 * ones (engine crash / ready timeout), which Task 1.4 records by setting
 * [fallbackActive] = true.  That flag IS the probe outcome for the rest of
 * the process lifetime.
 */
fun isCocosRuntimeAvailable(): Boolean = !fallbackActive

// ─── Pure decision function ───────────────────────────────────────────────────

/**
 * Pure, side-effect-free routing decision.  All four boolean inputs must
 * be true (or false for the inversion cases) to route to Cocos.
 *
 * @param runtimeAvailable  Engine runtime usable ([isCocosRuntimeAvailable]).
 * @param prefEnabled       User toggled Cocos scene on (default true).
 * @param fallbackActive    Engine crashed at runtime this session.
 * @param forceNative       Debug-only instrumentation flag.
 */
fun decideBattleRoute(
    runtimeAvailable: Boolean,
    prefEnabled: Boolean,
    fallbackActive: Boolean,
    forceNative: Boolean,
): BattleRoute {
    return if (runtimeAvailable && prefEnabled && !fallbackActive && !forceNative) {
        BattleRoute.COCOS
    } else {
        BattleRoute.NATIVE
    }
}

// ─── Preference helpers ───────────────────────────────────────────────────────

/**
 * Decode a raw SharedPreferences string value into a boolean.
 *
 * Absent key returns the empty string from [SharedPreferences.getString]
 * with a default of ""; we map:
 *   ""      → true  (absent / never written → default ON, iOS/HOS parity)
 *   "false" → false
 *   "true"  → true
 *   anything else → true  (garbage → ON, same as HOS twin)
 */
fun cocosBattlePrefEnabledFromRaw(raw: String): Boolean = raw != "false"

/**
 * Persist the Cocos-scene preference to SharedPreferences.
 *
 * Uses apply() (fire-and-forget).  The write is immediately visible to any
 * subsequent in-process SharedPreferences read because apply() commits the
 * in-memory state synchronously; the disk flush happens asynchronously in the
 * background.  The value is re-read on the next [chooseBattleRoute] call, so
 * the async disk flush does not create a read-back race.
 */
fun saveCocosScenePref(context: Context, enabled: Boolean) {
    context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        .edit()
        .putString(COCOS_BATTLE_PREF_KEY, if (enabled) "true" else "false")
        .apply()
}

/**
 * Load the raw string value of the Cocos-scene preference.
 * Returns "" when the key has never been written (→ default ON).
 */
fun loadCocosScenePrefRaw(context: Context): String =
    context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        .getString(COCOS_BATTLE_PREF_KEY, "") ?: ""

// ─── Integrated resolver ──────────────────────────────────────────────────────

/**
 * Assemble all inputs and return the [BattleRoute] to use for the next battle.
 *
 * Call this at every "start battle" site (home → start, home → review,
 * result → retry).  The snapshot-restore path is explicitly excluded from
 * Cocos routing (see WordMagicGameApp.kt inline comment); that caller
 * should always use [BattleRoute.NATIVE] directly.
 *
 * Reads:
 *   1. [isCocosRuntimeAvailable] — false once the runtime failed this session.
 *   2. SharedPreferences "battle.useCocosScene" — absent key → true (default ON).
 *   3. [fallbackActive]          — written by CocosBattleActivity (Task 1.4).
 *   4. [forceNativeBattle]       — debug-only instrumentation flag.
 */
fun chooseBattleRoute(context: Context): BattleRoute {
    val runtimeAvailable = isCocosRuntimeAvailable()
    val raw = loadCocosScenePrefRaw(context)
    val prefEnabled = cocosBattlePrefEnabledFromRaw(raw)
    return decideBattleRoute(
        runtimeAvailable = runtimeAvailable,
        prefEnabled = prefEnabled,
        fallbackActive = fallbackActive,
        forceNative = forceNativeBattle,
    )
}
