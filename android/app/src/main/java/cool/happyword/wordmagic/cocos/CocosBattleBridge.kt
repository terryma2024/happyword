package cool.happyword.wordmagic.cocos

import cool.happyword.wordmagic.core.BattleAnswerOutcome
import cool.happyword.wordmagic.core.BattleEngine
import cool.happyword.wordmagic.core.BattleQuestionTypePolicy
import cool.happyword.wordmagic.core.BattleState
import cool.happyword.wordmagic.core.BattleStatus
import cool.happyword.wordmagic.core.GameConfig
import cool.happyword.wordmagic.core.MonsterCatalog
import cool.happyword.wordmagic.core.MonsterEntry
import cool.happyword.wordmagic.core.QuestionKind
import cool.happyword.wordmagic.core.SessionResult

/**
 * CocosBattleBridge — translates BattleEngine state and outcomes into bridge
 * messages for the embedded Cocos battle scene, and routes user intents from
 * the scene back into the engine (Android Task 1.2).
 *
 * Port of harmonyos/entry/src/main/ets/services/CocosBattleBridge.ets (which
 * itself ports the iOS CocosBattleBridge.swift), adapted to the FUNCTIONAL
 * Android engine: `core/BattleEngine` is stateless, so this adapter OWNS the
 * current [BattleState] and reassigns it after every engine call — the one
 * structural difference vs the ArkTS/Swift adapters. Battle logic stays in
 * BattleEngine; this adapter only mirrors what the native BattleScreen
 * (ui/battle/BattleUi.kt) does around it: audio cue moments, TTS moments,
 * boss-intro bookkeeping, and the result handoff.
 *
 * Threading contract: this class is NOT thread-safe and expects every entry
 * point (transport handler invocations, [sendStateTick], [dispose]) on the
 * MAIN thread. On Android, JsbBridgeWrapper delivers scene callbacks on the
 * Cocos game thread (see cocos/README.md → "Android embed"), so the real
 * [CocosTransport] implementation (Task 1.4) must hop to the main thread
 * BEFORE invoking the handler. Likewise the production [DelayScheduler] is a
 * main-Looper Handler. Pre-ready sends are silently dropped by the engine's
 * JS bridge; this adapter only ever sends in reaction to inbound scene
 * messages (everything starts at the scene's organic battle/ready), and the
 * host must not call [sendStateTick] before [CocosBattleBridgeCallbacks.onReady]
 * fired — a !ready guard backstops that. The bridge is per-activity: each
 * CocosBattleActivity entry constructs a fresh instance and gets a fresh
 * organic battle/ready (no HarmonyOS-style once-per-process ready latch).
 *
 * Timing notes (mirrors the cross-platform bridge constants):
 *   - [COCOS_FEEDBACK_HOLD_MS] (650 ms, == BATTLE_FEEDBACK_MS in
 *     ui/navigation) elapses between the submit animation and the next
 *     battle/question — the same hold the native BattleScreen keeps the
 *     answered question (and its feedback colors) on screen.
 *   - The player-hurt grunt rides a [COCOS_PLAYER_HURT_GRUNT_MS] (340 ms)
 *     delay so the voice cue lands with the scene's backward-projectile
 *     impact. The scene's projectile timing is shared across platforms, so
 *     this stays 340 ms like the iOS/HarmonyOS bridges (the native Compose
 *     screen uses its own 320 ms PROJECTILE_IMPACT_MS for its own animation).
 *   - battle/end goes out immediately; the finish callback fires once after
 *     the same 650 ms hold, preceded by the victory/defeat fanfare — the
 *     native BattleScreen does the same before onBattleFinished.
 */

/** Mirrors ui/navigation BATTLE_FEEDBACK_MS / the iOS-HOS bridge hold. */
const val COCOS_FEEDBACK_HOLD_MS: Long = 650L

/** Scene projectile travel — keeps the grunt aligned with the impact. */
const val COCOS_PLAYER_HURT_GRUNT_MS: Long = 340L

/** Player art keys shipped in the Cocos scene (same as the iOS/HOS bridges). */
private const val PLAYER_ART_IDLE = "CharacterMagician"
private const val PLAYER_ART_FIGHT = "CharacterMagicianFight"
private const val PLAYER_ART_HURT = "CharacterMagicianBeaten"

/**
 * Scene transport seam. Task 1.4 adapts JsbBridgeWrapper to this (including
 * the game-thread → main-thread hop on the inbound side); tests use an
 * in-memory fake.
 */
interface CocosTransport {
    fun send(json: String)
    fun setHandler(handler: (String) -> Unit)
}

/** Handle for a scheduled delay so [CocosBattleBridge.dispose] can cancel it. */
fun interface Cancellable {
    fun cancel()
}

/**
 * Injectable delay scheduling so unit tests run synchronously. The production
 * implementation (Task 1.4) posts to a main-Looper Handler.
 */
typealias DelayScheduler = (delayMs: Long, fn: () -> Unit) -> Cancellable

/**
 * Sound cues the bridge can request — mirrors the moments the native
 * BattleScreen plays raw resources through AndroidBattleAudioMixer.
 * The host maps: HIT_NORMAL→R.raw.hit_normal, HIT_CRIT→R.raw.hit_crit,
 * ANSWER_WRONG→R.raw.answer_wrong, PLAYER_HURT→R.raw.player_hurt,
 * MONSTER_DEFEAT→R.raw.monster_defeat, VICTORY→playVictory(),
 * DEFEAT→playDefeat(). (An enum instead of @RawRes ints keeps this file free
 * of generated-R / android.* dependencies.)
 */
enum class CocosBattleSfx {
    HIT_NORMAL,
    HIT_CRIT,
    ANSWER_WRONG,
    PLAYER_HURT,
    MONSTER_DEFEAT,
    VICTORY,
    DEFEAT,
}

/**
 * Host-provided callbacks. The hosting activity owns AndroidBattleAudioMixer
 * and the auto-speak gating — the adapter only encodes WHEN each cue fires,
 * matching the native BattleScreen:
 *
 *   onFinish(result)        → settle results + route to the result screen
 *                             (the result is engine.resultFor(currentState);
 *                             the host applies coin credit / check-in / etc.)
 *   playSfx(cue)            → AndroidBattleAudioMixer.playSfx(raw res)
 *   speakWord(word)         → AndroidBattleAudioMixer.speakWord (speaker tap)
 *   autoSpeakWord(word, k)  → gate on config.autoPronunciation and
 *                             k != QuestionKind.SentenceCloze (BattleScreen
 *                             parity), then speakWord
 *   onReady                 → fired on EVERY battle/ready; the host uses the
 *                             first invocation to cancel its ready-timeout
 *                             fallback and start the countdown timer
 */
data class CocosBattleBridgeCallbacks(
    val onFinish: (SessionResult) -> Unit,
    val playSfx: (CocosBattleSfx) -> Unit,
    val speakWord: (String) -> Unit,
    val autoSpeakWord: (word: String, kind: QuestionKind) -> Unit,
    val onReady: () -> Unit = {},
)

/**
 * Visual description of one answer outcome — port of the ArkTS/iOS
 * BattleAnimationEvent translation tables.
 */
private class BattleAnimationEvent {
    var projectileDirection: String = "forward"
    var projectileIntensity: Int = 1
    var projectileLabel: String = ""
    var playerMotion: String = "idle"
    var monsterMotion: String = "idle"
    var feedbackText: String = ""
    var showsCritOverlay: Boolean = false
    var damageLabel: String = ""
    var playsMonsterDefeatCue: Boolean = false
}

private fun eventForOutcome(outcome: BattleAnswerOutcome, word: String): BattleAnimationEvent {
    val e = BattleAnimationEvent()
    val intensity = maxOf(outcome.damage, 1)
    e.projectileLabel = word
    e.projectileIntensity = intensity
    e.damageLabel = "-$intensity!"
    e.playsMonsterDefeatCue = outcome.monsterDefeated && !outcome.battleEnded
    when {
        outcome.comboTriggered -> {
            e.projectileDirection = "forward"
            e.playerMotion = "cast"
            e.monsterMotion = "zoom"
            e.feedbackText = "Combo 3! Magic Burst x$intensity"
            e.showsCritOverlay = true
        }
        outcome.correct -> {
            e.projectileDirection = "forward"
            e.playerMotion = "nudge"
            e.monsterMotion = "hurt"
            e.feedbackText = "Correct!"
            e.showsCritOverlay = false
        }
        else -> {
            e.projectileDirection = "backward"
            e.playerMotion = "hurt"
            e.monsterMotion = "idle"
            e.feedbackText = "Correct answer: $word"
            e.showsCritOverlay = false
        }
    }
    return e
}

/** V0.8.4 — Spell letter-pool wrong tap (player −damage HP, question unchanged). */
private fun eventForSpellWrongTap(damage: Int): BattleAnimationEvent {
    val e = BattleAnimationEvent()
    e.projectileDirection = "backward"
    e.projectileIntensity = damage
    e.projectileLabel = ""
    e.playerMotion = "hurt"
    e.monsterMotion = "idle"
    e.feedbackText = "Try again"
    e.showsCritOverlay = false
    e.damageLabel = "-$damage"
    e.playsMonsterDefeatCue = false
    return e
}

// ── Monster art / catalog lookup ─────────────────────────────────────────────

private val monsterRoster: List<MonsterEntry> by lazy { MonsterCatalog.default().entries }

/**
 * Monster entry for a 1-based catalog index. Indices wrap around the roster
 * like the native BattleScreen's monster lookup; out-of-range input falls
 * back to the first entry (ArkTS BattleArtCatalog parity).
 */
internal fun monsterEntryForCatalogIndex(index1Based: Int): MonsterEntry {
    val idx0 = if (index1Based <= 0) 0 else (index1Based - 1) % monsterRoster.size
    return monsterRoster[idx0]
}

/**
 * Cocos character art key for a 1-based catalog index. The scene loads
 * monster textures from `art/characters/<imageKey>/spriteFrame`; the PNGs
 * are named `Character` + PascalCase catalog id (e.g. `snow-queen` →
 * `CharacterSnowQueen`) — same derivation as the ArkTS BattleArtCatalog.
 */
fun cocosImageKeyForCatalogIndex(index1Based: Int): String {
    val key = monsterEntryForCatalogIndex(index1Based).id
    return "Character" + key.split('-')
        .filter { it.isNotEmpty() }
        .joinToString("") { part -> part.replaceFirstChar { it.uppercaseChar() } }
}

private fun wireStatus(status: BattleStatus): String = when (status) {
    BattleStatus.Playing -> "playing"
    BattleStatus.Won -> "won"
    BattleStatus.Lost -> "lost"
}

class CocosBattleBridge(
    private val engine: BattleEngine,
    private val config: GameConfig,
    initialState: BattleState,
    private val transport: CocosTransport,
    private val callbacks: CocosBattleBridgeCallbacks,
    private val scheduler: DelayScheduler,
    private val catalogIndexProvider: (BattleState) -> Int = { it.monsterCatalogIndex },
    initialRemainingSeconds: Int = config.timerSeconds,
) {
    /**
     * The adapter-owned battle state (functional engine: every engine call
     * returns the next state, which is assigned here). Exposed so the hosting
     * activity can persist snapshots / settle results.
     */
    var currentState: BattleState = initialState
        private set

    /** Countdown is host-owned (like battleTimeLeft); mirrored for payloads. */
    private var remainingSeconds: Int = initialRemainingSeconds

    private var ready: Boolean = false
    private var finishNotified: Boolean = false

    /**
     * Set by [dispose] when the hosting activity tears down. Once true the
     * bridge is inert: inbound messages are ignored, outbound sends stop, and
     * every already-scheduled closure (question hold, hurt grunt, finish
     * hold) is cancelled and additionally no-op guarded — so no callback can
     * touch a destroyed activity.
     */
    private var disposed: Boolean = false

    /**
     * True while the 650 ms post-submit feedback hold is pending. A second
     * battle/submitOption racing the hold (double-tap in the scene) is
     * dropped so the engine receives exactly one submit per question swap —
     * parity with BattleScreen's `activeOutcome == null` guard in onAnswer.
     */
    private var holdActive: Boolean = false

    /** Mirrors the ArkTS/Swift boss-intro bookkeeping. */
    private val shownBossIntroCatalogIndices = mutableSetOf<Int>()
    private var lastBossIntroMonsterIndex: Int = 0

    private val pendingDelays = mutableListOf<Cancellable>()

    init {
        transport.setHandler { json -> handleSceneMessage(json) }
    }

    val isReady: Boolean
        get() = ready

    /**
     * Tear-down latch — call from the hosting activity's onDestroy. After
     * this, the bridge neither sends to the scene nor invokes any callback,
     * even from closures that were already scheduled before disposal.
     */
    fun dispose() {
        disposed = true
        val pending = pendingDelays.toList()
        pendingDelays.clear()
        pending.forEach { it.cancel() }
    }

    /**
     * Called by the hosting activity's 1 s countdown after it decrements its
     * own timeLeft (the functional BattleState carries no clock — the host
     * owns the countdown exactly like the native battleTimeLeft).
     */
    fun sendStateTick(remainingSeconds: Int) {
        if (disposed || !ready) return
        this.remainingSeconds = remainingSeconds.coerceAtLeast(0)
        sendState()
    }

    fun handleSceneMessage(json: String) {
        if (disposed) return
        when (val message = CocosBridgeMessages.decodeSceneMessage(json)) {
            is CocosBridgeMessages.SceneMessage.Ready -> handleReady()
            is CocosBridgeMessages.SceneMessage.SubmitOption -> handleSubmit(message.option)
            is CocosBridgeMessages.SceneMessage.SpellWrongTap -> handleSpellWrongTap()
            is CocosBridgeMessages.SceneMessage.SpeakAnswer -> handleSpeakAnswer()
            is CocosBridgeMessages.SceneMessage.Escape -> handleEscape()
            is CocosBridgeMessages.SceneMessage.Pong -> Unit // health-check reply
            null -> Unit // unknown / invalid message — ignore
        }
    }

    // ── Inbound handlers ─────────────────────────────────────────────────────

    /**
     * battle/ready acts as a full scene reset (contract README): re-send
     * init + state + question every time. On Android every activity entry
     * yields a fresh organic ready (cocos/README.md re-entry verdict).
     */
    private fun handleReady() {
        ready = true
        callbacks.onReady()
        sendInit()
        sendState()
        sendQuestion()
        maybeSendBossIntro()
        autoSpeakCurrent()
    }

    /** Mirrors BattleScreen.onAnswer / SpellAnswerArea.onComplete around the engine. */
    private fun handleSubmit(option: String) {
        if (holdActive) {
            // Duplicate tap racing the 650 ms feedback hold — drop it
            // (BattleScreen parity: option buttons are disabled while
            // activeOutcome is non-null).
            return
        }
        if (currentState.status != BattleStatus.Playing) return
        val answeredQuestion = currentState.question

        val outcome = engine.submitAnswerWithOutcome(currentState, option)
        currentState = outcome.nextState

        if (outcome.advancedStep) {
            // fill-letter-medium step advance: no damage, no animation —
            // resync the mutated question in place. The native screen plays
            // the normal hit cue here.
            callbacks.playSfx(CocosBattleSfx.HIT_NORMAL)
            sendState()
            sendQuestion()
            return
        }

        val event = eventForOutcome(outcome, answeredQuestion.correctAnswer)
        playSubmitAudio(outcome)
        sendAnimation(event, outcome.correct, outcome.comboTriggered, outcome.battleEnded)
        sendState()

        if (outcome.battleEnded) {
            finishAfterFeedbackHold(currentState.status)
            return
        }
        // Mirror the native feedback hold: the answered question (and its
        // feedback) stays on screen 650 ms before the next question swaps in.
        holdActive = true
        schedule(COCOS_FEEDBACK_HOLD_MS) {
            holdActive = false
            if (disposed) return@schedule
            sendQuestion()
            maybeSendBossIntro()
            autoSpeakCurrent()
        }
    }

    /** Mirrors BattleScreen.onSpellWrongTap (engine.spellLetterPenaltyOutcome). */
    private fun handleSpellWrongTap() {
        val outcome = engine.spellLetterPenaltyOutcome(currentState)
        if (outcome.damage <= 0 || !outcome.playerDamaged) return
        currentState = outcome.nextState
        callbacks.playSfx(CocosBattleSfx.ANSWER_WRONG)
        schedulePlayerHurtGrunt()
        val lost = currentState.status == BattleStatus.Lost
        sendAnimation(
            eventForSpellWrongTap(outcome.damage),
            correct = false,
            comboTriggered = false,
            battleEnded = lost,
        )
        sendState()
        if (lost) {
            finishAfterFeedbackHold(BattleStatus.Lost)
        }
    }

    /** Speaker tap in the scene — BattleScreen parity: speakWord(question.correctAnswer). */
    private fun handleSpeakAnswer() {
        val word = currentState.question.correctAnswer
        if (word.isNotEmpty()) {
            callbacks.speakWord(word)
        }
    }

    /**
     * Mirrors the native onEscape: settle the state as Lost and hand the
     * built result to the host immediately — no battle/end, no hold.
     */
    private fun handleEscape() {
        if (currentState.status == BattleStatus.Playing) {
            currentState = currentState.copy(status = BattleStatus.Lost)
        }
        if (finishNotified) return
        finishNotified = true
        callbacks.onFinish(engine.resultFor(currentState))
    }

    // ── Audio (BattleScreen cue moments) ─────────────────────────────────────

    private fun playSubmitAudio(outcome: BattleAnswerOutcome) {
        when {
            outcome.comboTriggered -> callbacks.playSfx(CocosBattleSfx.HIT_CRIT)
            outcome.correct -> callbacks.playSfx(CocosBattleSfx.HIT_NORMAL)
            else -> {
                callbacks.playSfx(CocosBattleSfx.ANSWER_WRONG)
                schedulePlayerHurtGrunt()
            }
        }
        // Layered defeat cue when the final blow landed but the battle goes
        // on; the win-side fanfare is handled in finishAfterFeedbackHold.
        if (outcome.monsterDefeated && !outcome.battleEnded) {
            callbacks.playSfx(CocosBattleSfx.MONSTER_DEFEAT)
        }
    }

    private fun schedulePlayerHurtGrunt() {
        schedule(COCOS_PLAYER_HURT_GRUNT_MS) {
            if (disposed) return@schedule
            callbacks.playSfx(CocosBattleSfx.PLAYER_HURT)
        }
    }

    private fun autoSpeakCurrent() {
        val question = currentState.question
        if (question.correctAnswer.isNotEmpty()) {
            callbacks.autoSpeakWord(question.correctAnswer, question.kind)
        }
    }

    // ── Finish flow ──────────────────────────────────────────────────────────

    private fun finishAfterFeedbackHold(endStatus: BattleStatus) {
        send(CocosBridgeMessages.encodeEnd(if (endStatus == BattleStatus.Won) "won" else "lost"))
        schedule(COCOS_FEEDBACK_HOLD_MS) {
            if (disposed || finishNotified) return@schedule
            finishNotified = true
            // Terminal fanfare just before the handoff (BattleScreen parity:
            // playVictory()/playDefeat() before onBattleFinished).
            callbacks.playSfx(
                if (endStatus == BattleStatus.Won) CocosBattleSfx.VICTORY else CocosBattleSfx.DEFEAT,
            )
            callbacks.onFinish(engine.resultFor(currentState))
        }
    }

    // ── Outbound ─────────────────────────────────────────────────────────────

    private fun send(json: String) {
        if (disposed) return
        transport.send(json)
    }

    private fun sendInit() {
        send(
            CocosBridgeMessages.encodeInit(
                playerMaxHp = config.playerHp,
                monsterMaxHp = config.monsterHp,
                monstersTotal = config.monsterCount,
                startingSeconds = remainingSeconds,
                playerArtIdle = PLAYER_ART_IDLE,
                playerArtFight = PLAYER_ART_FIGHT,
                playerArtHurt = PLAYER_ART_HURT,
            ),
        )
    }

    private fun sendState() {
        val state = currentState
        val catalogIndex = catalogIndexProvider(state)
        val entry = monsterEntryForCatalogIndex(catalogIndex)
        send(
            CocosBridgeMessages.encodeState(
                playerHp = state.playerHp,
                playerMaxHp = config.playerHp,
                monsterHp = state.monsterHp,
                monsterMaxHp = config.monsterHp,
                monsterIndex = state.monsterIndex,
                monstersTotal = config.monsterCount,
                remainingSeconds = remainingSeconds,
                comboCount = state.combo,
                status = wireStatus(state.status),
                monsterCatalogIndex = catalogIndex,
                monsterImageKey = cocosImageKeyForCatalogIndex(catalogIndex),
                monsterName = entry.nameEn,
                monsterLevelLabel = entry.battleLevelLabel,
                monsterBonus = state.currentMonsterBonus,
            ),
        )
    }

    private fun sendQuestion() {
        val q = currentState.question
        send(
            CocosBridgeMessages.encodeQuestion(
                wordId = q.wordId,
                kind = BattleQuestionTypePolicy.kindToTypeId(q.kind),
                promptZh = q.prompt,
                answer = q.correctAnswer,
                options = q.options,
                letterTemplate = q.letterTemplate,
                missingIndex = q.missingIndex,
                letterOptions = q.letterOptions,
                letterAnswer = q.letterAnswer,
                letterTemplateBase = q.letterTemplateBase,
                missingIndices = q.missingIndices,
                letterOptionsSteps = q.letterOptionsSteps,
                letterAnswers = q.letterAnswers,
                currentStep = q.currentStep,
                spellLetters = q.spellLetters,
                spellRevealedMask = q.spellRevealedMask,
                spellPool = q.spellPool,
                sentenceTemplate = q.sentenceTemplate,
                sentenceZh = q.sentenceZh,
            ),
        )
    }

    private fun sendAnimation(
        event: BattleAnimationEvent,
        correct: Boolean,
        comboTriggered: Boolean,
        battleEnded: Boolean,
    ) {
        send(
            CocosBridgeMessages.encodeAnimation(
                projectileDirection = event.projectileDirection,
                projectileIntensity = event.projectileIntensity,
                projectileLabel = event.projectileLabel,
                playerMotion = event.playerMotion,
                monsterMotion = event.monsterMotion,
                feedbackText = event.feedbackText,
                showsCritOverlay = event.showsCritOverlay,
                damageLabel = event.damageLabel,
                playsMonsterDefeatCue = event.playsMonsterDefeatCue,
                correct = correct,
                comboTriggered = comboTriggered,
                battleEnded = battleEnded,
            ),
        )
    }

    /**
     * Mirrors the Swift/ArkTS maybeSendBossIntro bookkeeping exactly: an
     * intro is sent the first time a monster's CATALOG index is seen, and
     * only when the engine's monster slot actually changed. The scene owns
     * the auto-dismiss. Dialogue comes from the monster catalog like the
     * native BossIntroBubble.
     */
    private fun maybeSendBossIntro() {
        val state = currentState
        if (state.status != BattleStatus.Playing) return
        val catalogIndex = catalogIndexProvider(state)
        if (state.monsterIndex == lastBossIntroMonsterIndex ||
            shownBossIntroCatalogIndices.contains(catalogIndex)
        ) {
            return
        }
        val entry = monsterEntryForCatalogIndex(catalogIndex)
        send(
            CocosBridgeMessages.encodeBossIntro(
                monsterIndex = state.monsterIndex,
                name = entry.nameEn,
                introLineEn = entry.dialogue.introLine.en,
                introLineZh = entry.dialogue.introLine.zh,
            ),
        )
        shownBossIntroCatalogIndices.add(catalogIndex)
        lastBossIntroMonsterIndex = state.monsterIndex
    }

    // ── Scheduling ───────────────────────────────────────────────────────────

    private fun schedule(delayMs: Long, fn: () -> Unit) {
        val box = arrayOfNulls<Cancellable>(1)
        val handle = scheduler(delayMs) {
            box[0]?.let(pendingDelays::remove)
            fn()
        }
        box[0] = handle
        pendingDelays.add(handle)
    }
}
