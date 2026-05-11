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

    @Test
    fun correctAnswerDamagesMonster() {
        val engine = BattleEngine(
            config = GameConfig(monsterHp = 3, monsterCount = 1),
            words = words,
        )

        val state = engine.submitAnswer(engine.initialState(), "apple")

        assertEquals(2, state.monsterHp)
        assertEquals(1, state.combo)
        assertEquals("banana", state.question.correctAnswer)
        assertEquals(BattleStatus.Playing, state.status)
    }

    @Test
    fun wrongAnswerDamagesPlayerAndKeepsMonsterHp() {
        val engine = BattleEngine(
            config = GameConfig(playerHp = 5, monsterHp = 3, monsterCount = 1),
            words = words,
        )

        val state = engine.submitAnswer(engine.initialState(), "banana")

        assertEquals(4, state.playerHp)
        assertEquals(3, state.monsterHp)
        assertEquals(0, state.combo)
        assertEquals("banana", state.question.correctAnswer)
    }

    @Test
    fun thirdConsecutiveCorrectAnswerDoesDoubleDamageAndResetsCombo() {
        val engine = BattleEngine(
            config = GameConfig(monsterHp = 5, monsterCount = 1),
            words = words,
        )

        val first = engine.submitAnswer(engine.initialState(), "apple")
        val second = engine.submitAnswer(first, "banana")
        val third = engine.submitAnswer(second, "cat")

        assertEquals(1, third.monsterHp)
        assertEquals(0, third.combo)
    }

    @Test
    fun defeatingAllMonstersProducesWonResultWithCoinsEqualToStars() {
        val engine = BattleEngine(
            config = GameConfig(monsterHp = 1, monsterCount = 1),
            words = words,
        )

        val won = engine.submitAnswer(engine.initialState(), "apple")
        val result = engine.resultFor(won)

        assertEquals(BattleStatus.Won, won.status)
        assertTrue(result.won)
        assertEquals(3, result.stars)
        assertEquals(3, result.coinDelta)
        assertEquals(1, result.defeatedMonsters)
    }

    @Test
    fun losingAfterDefeatingOneMonsterStillAwardsOneStar() {
        val engine = BattleEngine(
            config = GameConfig(playerHp = 1, monsterHp = 1, monsterCount = 2),
            words = words,
        )

        val defeatedOne = engine.submitAnswer(engine.initialState(), "apple")
        val lost = engine.submitAnswer(defeatedOne, "apple")
        val result = engine.resultFor(lost)

        assertEquals(BattleStatus.Lost, lost.status)
        assertEquals(1, lost.defeatedMonsters)
        assertEquals(1, result.stars)
        assertEquals(1, result.coinDelta)
    }

    @Test
    fun answerOutcomeReportsNormalCorrectHit() {
        val engine = BattleEngine(
            config = GameConfig(monsterHp = 3, monsterCount = 1),
            words = words,
        )

        val outcome = engine.submitAnswerWithOutcome(engine.initialState(), "apple")

        assertEquals(true, outcome.correct)
        assertEquals("apple", outcome.correctAnswer)
        assertEquals("apple", outcome.selectedAnswer)
        assertEquals(1, outcome.damage)
        assertEquals(false, outcome.comboTriggered)
        assertEquals(false, outcome.playerDamaged)
        assertEquals(false, outcome.monsterDefeated)
    }

    @Test
    fun answerOutcomeReportsWrongHitAgainstPlayer() {
        val engine = BattleEngine(
            config = GameConfig(playerHp = 5, monsterHp = 3, monsterCount = 1),
            words = words,
        )

        val outcome = engine.submitAnswerWithOutcome(engine.initialState(), "banana")

        assertEquals(false, outcome.correct)
        assertEquals("apple", outcome.correctAnswer)
        assertEquals("banana", outcome.selectedAnswer)
        assertEquals(1, outcome.damage)
        assertEquals(false, outcome.comboTriggered)
        assertEquals(true, outcome.playerDamaged)
        assertEquals(false, outcome.monsterDefeated)
    }

    @Test
    fun answerOutcomeReportsComboBurst() {
        val engine = BattleEngine(
            config = GameConfig(monsterHp = 5, monsterCount = 1),
            words = words,
        )

        val first = engine.submitAnswerWithOutcome(engine.initialState(), "apple").nextState
        val second = engine.submitAnswerWithOutcome(first, "banana").nextState
        val outcome = engine.submitAnswerWithOutcome(second, "cat")

        assertEquals(true, outcome.correct)
        assertEquals(2, outcome.damage)
        assertEquals(true, outcome.comboTriggered)
        assertEquals(false, outcome.monsterDefeated)
    }

    @Test
    fun questionOptionsUseShuffledOrderInsteadOfAlwaysPuttingCorrectAnswerFirst() {
        val engine = BattleEngine(
            config = GameConfig(),
            words = words,
            shuffleOptions = { options -> options.reversed() },
        )

        val state = engine.initialState()

        assertEquals(listOf("cat", "banana", "apple"), state.question.options)
        assertEquals("apple", state.question.correctAnswer)
    }
}
