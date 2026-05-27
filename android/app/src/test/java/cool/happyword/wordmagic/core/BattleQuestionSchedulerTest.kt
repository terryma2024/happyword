package cool.happyword.wordmagic.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class BattleQuestionSchedulerTest {
    @Test
    fun singleTypeAlwaysReturnsThatKind() {
        val scheduler = BattleQuestionScheduler(
            rawPlanWordIds = listOf("w-a", "w-b"),
            enabledTypes = listOf(BattleQuestionTypePolicy.SPELL),
            rng = { 0.0 },
        )
        assertEquals(BattleScheduleMode.SingleType, scheduler.scheduleMode())
        repeat(6) {
            assertEquals(BattleQuestionTypePolicy.SPELL, scheduler.pickNext(null) { _, _ -> true }.kind)
        }
    }

    @Test
    fun introOnlyNeverReturnsChallengeKind() {
        val scheduler = BattleQuestionScheduler(
            rawPlanWordIds = listOf("w-a", "w-b", "w-c"),
            enabledTypes = listOf(BattleQuestionTypePolicy.CHOICE, BattleQuestionTypePolicy.FILL_LETTER),
            rng = { 0.25 },
        )
        assertEquals(BattleScheduleMode.IntroOnly, scheduler.scheduleMode())
        val canServe: WordKindSupportFn = { _, _ -> true }
        repeat(12) { index ->
            val kind = scheduler.pickNext(null, canServe).kind
            assertFalse(
                kind == BattleQuestionTypePolicy.FILL_LETTER_MEDIUM ||
                    kind == BattleQuestionTypePolicy.SPELL ||
                    kind == BattleQuestionTypePolicy.SENTENCE_CLOZE,
            )
            scheduler.markServed("w-${index % 3}", kind, canServe)
        }
    }

    @Test
    fun challengeStagesAdvanceInConfiguredDifficultyOrder() {
        val scheduler = BattleQuestionScheduler(
            rawPlanWordIds = listOf("w-a"),
            enabledTypes = listOf(
                BattleQuestionTypePolicy.FILL_LETTER_MEDIUM,
                BattleQuestionTypePolicy.SPELL,
                BattleQuestionTypePolicy.SENTENCE_CLOZE,
            ),
            rng = { 0.99 },
        )
        val canServe: WordKindSupportFn = { _, _ -> true }

        assertEquals(BattleQuestionTypePolicy.FILL_LETTER_MEDIUM, scheduler.pickNext(null, canServe).kind)
        scheduler.markServed("w-a", BattleQuestionTypePolicy.FILL_LETTER_MEDIUM, canServe)
        assertEquals(BattleQuestionTypePolicy.SPELL, scheduler.pickNext("w-a", canServe).kind)
        scheduler.markServed("w-a", BattleQuestionTypePolicy.SPELL, canServe)
        assertEquals(BattleQuestionTypePolicy.SENTENCE_CLOZE, scheduler.pickNext("w-a", canServe).kind)
    }

    @Test
    fun challengeRollsNeverReturnSentenceClozeWhenDisabled() {
        val scheduler = BattleQuestionScheduler(
            rawPlanWordIds = listOf("w-a"),
            enabledTypes = listOf(BattleQuestionTypePolicy.FILL_LETTER_MEDIUM, BattleQuestionTypePolicy.SPELL),
            rng = { 0.99 },
        )

        repeat(10) {
            assertFalse(scheduler.pickNext(null) { _, _ -> true }.kind == BattleQuestionTypePolicy.SENTENCE_CLOZE)
        }
    }

    @Test
    fun stagesAdvanceStrictlyEasyToHardAfterAllSupportedWordsAreServed() {
        val scheduler = BattleQuestionScheduler(
            rawPlanWordIds = listOf("w-a", "w-b"),
            enabledTypes = BattleQuestionTypePolicy.defaultOrderedTypeIds,
            rng = { 0.0 },
        )
        val canServe: WordKindSupportFn = { wordId, kind ->
            when (kind) {
                BattleQuestionTypePolicy.CHOICE -> true
                BattleQuestionTypePolicy.FILL_LETTER -> wordId == "w-a"
                BattleQuestionTypePolicy.FILL_LETTER_MEDIUM -> wordId == "w-b"
                BattleQuestionTypePolicy.SPELL -> true
                BattleQuestionTypePolicy.SENTENCE_CLOZE -> wordId == "w-b"
                else -> false
            }
        }

        assertEquals(BattleQuestionTypePolicy.CHOICE, scheduler.pickNext(null, canServe).kind)
        scheduler.markServed("w-a", BattleQuestionTypePolicy.CHOICE, canServe)
        assertEquals(BattleQuestionTypePolicy.CHOICE, scheduler.pickNext("w-a", canServe).kind)
        scheduler.markServed("w-b", BattleQuestionTypePolicy.CHOICE, canServe)

        val fillPick = scheduler.pickNext("w-b", canServe)
        assertEquals(BattleQuestionTypePolicy.FILL_LETTER, fillPick.kind)
        assertEquals("w-a", fillPick.preferredWordId)
        scheduler.markServed("w-a", BattleQuestionTypePolicy.FILL_LETTER, canServe)

        val mediumPick = scheduler.pickNext("w-a", canServe)
        assertEquals(BattleQuestionTypePolicy.FILL_LETTER_MEDIUM, mediumPick.kind)
        assertEquals("w-b", mediumPick.preferredWordId)
        scheduler.markServed("w-b", BattleQuestionTypePolicy.FILL_LETTER_MEDIUM, canServe)

        assertEquals(BattleQuestionTypePolicy.SPELL, scheduler.pickNext("w-b", canServe).kind)
    }

    @Test
    fun battleKeepsLivingMonsterWhileQuestionStageAdvancesThenSpawnsByActiveStage() {
        val words = listOf(
            WordEntry("w-apple", "apple", "苹果", example = ExampleSentence("I eat an apple.", "我吃苹果。")),
            WordEntry("w-banana", "banana", "香蕉", example = ExampleSentence("The banana is yellow.", "香蕉是黄色的。")),
        )
        val engine = BattleEngine(
            config = GameConfig(monsterHp = 5, monsterCount = 2, enabledQuestionTypes = BattleQuestionTypePolicy.defaultOrderedTypeIds),
            words = words,
            targetWordIds = words.map { it.id },
            shuffleOptions = { it },
            randomDouble = { 0.0 },
        )

        var state = engine.initialState()
        assertEquals(1, state.monsterIndex)
        assertEquals(MonsterLevel.Beginner, MonsterLevel.forCatalogIndex(state.monsterCatalogIndex))

        repeat(2) {
            assertEquals(QuestionKind.Choice, state.question.kind)
            state = engine.submitAnswer(state, state.question.correctAnswer)
        }

        assertEquals("same monster survives the stage advance", 1, state.monsterIndex)
        assertEquals(QuestionKind.FillLetter, state.question.kind)
        assertEquals(MonsterLevel.Beginner, MonsterLevel.forCatalogIndex(state.monsterCatalogIndex))

        while (state.status == BattleStatus.Playing && state.monsterIndex == 1) {
            state = engine.submitAnswer(state, answerFor(state.question))
        }

        assertEquals(2, state.monsterIndex)
        assertEquals(QuestionKind.FillLetterMedium, state.question.kind)
        assertEquals(MonsterLevel.Advanced, MonsterLevel.forCatalogIndex(state.monsterCatalogIndex))
    }

    @Test
    fun restoredBattleContinuesQuestionOrderAfterCurrentQuestion() {
        val words = BuiltinPacks.all.first { it.id == "fruit-forest" }.words.take(5)
        val config = GameConfig(
            monsterHp = 99,
            monsterCount = 1,
            enabledQuestionTypes = listOf(BattleQuestionTypePolicy.CHOICE),
        )
        val targetIds = words.map { it.id }
        val originalEngine = BattleEngine(
            config = config,
            words = words,
            targetWordIds = targetIds,
            shuffleOptions = { it },
            randomDouble = { 0.0 },
        )
        val first = originalEngine.initialState()
        val second = originalEngine.submitAnswer(first, first.question.correctAnswer)
        assertEquals(words[0].id, first.question.wordId)
        assertEquals(words[1].id, second.question.wordId)

        val restoredEngine = BattleEngine(
            config = config,
            words = words,
            targetWordIds = targetIds,
            shuffleOptions = { it },
            randomDouble = { 0.0 },
            servedQuestions = listOf(
                BattleServedQuestion(first.question.wordId, BattleQuestionTypePolicy.kindToTypeId(first.question.kind)),
                BattleServedQuestion(second.question.wordId, BattleQuestionTypePolicy.kindToTypeId(second.question.kind)),
            ),
        )
        val afterRestoredAnswer = restoredEngine.submitAnswer(second, second.question.correctAnswer)

        assertEquals(words[2].id, afterRestoredAnswer.question.wordId)
    }

    @Test
    fun spellWrongTapPenaltyAtOneHpEndsBattle() {
        val engine = BattleEngine(config = GameConfig(playerHp = 1))
        val initial = engine.initialState()
        val (_, next) = engine.applySpellLetterPenalty(initial)
        assertEquals(0, next.playerHp)
        assertEquals(BattleStatus.Lost, next.status)
    }

    private fun answerFor(question: Question): String {
        return when (question.kind) {
            QuestionKind.Choice -> question.correctAnswer
            QuestionKind.SentenceCloze -> question.correctAnswer
            QuestionKind.FillLetter -> question.letterAnswer
            QuestionKind.FillLetterMedium -> question.letterAnswers[question.currentStep]
            QuestionKind.Spell -> question.correctAnswer
        }
    }
}
