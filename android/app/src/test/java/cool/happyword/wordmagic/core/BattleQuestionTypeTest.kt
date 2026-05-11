package cool.happyword.wordmagic.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class BattleQuestionTypeTest {
    private val words = listOf(
        WordEntry("fruit-apple", "apple", "苹果"),
        WordEntry("fruit-banana", "banana", "香蕉"),
        WordEntry("fruit-orange", "orange", "橙子"),
        WordEntry("animal-monkey", "monkey", "猴子"),
        WordEntry("place-garden", "garden", "花园"),
    )

    @Test
    fun monsterPlanUsesHarmonyQuestionKindFallbackChain() {
        val engine = BattleEngine(
            config = GameConfig(monsterHp = 1, monsterCount = 5),
            words = words,
            shuffleOptions = { it },
            randomDouble = { 0.999 },
        )

        val normal = engine.initialState()
        assertEquals(QuestionKind.Choice, normal.question.kind)
        assertEquals(listOf("apple", "banana", "orange"), normal.question.options)

        val spelling = engine.submitAnswer(normal, answerFor(normal.question))
        assertEquals(QuestionKind.FillLetter, spelling.question.kind)
        assertTrue(spelling.question.letterTemplate.contains("_"))
        assertTrue(spelling.question.letterOptions.contains(spelling.question.letterAnswer))
        assertEquals("banana", spelling.question.correctAnswer)

        val elite = engine.submitAnswer(spelling, answerFor(spelling.question))
        assertEquals(QuestionKind.FillLetterMedium, elite.question.kind)
        assertEquals(2, elite.question.missingIndices.size)
        assertEquals(2, elite.question.letterOptionsSteps.size)
        assertEquals(2, elite.question.letterAnswers.size)

        val eliteStep = engine.submitAnswer(elite, answerFor(elite.question))
        val review = engine.submitAnswer(eliteStep, answerFor(eliteStep.question))
        assertEquals(QuestionKind.Choice, review.question.kind)

        val boss = engine.submitAnswer(review, answerFor(review.question))
        assertEquals(QuestionKind.Spell, boss.question.kind)
        assertEquals("garden", boss.question.correctAnswer)
        assertEquals(listOf(true, false, false, false, false, false), boss.question.spellRevealedMask)
        assertEquals(listOf("g", "a", "r", "d", "e", "n"), boss.question.spellLetters)
        assertEquals(listOf("a", "r", "d", "e", "n"), boss.question.spellPool)
    }

    @Test
    fun mediumFillLetterFirstCorrectStepAdvancesWithoutDamageOrQuestionRotation() {
        val engine = BattleEngine(
            config = GameConfig(monsterHp = 1, monsterCount = 5),
            words = words,
            shuffleOptions = { it },
            randomDouble = { 0.999 },
        )
        val normal = engine.initialState()
        val spelling = engine.submitAnswer(normal, answerFor(normal.question))
        val elite = engine.submitAnswer(spelling, answerFor(spelling.question))

        val outcome = engine.submitAnswerWithOutcome(elite, answerFor(elite.question))

        assertTrue(outcome.correct)
        assertTrue(outcome.advancedStep)
        assertEquals(0, outcome.damage)
        assertFalse(outcome.monsterDefeated)
        assertEquals(elite.monsterHp, outcome.nextState.monsterHp)
        assertEquals(QuestionKind.FillLetterMedium, outcome.nextState.question.kind)
        assertEquals(1, outcome.nextState.question.currentStep)
        assertTrue(outcome.nextState.question.letterTemplateBase.contains(outcome.question.letterAnswers[0]))
    }

    @Test
    fun shortBossWordFallsBackFromSpellToMediumFillLetter() {
        val shortWords = listOf(
            WordEntry("w-ox", "ox", "牛"),
            WordEntry("w-cat", "cat", "猫"),
            WordEntry("w-dog", "dog", "狗"),
            WordEntry("w-sun", "sun", "太阳"),
            WordEntry("w-strawberry", "strawberry", "草莓"),
        )
        val engine = BattleEngine(
            config = GameConfig(monsterHp = 1, monsterCount = 5),
            words = shortWords,
            shuffleOptions = { it },
            randomDouble = { 0.999 },
        )

        val normal = engine.initialState()
        val spelling = engine.submitAnswer(normal, answerFor(normal.question))
        val elite = engine.submitAnswer(spelling, answerFor(spelling.question))
        val eliteStep = engine.submitAnswer(elite, answerFor(elite.question))
        val review = engine.submitAnswer(eliteStep, answerFor(eliteStep.question))
        val boss = engine.submitAnswer(review, answerFor(review.question))

        assertEquals(QuestionKind.FillLetterMedium, boss.question.kind)
        assertEquals("strawberry", boss.question.correctAnswer)
    }

    private fun answerFor(question: Question): String {
        return when (question.kind) {
            QuestionKind.Choice -> question.correctAnswer
            QuestionKind.FillLetter -> question.letterAnswer
            QuestionKind.FillLetterMedium -> question.letterAnswers[question.currentStep]
            QuestionKind.Spell -> question.correctAnswer
        }
    }
}
