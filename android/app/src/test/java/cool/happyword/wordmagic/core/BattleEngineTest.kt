package cool.happyword.wordmagic.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class BattleEngineTest {
    private val words = listOf(
        WordEntry("apple", "apple", "苹果"),
        WordEntry("banana", "banana", "香蕉"),
        WordEntry("cat", "cat", "猫"),
        WordEntry("dog", "dog", "狗"),
    )
    private val choiceOnlyTypes = listOf(BattleQuestionTypePolicy.CHOICE)

    @Test
    fun correctAnswerDamagesMonster() {
        val engine = BattleEngine(
            config = GameConfig(monsterHp = 3, monsterCount = 1, enabledQuestionTypes = choiceOnlyTypes),
            words = words,
        )

        val initial = engine.initialState()
        val state = engine.submitAnswer(initial, initial.question.correctAnswer)

        assertEquals(2, state.monsterHp)
        assertEquals(1, state.combo)
        assertEquals(1, state.correctCount)
        assertEquals(BattleStatus.Playing, state.status)
    }

    @Test
    fun wrongAnswerDamagesPlayerAndKeepsMonsterHp() {
        val engine = BattleEngine(
            config = GameConfig(playerHp = 5, monsterHp = 3, monsterCount = 1, enabledQuestionTypes = choiceOnlyTypes),
            words = words,
        )

        val initial = engine.initialState()
        val wrongAnswer = initial.question.options.first { it != initial.question.correctAnswer }
        val state = engine.submitAnswer(initial, wrongAnswer)

        assertEquals(4, state.playerHp)
        assertEquals(3, state.monsterHp)
        assertEquals(0, state.combo)
        assertEquals(1, state.wrongCount)
    }

    @Test
    fun thirdConsecutiveCorrectAnswerDoesDoubleDamageAndResetsCombo() {
        val engine = BattleEngine(
            config = GameConfig(monsterHp = 5, monsterCount = 1, enabledQuestionTypes = choiceOnlyTypes),
            words = words,
        )

        val initial = engine.initialState()
        val first = engine.submitAnswer(initial, initial.question.correctAnswer)
        val second = engine.submitAnswer(first, first.question.correctAnswer)
        val third = engine.submitAnswer(second, second.question.correctAnswer)

        assertEquals(1, third.monsterHp)
        assertEquals(0, third.combo)
    }

    @Test
    fun defeatingAllMonstersProducesWonResultWithCoinsEqualToStars() {
        val engine = BattleEngine(
            config = GameConfig(monsterHp = 1, monsterCount = 1, enabledQuestionTypes = choiceOnlyTypes),
            words = words,
            randomDouble = { 0.99 },
        )

        val initial = engine.initialState()
        val won = engine.submitAnswer(initial, initial.question.correctAnswer)
        val result = engine.resultFor(won)

        assertEquals(BattleStatus.Won, won.status)
        assertTrue(result.won)
        assertEquals(3, result.stars)
        assertEquals(3, result.coinDelta)
        assertEquals(1, result.defeatedMonsters)
    }

    @Test
    fun advancedAndSuperMonstersCanDealHeavyAttackDamage() {
        val engine = BattleEngine(
            config = GameConfig(playerHp = 5, monsterHp = 1, monsterCount = 10, enabledQuestionTypes = listOf(BattleQuestionTypePolicy.CHOICE)),
            words = words,
            randomDouble = { 0.25 },
        )

        var state = engine.initialState()
        repeat(7) {
            state = engine.submitAnswer(state, state.question.correctAnswer)
        }
        val wrongAnswer = state.question.options.first { it != state.question.correctAnswer }
        val outcome = engine.submitAnswerWithOutcome(state, wrongAnswer)

        assertEquals(false, outcome.correct)
        assertEquals(2, outcome.damage)
        assertEquals(3, outcome.nextState.playerHp)
    }

    @Test
    fun bonusMonsterKillsIncreaseWonCoinRewardByThirtyPercent() {
        val engine = BattleEngine(
            config = GameConfig(monsterHp = 1, monsterCount = 8, enabledQuestionTypes = listOf(BattleQuestionTypePolicy.CHOICE)),
            words = words,
            randomDouble = { 0.10 },
        )

        var won = engine.initialState()
        while (won.status == BattleStatus.Playing) {
            won = engine.submitAnswer(won, won.question.correctAnswer)
        }
        val result = engine.resultFor(won)

        assertTrue(result.won)
        assertEquals(3, result.stars)
        assertEquals(1, result.bonusKillCount)
        assertEquals(4, result.coinDelta)
    }

    @Test
    fun losingAfterDefeatingOneMonsterStillAwardsOneStar() {
        val engine = BattleEngine(
            config = GameConfig(playerHp = 1, monsterHp = 1, monsterCount = 2, enabledQuestionTypes = choiceOnlyTypes),
            words = words,
        )

        val initial = engine.initialState()
        val defeatedOne = engine.submitAnswer(initial, initial.question.correctAnswer)
        val wrongAnswer = defeatedOne.question.options.first { it != defeatedOne.question.correctAnswer }
        val lost = engine.submitAnswer(defeatedOne, wrongAnswer)
        val result = engine.resultFor(lost)

        assertEquals(BattleStatus.Lost, lost.status)
        assertEquals(1, lost.defeatedMonsters)
        assertEquals(1, result.stars)
        assertEquals(1, result.coinDelta)
    }

    @Test
    fun answerOutcomeReportsNormalCorrectHit() {
        val engine = BattleEngine(
            config = GameConfig(monsterHp = 3, monsterCount = 1, enabledQuestionTypes = choiceOnlyTypes),
            words = words,
        )

        val initial = engine.initialState()
        val outcome = engine.submitAnswerWithOutcome(initial, initial.question.correctAnswer)

        assertEquals(true, outcome.correct)
        assertEquals(initial.question.correctAnswer, outcome.correctAnswer)
        assertEquals(initial.question.correctAnswer, outcome.selectedAnswer)
        assertEquals(1, outcome.damage)
        assertEquals(false, outcome.comboTriggered)
        assertEquals(false, outcome.playerDamaged)
        assertEquals(false, outcome.monsterDefeated)
    }

    @Test
    fun answerOutcomeReportsWrongHitAgainstPlayer() {
        val engine = BattleEngine(
            config = GameConfig(playerHp = 5, monsterHp = 3, monsterCount = 1, enabledQuestionTypes = choiceOnlyTypes),
            words = words,
        )

        val initial = engine.initialState()
        val wrongAnswer = initial.question.options.first { it != initial.question.correctAnswer }
        val outcome = engine.submitAnswerWithOutcome(initial, wrongAnswer)

        assertEquals(false, outcome.correct)
        assertEquals(initial.question.correctAnswer, outcome.correctAnswer)
        assertEquals(wrongAnswer, outcome.selectedAnswer)
        assertEquals(1, outcome.damage)
        assertEquals(false, outcome.comboTriggered)
        assertEquals(true, outcome.playerDamaged)
        assertEquals(false, outcome.monsterDefeated)
    }

    @Test
    fun answerOutcomeReportsComboBurst() {
        val engine = BattleEngine(
            config = GameConfig(monsterHp = 5, monsterCount = 1, enabledQuestionTypes = choiceOnlyTypes),
            words = words,
        )

        val initial = engine.initialState()
        val first = engine.submitAnswerWithOutcome(initial, initial.question.correctAnswer).nextState
        val second = engine.submitAnswerWithOutcome(first, first.question.correctAnswer).nextState
        val outcome = engine.submitAnswerWithOutcome(second, second.question.correctAnswer)

        assertEquals(true, outcome.correct)
        assertEquals(2, outcome.damage)
        assertEquals(true, outcome.comboTriggered)
        assertEquals(false, outcome.monsterDefeated)
    }

    @Test
    fun questionOptionsUseShuffledOrderInsteadOfAlwaysPuttingCorrectAnswerFirst() {
        val engine = BattleEngine(
            config = GameConfig(enabledQuestionTypes = choiceOnlyTypes),
            words = words,
            shuffleOptions = { options -> options.reversed() },
        )

        val state = engine.initialState()
        val expectedOptions = (listOf(state.question.correctAnswer) + words.map { it.word }.filter { it != state.question.correctAnswer })
            .distinct()
            .take(3)
            .reversed()

        assertEquals(expectedOptions, state.question.options)
    }

    @Test
    fun targetWordIdsFocusQuestionsWhileUsingFullWordPoolForOptions() {
        val engine = BattleEngine(
            config = GameConfig(enabledQuestionTypes = choiceOnlyTypes),
            words = words,
            targetWordIds = listOf("cat"),
        )

        val state = engine.initialState()

        assertEquals("cat", state.question.wordId)
        assertEquals(3, state.question.options.size)
        assertTrue(state.question.options.contains("cat"))
    }
}
