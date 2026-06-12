package cool.happyword.wordmagic.cocos

import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.cocos.lib.CocosActivity
import com.cocos.lib.JsbBridgeWrapper
import cool.happyword.wordmagic.R
import cool.happyword.wordmagic.core.BattleStatus
import cool.happyword.wordmagic.core.QuestionKind
import cool.happyword.wordmagic.ui.battle.AndroidBattleAudioMixer

/**
 * Hosts the Cocos battle scene as a separate Activity (Task 1.4 live wiring).
 *
 * The activity is a thin lifecycle shell around [CocosBattleBridge]; the
 * session itself (engine + initial state + config) is built at the Compose
 * route site — the SAME construction the native BattleScreen path uses — and
 * handed over through [CocosBattleSessionHolder] (see its KDoc for why a
 * process-level holder instead of Intent extras). Settlement also happens on
 * the Compose side: the activity posts a [CocosBattleOutcome] and finishes;
 * WordMagicGameApp consumes it in an ON_RESUME observer and runs the exact
 * native settlement (`finishBattleSession` / native-timeout equivalent).
 *
 * Lifecycle (Task 0.3 verdicts, cocos/README.md → "Android embed"):
 *   onCreate    register the JsbBridgeWrapper listener (singleton — stacks
 *               duplicates, so it MUST be removed in onDestroy), take the
 *               session inputs, build bridge + audio, arm the 5 s
 *               battle/ready watchdog. Every activity entry is a fresh JS
 *               reload, so each entry gets a fresh organic battle/ready —
 *               per-activity bridge, no process ready-latch.
 *   onReady     (every battle/ready) cancel the watchdog, start the host's
 *               1 Hz countdown (the functional BattleState carries no clock;
 *               the host owns the timer like the native battleTimeLeft).
 *   onPause /   the Cocos VM stays alive while backgrounded; no new ready on
 *   onResume    return — nothing to re-arm.
 *   onDestroy   remove listener, dispose bridge + audio, cancel handlers.
 *
 * Fallback contract: engine boot failure (throw during onCreate) or no
 * battle/ready within [READY_TIMEOUT_MS] latches the process-scoped
 * [fallbackActive] flag, posts [CocosBattleOutcome.Fallback] and finishes —
 * the Compose side then re-routes the same session into the native
 * BattleScreen, and every later battle this process stays native.
 *
 * Threading: JsbBridgeWrapper delivers scene callbacks on the Cocos game
 * thread; [JsbTransport] hops to the main thread BEFORE invoking the bridge
 * handler (bridge threading contract). All host timers are main-Looper.
 */
class CocosBattleActivity : CocosActivity() {

    private val tag = "WMCocosBattle"

    private val mainHandler = Handler(Looper.getMainLooper())
    private val transport = JsbTransport(mainHandler)

    private var bridge: CocosBattleBridge? = null
    private var audioMixer: AndroidBattleAudioMixer? = null

    /** Host-owned countdown (native battleTimeLeft parity). */
    private var remainingSeconds: Int = 0
    private var countdownStarted: Boolean = false
    private var readyWatchdogPending: Boolean = false
    private var outcomePosted: Boolean = false

    private val readyWatchdog = Runnable {
        readyWatchdogPending = false
        Log.e(tag, "no battle/ready within ${READY_TIMEOUT_MS} ms — falling back to native battle")
        fallbackToNative()
    }

    private val countdownTick = object : Runnable {
        override fun run() {
            val activeBridge = bridge ?: return
            if (outcomePosted) return
            if (activeBridge.currentState.status != BattleStatus.Playing) return
            remainingSeconds = (remainingSeconds - 1).coerceAtLeast(0)
            activeBridge.sendStateTick(remainingSeconds)
            if (remainingSeconds <= 0 && activeBridge.currentState.status == BattleStatus.Playing) {
                // Mirror the native timer's timeout: state.copy(playerHp = 0,
                // status = Lost) and the minimal settlement (the Compose side
                // runs the native-timeout equivalent for TimedOut).
                val timedOut = activeBridge.currentState.copy(
                    playerHp = 0,
                    status = BattleStatus.Lost,
                )
                postOutcomeAndFinish(CocosBattleOutcome.TimedOut(timedOut))
                return
            }
            mainHandler.postDelayed(this, TICK_MS)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        // Engine boot failure (native init throw) → fallback path. super must
        // run inside the try: CocosActivity.onCreate loads libcocos.so and
        // boots the engine.
        try {
            super.onCreate(savedInstanceState)
            Log.i(tag, "CocosBattleActivity onCreate")
            wireSession()
        } catch (err: Throwable) {
            Log.e(tag, "Cocos engine boot failed — falling back to native battle", err)
            fallbackToNative()
        }
    }

    private fun wireSession() {
        val inputs = CocosBattleSessionHolder.takeInputs()
        if (inputs == null) {
            // Launched without a published session (programming error — every
            // entry point publishes before startActivity). Nothing to play
            // and nothing wrong with the engine: just leave.
            Log.e(tag, "launched without session inputs — finishing")
            finish()
            return
        }

        val mixer = AndroidBattleAudioMixer(applicationContext)
        mixer.enter(inputs.config)
        audioMixer = mixer

        remainingSeconds = inputs.config.timerSeconds

        bridge = CocosBattleBridge(
            engine = inputs.engine,
            config = inputs.config,
            initialState = inputs.initialState,
            transport = transport,
            callbacks = CocosBattleBridgeCallbacks(
                onFinish = { _ ->
                    // Settlement happens Compose-side from the final state
                    // (finishBattleSession recomputes the SessionResult from
                    // the same engine — identical to the native path).
                    val finalState = bridge?.currentState ?: inputs.initialState
                    postOutcomeAndFinish(CocosBattleOutcome.Finished(finalState))
                },
                playSfx = { cue -> playSfx(mixer, cue) },
                speakWord = { word -> mixer.speakWord(word) },
                autoSpeakWord = { word, kind ->
                    // BattleScreen auto-speak gating parity: config toggle,
                    // never for sentence-cloze, and the same 250 ms settle
                    // delay before speaking the swapped-in question.
                    if (inputs.config.autoPronunciation && kind != QuestionKind.SentenceCloze) {
                        mainHandler.postDelayed({ mixer.speakWord(word) }, AUTO_SPEAK_DELAY_MS)
                    }
                },
                onReady = { onSceneReady() },
            ),
            scheduler = { delayMs, fn ->
                val runnable = Runnable(fn)
                mainHandler.postDelayed(runnable, delayMs)
                Cancellable { mainHandler.removeCallbacks(runnable) }
            },
        )

        // Listener registration AFTER the bridge wired its transport handler,
        // so the first hop never lands on a null handler. JsbBridgeWrapper is
        // a process-level singleton — removed in onDestroy (it stacks
        // duplicates despite its javadoc).
        JsbBridgeWrapper.getInstance()
            .addScriptEventListener(EVENT_TO_NATIVE, transport.listener)

        // Watchdog armed last: if the scene never sends battle/ready the
        // player still lands in a playable (native) battle.
        readyWatchdogPending = true
        mainHandler.postDelayed(readyWatchdog, READY_TIMEOUT_MS)
    }

    /** Every battle/ready: stop the watchdog; first one starts the clock. */
    private fun onSceneReady() {
        Log.i(tag, "scene ready (countdownStarted=$countdownStarted)")
        if (readyWatchdogPending) {
            readyWatchdogPending = false
            mainHandler.removeCallbacks(readyWatchdog)
        }
        if (!countdownStarted) {
            countdownStarted = true
            mainHandler.postDelayed(countdownTick, TICK_MS)
        }
    }

    private fun playSfx(mixer: AndroidBattleAudioMixer, cue: CocosBattleSfx) {
        when (cue) {
            CocosBattleSfx.HIT_NORMAL -> mixer.playSfx(R.raw.hit_normal)
            CocosBattleSfx.HIT_CRIT -> mixer.playSfx(R.raw.hit_crit)
            CocosBattleSfx.ANSWER_WRONG -> mixer.playSfx(R.raw.answer_wrong)
            CocosBattleSfx.PLAYER_HURT -> mixer.playSfx(R.raw.player_hurt)
            CocosBattleSfx.MONSTER_DEFEAT -> mixer.playSfx(R.raw.monster_defeat)
            CocosBattleSfx.VICTORY -> mixer.playVictory()
            CocosBattleSfx.DEFEAT -> mixer.playDefeat()
        }
    }

    private fun fallbackToNative() {
        fallbackActive = true
        postOutcomeAndFinish(CocosBattleOutcome.Fallback)
    }

    private fun postOutcomeAndFinish(outcome: CocosBattleOutcome) {
        if (outcomePosted) return
        outcomePosted = true
        CocosBattleSessionHolder.postOutcome(outcome)
        finish()
    }

    override fun onResume() {
        super.onResume()
        Log.i(tag, "CocosBattleActivity onResume")
    }

    override fun onPause() {
        super.onPause()
        Log.i(tag, "CocosBattleActivity onPause")
    }

    override fun onDestroy() {
        super.onDestroy()
        JsbBridgeWrapper.getInstance()
            .removeScriptEventListener(EVENT_TO_NATIVE, transport.listener)
        bridge?.dispose()
        bridge = null
        mainHandler.removeCallbacksAndMessages(null)
        audioMixer?.dispose()
        audioMixer = null
        Log.i(tag, "CocosBattleActivity onDestroy")
    }

    /**
     * JsbBridgeWrapper ↔ [CocosTransport] adapter. Scene callbacks arrive on
     * the Cocos game thread — hop to the main looper BEFORE invoking the
     * bridge handler (bridge threading contract). Outbound dispatch is safe
     * from the main thread; pre-ready sends would be silently dropped by the
     * engine, but the bridge only ever sends in reaction to inbound scene
     * messages, so nothing is sent before the scene listens.
     */
    private class JsbTransport(private val mainHandler: Handler) : CocosTransport {
        private var handler: ((String) -> Unit)? = null

        val listener = JsbBridgeWrapper.OnScriptEventListener { json ->
            mainHandler.post { handler?.invoke(json) }
        }

        override fun send(json: String) {
            JsbBridgeWrapper.getInstance().dispatchEventToScript(EVENT_TO_SCRIPT, json)
        }

        override fun setHandler(handler: (String) -> Unit) {
            this.handler = handler
        }
    }

    private companion object {
        /** Channel names — must match cocos/assets/scripts/bridge/transport.ts. */
        const val EVENT_TO_NATIVE = "wmBattleToNative"
        const val EVENT_TO_SCRIPT = "wmBattleToScript"

        /** Countdown cadence — native battle timer parity. */
        const val TICK_MS = 1_000L

        /** BattleScreen's delay(250) before auto-speaking a new question. */
        const val AUTO_SPEAK_DELAY_MS = 250L

        /** battle/ready watchdog — HOS CocosBattlePage READY_TIMEOUT_MS parity. */
        const val READY_TIMEOUT_MS = 5_000L
    }
}
