package cool.happyword.wordmagic.cocos

import cool.happyword.wordmagic.core.BattleAnswerOutcome
import cool.happyword.wordmagic.core.BattleEngine
import cool.happyword.wordmagic.core.BattleQuestionTypePolicy
import cool.happyword.wordmagic.core.BattleState
import cool.happyword.wordmagic.core.BattleStatus
import cool.happyword.wordmagic.core.GameConfig
import cool.happyword.wordmagic.core.MonsterCatalog
import cool.happyword.wordmagic.core.Question
import cool.happyword.wordmagic.core.QuestionKind
import cool.happyword.wordmagic.core.SessionResult
import cool.happyword.wordmagic.core.WordEntry
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Port of harmonyos/entry/src/test/CocosBattleBridge.test.ets, adapted to the
 * functional Android BattleEngine (the bridge owns the BattleState; tests read
 * the live question from bridge.currentState instead of a stubbed source).
 */
class CocosBattleBridgeTest {

    // ── Fakes ────────────────────────────────────────────────────────────────

    private class FakeTransport : CocosTransport {
        val sent = mutableListOf<String>()
        private var handler: (String) -> Unit = {}

        override fun send(json: String) {
            sent.add(json)
        }

        override fun setHandler(handler: (String) -> Unit) {
            this.handler = handler
        }

        fun inject(json: String) = handler(json)

        fun clear() = sent.clear()

        fun sentTypes(): List<String> = sent.map { JSONObject(it).getString("type") }

        fun lastPayloadOfType(type: String): JSONObject? {
            for (i in sent.indices.reversed()) {
                val msg = JSONObject(sent[i])
                if (msg.getString("type") == type) return msg.getJSONObject("payload")
            }
            return null
        }
    }

    private class FakeScheduler {
        class Call(val delayMs: Long, val fn: () -> Unit) {
            var cancelled = false
        }

        val calls = mutableListOf<Call>()

        fun schedule(delayMs: Long, fn: () -> Unit): Cancellable {
            val call = Call(delayMs, fn)
            calls.add(call)
            return Cancellable { call.cancelled = true }
        }

        /** Run and drain everything currently scheduled (not re-entrant safe; fine for tests). */
        fun runAll() {
            val pending = calls.toList()
            calls.clear()
            for (call in pending) {
                if (!call.cancelled) call.fn()
            }
        }
    }

    private class RecordingCallbacks {
        val finishResults = mutableListOf<SessionResult>()
        val sfx = mutableListOf<CocosBattleSfx>()
        val spoken = mutableListOf<String>()
        val autoSpoken = mutableListOf<String>()
        val answerOutcomes = mutableListOf<Pair<BattleState, BattleAnswerOutcome>>()
        var readyCount = 0

        fun asCallbacks(): CocosBattleBridgeCallbacks = CocosBattleBridgeCallbacks(
            onFinish = { finishResults.add(it) },
            playSfx = { sfx.add(it) },
            speakWord = { spoken.add(it) },
            autoSpeakWord = { word, _ -> autoSpoken.add(word) },
            onReady = { readyCount += 1 },
            onAnswerOutcome = { preState, outcome -> answerOutcomes.add(preState to outcome) },
        )
    }

    // ── Harness ──────────────────────────────────────────────────────────────

    private class Harness(
        monstersTotal: Int,
        monsterMaxHp: Int,
        playerMaxHp: Int,
        enabledTypes: List<String> = listOf(BattleQuestionTypePolicy.CHOICE),
        words: List<WordEntry> = defaultWords,
        randomDouble: () -> Double = { 0.99 },
    ) {
        val config = GameConfig(
            playerHp = playerMaxHp,
            monsterHp = monsterMaxHp,
            monsterCount = monstersTotal,
            timerSeconds = 300,
            enabledQuestionTypes = enabledTypes,
        )
        val engine = BattleEngine(
            config = config,
            words = words,
            targetWordIds = words.map { it.id },
            shuffleOptions = { it },
            randomDouble = randomDouble,
            monsterCatalogIndex = { it },
        )
        val transport = FakeTransport()
        val scheduler = FakeScheduler()
        val callbacks = RecordingCallbacks()
        val bridge = CocosBattleBridge(
            engine = engine,
            config = config,
            initialState = engine.initialState(),
            transport = transport,
            callbacks = callbacks.asCallbacks(),
            scheduler = { delayMs, fn -> scheduler.schedule(delayMs, fn) },
        )

        val state: BattleState
            get() = bridge.currentState

        fun injectReady() = transport.inject("""{"v":1,"type":"battle/ready","payload":{}}""")

        fun injectSubmit(option: String) =
            transport.inject("""{"v":1,"type":"battle/submitOption","payload":{"option":"$option"}}""")

        fun injectCorrect(): String {
            val answer = answerFor()
            injectSubmit(answer)
            return answer
        }

        fun answerFor(): String = when (state.question.kind) {
            QuestionKind.FillLetter -> state.question.letterAnswer
            QuestionKind.FillLetterMedium -> state.question.letterAnswers[state.question.currentStep]
            else -> state.question.correctAnswer
        }

        fun wrongOptionFor(): String =
            state.question.options.first { it != state.question.correctAnswer }

        fun totalAnswers(): Int = state.correctCount + state.wrongCount

        companion object {
            val defaultWords = listOf(
                WordEntry("w-cat", "cat", "猫"),
                WordEntry("w-dog", "dog", "狗"),
                WordEntry("w-pig", "pig", "猪"),
            )

            /** Same word set BattleQuestionTypeTest uses to force medium fill-letter. */
            val mediumWords = listOf(
                WordEntry("fruit-apple", "apple", "苹果"),
                WordEntry("fruit-banana", "banana", "香蕉"),
                WordEntry("fruit-orange", "orange", "橙子"),
                WordEntry("animal-monkey", "monkey", "猴子"),
                WordEntry("place-garden", "garden", "花园"),
            )
        }
    }

    private fun makeHarness(monstersTotal: Int, monsterMaxHp: Int, playerMaxHp: Int): Harness =
        Harness(monstersTotal, monsterMaxHp, playerMaxHp)

    // ── Cases (ported from CocosBattleBridge.test.ets) ───────────────────────

    @Test
    fun readySendsInitStateQuestionAndBossIntro() {
        val h = makeHarness(2, 5, 10)
        h.injectReady()

        assertTrue(h.bridge.isReady)
        assertEquals(
            listOf("battle/init", "battle/state", "battle/question", "battle/bossIntro"),
            h.transport.sentTypes(),
        )

        val init = h.transport.lastPayloadOfType("battle/init")
        assertNotNull(init)
        assertEquals(10, init!!.getInt("playerMaxHp"))
        assertEquals(5, init.getInt("monsterMaxHp"))
        assertEquals(2, init.getInt("monstersTotal"))
        assertEquals(300, init.getInt("startingSeconds"))

        val state = h.transport.lastPayloadOfType("battle/state")
        assertNotNull(state)
        assertEquals("playing", state!!.getString("status"))
        val monster = state.getJSONObject("monster")
        assertEquals(1, monster.getInt("catalogIndex"))
        assertEquals("CharacterSlime", monster.getString("imageKey"))
        assertEquals("L1", monster.getString("levelLabel"))

        val question = h.transport.lastPayloadOfType("battle/question")
        assertNotNull(question)
        assertEquals(h.state.question.correctAnswer, question!!.getString("answer"))
        assertEquals("choice", question.getString("kind"))

        val intro = h.transport.lastPayloadOfType("battle/bossIntro")
        assertNotNull(intro)
        assertEquals(1, intro!!.getInt("monsterIndex"))
        assertTrue(intro.getString("introLineEn").isNotEmpty())

        // First question auto-speaks the answer through the hook.
        assertEquals(listOf(h.state.question.correctAnswer), h.callbacks.autoSpoken)
        // Nothing rides the delay scheduler on ready.
        assertEquals(0, h.scheduler.calls.size)
    }

    @Test
    fun correctSubmitSendsAnimationStateThenQuestionAfterHold() {
        val h = makeHarness(5, 5, 10)
        h.injectReady()
        h.transport.clear()

        h.injectCorrect()

        assertEquals(1, h.totalAnswers())
        assertEquals(listOf("battle/animation", "battle/state"), h.transport.sentTypes())
        val animation = h.transport.lastPayloadOfType("battle/animation")!!
        assertTrue(animation.getBoolean("correct"))
        assertEquals("forward", animation.getString("projectileDirection"))
        assertEquals("nudge", animation.getString("playerMotion"))
        assertEquals("hurt", animation.getString("monsterMotion"))
        assertEquals("Correct!", animation.getString("feedbackText"))
        assertEquals("-1!", animation.getString("damageLabel"))
        assertFalse(animation.getBoolean("battleEnded"))
        assertEquals(listOf(CocosBattleSfx.HIT_NORMAL), h.callbacks.sfx)

        // Next question goes out only after the 650 ms feedback hold.
        assertEquals(1, h.scheduler.calls.size)
        assertEquals(COCOS_FEEDBACK_HOLD_MS, h.scheduler.calls[0].delayMs)
        h.scheduler.runAll()
        assertEquals(
            listOf("battle/animation", "battle/state", "battle/question"),
            h.transport.sentTypes(),
        )
        // Auto-speak fires again for the next question (ready + post-hold).
        assertEquals(2, h.callbacks.autoSpoken.size)
        assertEquals(h.state.question.correctAnswer, h.callbacks.autoSpoken[1])
    }

    @Test
    fun wrongSubmitSendsBackwardAnimationWithoutMonsterDamage() {
        val h = makeHarness(5, 5, 10)
        h.injectReady()
        h.transport.clear()
        val monsterHpBefore = h.state.monsterHp
        val answeredWord = h.state.question.correctAnswer

        h.injectSubmit(h.wrongOptionFor())

        assertEquals(monsterHpBefore, h.state.monsterHp)
        assertEquals(9, h.state.playerHp)
        assertEquals(listOf("battle/animation", "battle/state"), h.transport.sentTypes())
        val animation = h.transport.lastPayloadOfType("battle/animation")!!
        assertFalse(animation.getBoolean("correct"))
        assertEquals("backward", animation.getString("projectileDirection"))
        assertEquals("hurt", animation.getString("playerMotion"))
        assertEquals("idle", animation.getString("monsterMotion"))
        assertEquals("Correct answer: $answeredWord", animation.getString("feedbackText"))

        // Wrong answer plays buzzer immediately and schedules the hurt grunt
        // for the projectile impact, then the question hold.
        assertEquals(listOf(CocosBattleSfx.ANSWER_WRONG), h.callbacks.sfx)
        assertEquals(2, h.scheduler.calls.size)
        assertEquals(COCOS_PLAYER_HURT_GRUNT_MS, h.scheduler.calls[0].delayMs)
        assertEquals(COCOS_FEEDBACK_HOLD_MS, h.scheduler.calls[1].delayMs)
        h.scheduler.runAll()
        assertEquals(listOf(CocosBattleSfx.ANSWER_WRONG, CocosBattleSfx.PLAYER_HURT), h.callbacks.sfx)
        assertEquals(
            listOf("battle/animation", "battle/state", "battle/question"),
            h.transport.sentTypes(),
        )
    }

    @Test
    fun comboBurstSendsCritAnimationAndCritSfx() {
        val h = makeHarness(5, 5, 10)
        h.injectReady()
        // Drain the feedback hold between answers — submits racing the hold
        // are dropped by design (see duplicateSubmitDuringFeedbackHoldIsDropped).
        h.injectCorrect()
        h.scheduler.runAll()
        h.injectCorrect()
        h.scheduler.runAll()
        h.transport.clear()
        h.callbacks.sfx.clear()

        h.injectCorrect()

        val animation = h.transport.lastPayloadOfType("battle/animation")!!
        assertTrue(animation.getBoolean("comboTriggered"))
        assertTrue(animation.getBoolean("showsCritOverlay"))
        assertEquals(2, animation.getInt("projectileIntensity"))
        assertEquals("cast", animation.getString("playerMotion"))
        assertEquals("zoom", animation.getString("monsterMotion"))
        assertEquals("Combo 3! Magic Burst x2", animation.getString("feedbackText"))
        assertEquals("-2!", animation.getString("damageLabel"))
        assertEquals(listOf(CocosBattleSfx.HIT_CRIT), h.callbacks.sfx)
    }

    @Test
    fun monsterDefeatMidBattlePlaysDefeatCueAndIntroducesNextMonster() {
        val h = makeHarness(2, 1, 10)
        h.injectReady()
        h.transport.clear()
        h.callbacks.sfx.clear()

        h.injectCorrect()

        val animation = h.transport.lastPayloadOfType("battle/animation")!!
        assertTrue(animation.getBoolean("playsMonsterDefeatCue"))
        assertFalse(animation.getBoolean("battleEnded"))
        assertEquals(listOf(CocosBattleSfx.HIT_NORMAL, CocosBattleSfx.MONSTER_DEFEAT), h.callbacks.sfx)

        h.scheduler.runAll()
        assertEquals(
            listOf("battle/animation", "battle/state", "battle/question", "battle/bossIntro"),
            h.transport.sentTypes(),
        )
        val intro = h.transport.lastPayloadOfType("battle/bossIntro")!!
        assertEquals(2, intro.getInt("monsterIndex"))
    }

    @Test
    fun mediumStepAdvanceResendsStateAndQuestionImmediately() {
        val h = Harness(
            monstersTotal = 5,
            monsterMaxHp = 99,
            playerMaxHp = 10,
            enabledTypes = listOf(BattleQuestionTypePolicy.FILL_LETTER_MEDIUM),
            words = Harness.mediumWords,
            randomDouble = { 0.999 },
        )
        h.injectReady()
        assertEquals(QuestionKind.FillLetterMedium, h.state.question.kind)
        val firstAnswer = h.state.question.letterAnswers[0]
        h.transport.clear()
        h.callbacks.sfx.clear()

        h.injectSubmit(firstAnswer)

        // No damage, no animation, no hold: state + in-place question update only.
        assertEquals(listOf("battle/state", "battle/question"), h.transport.sentTypes())
        assertEquals(0, h.scheduler.calls.size)
        assertEquals(listOf(CocosBattleSfx.HIT_NORMAL), h.callbacks.sfx)
        val question = h.transport.lastPayloadOfType("battle/question")!!
        assertEquals(1, question.getInt("currentStep"))
        assertTrue(question.getString("letterTemplateBase").contains(firstAnswer))
        assertEquals(1, question.getString("letterTemplateBase").count { it == '_' })
    }

    @Test
    fun spellWrongTapSendsPenaltyAnimationAndState() {
        val h = makeHarness(2, 5, 10)
        h.injectReady()
        h.transport.clear()
        h.callbacks.sfx.clear()

        h.transport.inject("""{"v":1,"type":"battle/spellWrongTap","payload":{}}""")

        assertEquals(9, h.state.playerHp)
        assertEquals(listOf("battle/animation", "battle/state"), h.transport.sentTypes())
        val animation = h.transport.lastPayloadOfType("battle/animation")!!
        assertEquals("Try again", animation.getString("feedbackText"))
        assertEquals("backward", animation.getString("projectileDirection"))
        assertEquals("-1", animation.getString("damageLabel"))
        assertFalse(animation.getBoolean("battleEnded"))
        assertEquals(listOf(CocosBattleSfx.ANSWER_WRONG), h.callbacks.sfx)
        // Hurt grunt rides the impact delay.
        assertEquals(1, h.scheduler.calls.size)
        assertEquals(COCOS_PLAYER_HURT_GRUNT_MS, h.scheduler.calls[0].delayMs)
        h.scheduler.runAll()
        assertEquals(listOf(CocosBattleSfx.ANSWER_WRONG, CocosBattleSfx.PLAYER_HURT), h.callbacks.sfx)
    }

    @Test
    fun spellWrongTapAtOneHpEndsBattleLost() {
        val h = makeHarness(2, 5, 1)
        h.injectReady()
        h.transport.clear()

        h.transport.inject("""{"v":1,"type":"battle/spellWrongTap","payload":{}}""")

        assertEquals(
            listOf("battle/animation", "battle/state", "battle/end"),
            h.transport.sentTypes(),
        )
        val animation = h.transport.lastPayloadOfType("battle/animation")!!
        assertTrue(animation.getBoolean("battleEnded"))
        val end = h.transport.lastPayloadOfType("battle/end")!!
        assertEquals("lost", end.getString("status"))
        h.scheduler.runAll()
        assertEquals(1, h.callbacks.finishResults.size)
        assertFalse(h.callbacks.finishResults[0].won)
        assertTrue(h.callbacks.sfx.contains(CocosBattleSfx.DEFEAT))
    }

    @Test
    fun speakAnswerInvokesSpeakHookWithoutSceneTraffic() {
        val h = makeHarness(2, 5, 10)
        h.injectReady()
        h.transport.clear()

        h.transport.inject("""{"v":1,"type":"battle/speakAnswer","payload":{}}""")

        assertEquals(listOf(h.state.question.correctAnswer), h.callbacks.spoken)
        assertEquals(0, h.transport.sent.size)
    }

    @Test
    fun escapeInvokesFinishWithBuiltSessionResult() {
        val h = makeHarness(2, 5, 10)
        h.injectReady()
        h.transport.clear()

        h.transport.inject("""{"v":1,"type":"battle/escape","payload":{}}""")

        // Escape routes immediately — no battle/end and no delay.
        assertEquals(0, h.transport.sent.size)
        assertEquals(0, h.scheduler.calls.size)
        assertEquals(1, h.callbacks.finishResults.size)
        assertFalse(h.callbacks.finishResults[0].won)
        // The bridge-owned state settled to Lost (native onEscape parity).
        assertEquals(cool.happyword.wordmagic.core.BattleStatus.Lost, h.state.status)
    }

    @Test
    fun winningFinalMonsterSendsEndAndFinishesOnce() {
        val h = makeHarness(1, 1, 10)
        h.injectReady()
        h.transport.clear()
        h.callbacks.sfx.clear()

        h.injectCorrect()

        assertEquals(
            listOf("battle/animation", "battle/state", "battle/end"),
            h.transport.sentTypes(),
        )
        val end = h.transport.lastPayloadOfType("battle/end")!!
        assertEquals("won", end.getString("status"))
        // No defeat cue layered on the final blow (the end fanfare covers it).
        val animation = h.transport.lastPayloadOfType("battle/animation")!!
        assertFalse(animation.getBoolean("playsMonsterDefeatCue"))
        assertTrue(animation.getBoolean("battleEnded"))

        assertEquals(1, h.scheduler.calls.size)
        assertEquals(COCOS_FEEDBACK_HOLD_MS, h.scheduler.calls[0].delayMs)
        val call = h.scheduler.calls[0]
        call.fn()
        call.fn() // double fire must not finish twice
        assertEquals(1, h.callbacks.finishResults.size)
        assertTrue(h.callbacks.finishResults[0].won)
        assertTrue(h.callbacks.sfx.contains(CocosBattleSfx.VICTORY))
    }

    @Test
    fun secondReadyResendsFullInitStateQuestion() {
        val h = makeHarness(2, 5, 10)
        h.injectReady()
        h.transport.clear()

        h.injectReady()

        // Full reset replay — but the monster-1 intro was already shown.
        assertEquals(
            listOf("battle/init", "battle/state", "battle/question"),
            h.transport.sentTypes(),
        )
    }

    @Test
    fun sendStateTickSendsStateOnly() {
        val h = makeHarness(2, 5, 10)
        h.injectReady()
        h.transport.clear()

        h.bridge.sendStateTick(299)

        assertEquals(listOf("battle/state"), h.transport.sentTypes())
        val state = h.transport.lastPayloadOfType("battle/state")!!
        assertEquals(299, state.getInt("remainingSeconds"))
    }

    @Test
    fun garbageMessagesAreIgnored() {
        val h = makeHarness(2, 5, 10)

        h.transport.inject("not json at all")
        h.transport.inject("""{"v":1,"type":"battle/unknown","payload":{}}""")

        assertFalse(h.bridge.isReady)
        assertEquals(0, h.transport.sent.size)
    }

    @Test
    fun onReadyHookFiresOnEveryReady() {
        val h = makeHarness(2, 5, 10)
        assertEquals(0, h.callbacks.readyCount)

        h.injectReady()
        assertEquals(1, h.callbacks.readyCount)

        // Re-entry replay fires it again (Android: fresh organic ready per entry).
        h.injectReady()
        assertEquals(2, h.callbacks.readyCount)
    }

    @Test
    fun duplicateSubmitDuringFeedbackHoldIsDropped() {
        val h = makeHarness(5, 5, 10)
        h.injectReady()
        h.transport.clear()

        h.injectCorrect()
        // Second tap racing the 650 ms hold — engine must see exactly one answer.
        h.injectSubmit(h.state.question.correctAnswer)

        assertEquals(1, h.totalAnswers())
        assertEquals(listOf("battle/animation", "battle/state"), h.transport.sentTypes())

        // After the hold elapses the next submit is accepted again.
        h.scheduler.runAll()
        h.injectCorrect()
        assertEquals(2, h.totalAnswers())
    }

    @Test
    fun disposeMakesScheduledQuestionClosureANoOp() {
        val h = makeHarness(5, 5, 10)
        h.injectReady()
        h.transport.clear()
        h.callbacks.autoSpoken.clear()

        h.injectCorrect()
        assertEquals(1, h.scheduler.calls.size)
        h.bridge.dispose()
        h.scheduler.runAll()

        // No battle/question after the hold, no auto-speak callback.
        assertEquals(listOf("battle/animation", "battle/state"), h.transport.sentTypes())
        assertEquals(0, h.callbacks.autoSpoken.size)
    }

    @Test
    fun disposeMakesFinishHoldClosureANoOp() {
        val h = makeHarness(1, 1, 10)
        h.injectReady()
        h.transport.clear()
        h.callbacks.sfx.clear()

        h.injectCorrect()
        assertNotNull(h.transport.lastPayloadOfType("battle/end"))
        h.bridge.dispose()
        h.scheduler.runAll()

        // Page tore down before the 650 ms finish hold: no onFinish, no fanfare.
        assertEquals(0, h.callbacks.finishResults.size)
        assertFalse(h.callbacks.sfx.contains(CocosBattleSfx.VICTORY))
    }

    @Test
    fun disposeCancelsPendingScheduledWork() {
        val h = makeHarness(5, 5, 10)
        h.injectReady()
        h.injectCorrect()
        assertEquals(1, h.scheduler.calls.size)
        assertFalse(h.scheduler.calls[0].cancelled)

        h.bridge.dispose()

        // The bridge cancels its scheduled closures eagerly via Cancellable.
        assertTrue(h.scheduler.calls[0].cancelled)
    }

    @Test
    fun messagesAndTicksAfterDisposeAreIgnored() {
        val h = makeHarness(2, 5, 10)
        h.injectReady()
        h.transport.clear()
        h.callbacks.spoken.clear()

        h.bridge.dispose()

        h.injectSubmit(h.state.question.correctAnswer)
        h.transport.inject("""{"v":1,"type":"battle/speakAnswer","payload":{}}""")
        h.transport.inject("""{"v":1,"type":"battle/escape","payload":{}}""")
        h.bridge.sendStateTick(299)

        assertEquals(0, h.totalAnswers())
        assertEquals(0, h.transport.sent.size)
        assertEquals(0, h.callbacks.spoken.size)
        assertEquals(0, h.callbacks.finishResults.size)
    }

    // ── onAnswerOutcome (per-answer side-effects hook) ───────────────────────

    @Test
    fun answerOutcomeFiresOncePerAcceptedSubmitWithPreSubmitState() {
        val h = makeHarness(5, 5, 10)
        h.injectReady()
        val preState = h.state

        h.injectCorrect()

        assertEquals(1, h.callbacks.answerOutcomes.size)
        val (pre, outcome) = h.callbacks.answerOutcomes[0]
        // The hook receives the PRE-submit state (recordMonsterDefeat needs
        // the pre-answer monsterCatalogIndex) and the engine outcome.
        assertEquals(preState, pre)
        assertTrue(outcome.correct)
        assertEquals(h.state, outcome.nextState)

        // Next accepted submit fires it again — exactly once each.
        h.scheduler.runAll()
        h.injectCorrect()
        assertEquals(2, h.callbacks.answerOutcomes.size)
    }

    @Test
    fun answerOutcomeNotFiredForDuplicateSubmitDuringFeedbackHold() {
        val h = makeHarness(5, 5, 10)
        h.injectReady()

        h.injectCorrect()
        // Second tap racing the 650 ms hold — dropped before the engine call,
        // so no side-effects hook either.
        h.injectSubmit(h.state.question.correctAnswer)

        assertEquals(1, h.totalAnswers())
        assertEquals(1, h.callbacks.answerOutcomes.size)
    }

    @Test
    fun answerOutcomeNotFiredAfterDispose() {
        val h = makeHarness(5, 5, 10)
        h.injectReady()
        h.bridge.dispose()

        h.injectSubmit(h.state.question.correctAnswer)

        assertEquals(0, h.callbacks.answerOutcomes.size)
    }

    @Test
    fun answerOutcomeNotFiredForSubmitsAfterBattleEnd() {
        val h = makeHarness(1, 1, 10)
        h.injectReady()

        h.injectCorrect() // final blow — battle Won
        assertEquals(1, h.callbacks.answerOutcomes.size)

        // Racing the finish hold and after it: status != Playing drops both.
        h.injectSubmit(h.state.question.correctAnswer)
        h.scheduler.runAll()
        h.injectSubmit(h.state.question.correctAnswer)
        assertEquals(1, h.callbacks.answerOutcomes.size)
    }

    @Test
    fun answerOutcomeNotFiredForSpellWrongTap() {
        val h = makeHarness(2, 5, 10)
        h.injectReady()

        h.transport.inject("""{"v":1,"type":"battle/spellWrongTap","payload":{}}""")

        // Native BattleScreen parity: onSpellWrongTap records no learning.
        assertEquals(9, h.state.playerHp)
        assertEquals(0, h.callbacks.answerOutcomes.size)
    }

    @Test
    fun answerOutcomeFiresForMediumStepAdvance() {
        // Native parity: the BattleScreen onAnswer lambda runs (and records
        // learning) for fill-letter-medium step advances too.
        val h = Harness(
            monstersTotal = 5,
            monsterMaxHp = 99,
            playerMaxHp = 10,
            enabledTypes = listOf(BattleQuestionTypePolicy.FILL_LETTER_MEDIUM),
            words = Harness.mediumWords,
            randomDouble = { 0.999 },
        )
        h.injectReady()
        assertEquals(QuestionKind.FillLetterMedium, h.state.question.kind)
        val firstAnswer = h.state.question.letterAnswers[0]

        h.injectSubmit(firstAnswer)

        assertEquals(1, h.callbacks.answerOutcomes.size)
        assertTrue(h.callbacks.answerOutcomes[0].second.advancedStep)
    }

    // ── requestEscape (system back on CocosBattleActivity) ───────────────────

    @Test
    fun requestEscapeSettlesLostLikeSceneEscape() {
        val h = makeHarness(2, 5, 10)
        h.injectReady()
        h.transport.clear()

        h.bridge.requestEscape()

        // Same contract as battle/escape: no scene traffic, no delay,
        // immediate Lost settlement handed to the host.
        assertEquals(0, h.transport.sent.size)
        assertEquals(0, h.scheduler.calls.size)
        assertEquals(1, h.callbacks.finishResults.size)
        assertFalse(h.callbacks.finishResults[0].won)
        assertEquals(BattleStatus.Lost, h.state.status)

        // A second back press cannot finish twice.
        h.bridge.requestEscape()
        assertEquals(1, h.callbacks.finishResults.size)
    }

    @Test
    fun requestEscapeAfterDisposeIsIgnored() {
        val h = makeHarness(2, 5, 10)
        h.injectReady()
        h.bridge.dispose()

        h.bridge.requestEscape()

        assertEquals(0, h.callbacks.finishResults.size)
    }

    @Test
    fun battleSpeakTextReturnsFullSentenceForCloze() {
        val q = Question(
            prompt = "p", correctAnswer = "cat", options = listOf("cat", "dog", "sun"),
            kind = QuestionKind.SentenceCloze, sentenceTemplate = "The ____ sat on the mat", sentenceZh = "z",
        )
        assertEquals("The cat sat on the mat", q.battleSpeakText)
    }
    @Test
    fun battleSpeakTextReturnsWordForChoice() {
        val q = Question(prompt = "p", correctAnswer = "cat", options = listOf("cat", "dog", "sun"))
        assertEquals("cat", q.battleSpeakText)
    }

    @Test
    fun cocosImageKeyMapsCatalogKeysToCharacterArtNames() {
        assertEquals("CharacterSlime", cocosImageKeyForCatalogIndex(1))
        assertEquals("CharacterPumpkinKing", cocosImageKeyForCatalogIndex(4))
        assertEquals("CharacterSnowQueen", cocosImageKeyForCatalogIndex(8))
        // Wrap-around mirrors the BattleUi monster lookup; out-of-range → first.
        val rosterSize = MonsterCatalog.default().entries.size
        assertEquals("CharacterSlime", cocosImageKeyForCatalogIndex(rosterSize + 1))
        assertEquals("CharacterSlime", cocosImageKeyForCatalogIndex(0))
        assertNotEquals("CharacterSlime", cocosImageKeyForCatalogIndex(2))
    }
}
