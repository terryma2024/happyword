package cool.happyword.wordmagic.cocos

import cool.happyword.wordmagic.core.BattleAnswerOutcome
import cool.happyword.wordmagic.core.BattleEngine
import cool.happyword.wordmagic.core.BattleState
import cool.happyword.wordmagic.core.GameConfig

/**
 * CocosBattleSession — in-process handoff between the Compose host
 * (WordMagicGameApp) and [CocosBattleActivity] (Android Task 1.4).
 *
 * Why a process-level holder instead of Intent extras / an activity result
 * contract: the battle session is built at the Compose route site (home
 * start / review start — the same construction the native BattleScreen
 * path uses) and the [BattleEngine] instance is NOT serializable — it
 * carries the word universe, the question scheduler's cursor state, and the
 * served-question bookkeeping. Settlement parity also requires the SAME
 * engine instance on both sides (`engine.resultFor(state)` on the Compose
 * side must see the config/bonus accounting the bridge played against).
 * There is no existing activity-result precedent in the app (DevMenu is a
 * Compose route; the only registerForActivityResult use is the third-party
 * QR scanner), so the simplest mechanism consistent with the codebase is a
 * single-slot object holder:
 *
 *   route site   publishInputs(engine, initial, config)  → startActivity
 *   activity     takeInputs() in onCreate (one-shot; null on a second take)
 *   activity     postOutcome(...) just before finish()
 *   Compose      consumeOutcome() in its ON_RESUME lifecycle observer and
 *                settles exactly like the native path (see WordMagicGameApp)
 *
 * Threading: every access happens on the main thread (route-site click
 * handlers, activity lifecycle, the bridge's main-thread callbacks), so no
 * synchronization is needed.
 *
 * If the activity finishes WITHOUT posting an outcome (e.g. system back
 * before the scene loaded), the Compose side simply stays where it was —
 * the stale per-session vars are overwritten by the next battle start.
 */

/** Everything the activity needs to run the session the route site built. */
data class CocosBattleSessionInputs(
    val engine: BattleEngine,
    val initialState: BattleState,
    val config: GameConfig,
    /**
     * Per-answer side effects (learning record, review mark, monster
     * progress) — the route site captures the SAME body the native
     * BattleScreen onAnswer runs (WordMagicGameApp.applyAnswerSideEffects),
     * and the activity wires it into
     * [CocosBattleBridgeCallbacks.onAnswerOutcome]. Invoked on the main
     * thread once per accepted submit with the PRE-submit state.
     */
    val onAnswerOutcome: (preState: BattleState, outcome: BattleAnswerOutcome) -> Unit = { _, _ -> },
)

/** What happened in the Cocos battle, for the Compose side to settle. */
sealed interface CocosBattleOutcome {
    /**
     * Battle ended organically (won / lost / escape). The Compose side runs
     * the full native settlement: `finishBattleSession(finalState)`.
     */
    data class Finished(val finalState: BattleState) : CocosBattleOutcome

    /**
     * The host countdown hit 0 while still Playing. Mirrors the native
     * timer's minimal settlement (clear snapshot + resultFor + Result
     * route — the native timeout path skips coin/check-in crediting).
     */
    data class TimedOut(val finalState: BattleState) : CocosBattleOutcome

    /**
     * Engine boot failure or battle/ready watchdog timeout. fallbackActive
     * is already latched; the Compose side re-routes the SAME session into
     * the native BattleScreen (`route = AppRoute.Battle`).
     */
    data object Fallback : CocosBattleOutcome
}

object CocosBattleSessionHolder {
    private var inputs: CocosBattleSessionInputs? = null
    private var outcome: CocosBattleOutcome? = null

    /** Route site → activity. Clears any stale outcome from a prior session. */
    fun publishInputs(next: CocosBattleSessionInputs) {
        inputs = next
        outcome = null
    }

    /** One-shot take by the activity; null when launched without a session. */
    fun takeInputs(): CocosBattleSessionInputs? {
        val taken = inputs
        inputs = null
        return taken
    }

    /** Activity → Compose, posted just before finish(). */
    fun postOutcome(next: CocosBattleOutcome) {
        outcome = next
    }

    /** One-shot consume by the Compose ON_RESUME observer. */
    fun consumeOutcome(): CocosBattleOutcome? {
        val consumed = outcome
        outcome = null
        return consumed
    }
}
