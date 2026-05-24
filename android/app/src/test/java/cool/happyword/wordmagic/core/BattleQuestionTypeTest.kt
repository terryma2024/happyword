package cool.happyword.wordmagic.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
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
    fun sentenceClozeQuestionMatchesHarmonyRules() {
        val apple = WordEntry(
            "fruit-apple",
            "apple",
            "苹果",
            example = ExampleSentence(en = "I eat an apple.", zh = "我吃一个苹果。"),
        )
        val engine = BattleEngine(
            config = GameConfig(
                monsterHp = 99,
                monsterCount = 1,
                enabledQuestionTypes = listOf(BattleQuestionTypePolicy.SENTENCE_CLOZE),
            ),
            words = listOf(
                apple,
                WordEntry("fruit-banana", "banana", "香蕉"),
                WordEntry("fruit-orange", "orange", "橙子"),
            ),
            targetWordIds = listOf("fruit-apple"),
            shuffleOptions = { it },
            randomDouble = { 0.0 },
        )

        val question = engine.initialState().question

        assertEquals(QuestionKind.SentenceCloze, question.kind)
        assertEquals("I eat an ____.", question.sentenceTemplate)
        assertEquals("我吃一个苹果。", question.sentenceZh)
        assertEquals(3, question.options.size)
        assertTrue(question.options.contains("apple"))
        assertFalse(BattleQuestionTypePolicy.wordSupportsQuestionType(
            WordEntry("animal-cat", "cat", "猫", example = ExampleSentence(en = "A caterpillar is small.", zh = "毛毛虫很小。")),
            BattleQuestionTypePolicy.SENTENCE_CLOZE,
        ))
    }

    @Test
    fun sentenceClozeOnlyRotatesAcrossTargetPackWords() {
        val pack = BuiltinPacks.all.first { it.id == "fruit-forest" }
        val engine = BattleEngine(
            config = GameConfig(
                monsterHp = 99,
                monsterCount = 1,
                enabledQuestionTypes = listOf(BattleQuestionTypePolicy.SENTENCE_CLOZE),
            ),
            words = pack.words,
            targetWordIds = pack.words.map { it.id },
            shuffleOptions = { it },
            randomDouble = { 0.0 },
        )
        val expectedIds = pack.words.take(5).map { it.id }
        val actualIds = mutableListOf<String>()
        var state = engine.initialState()

        repeat(expectedIds.size) {
            assertEquals(QuestionKind.SentenceCloze, state.question.kind)
            actualIds.add(state.question.wordId)
            state = engine.submitAnswer(state, state.question.correctAnswer)
        }

        assertEquals(expectedIds, actualIds)
    }

    @Test
    fun sentenceClozeSupportsPhrasesFirstMatchAndUniqueDistractors() {
        val wand = WordEntry(
            "magic-wand",
            "magic wand",
            "魔法棒",
            example = ExampleSentence(en = "I hold a magic wand.", zh = "我拿着一根魔法棒。"),
        )
        val phraseEngine = BattleEngine(
            config = GameConfig(monsterHp = 99, monsterCount = 1, enabledQuestionTypes = listOf(BattleQuestionTypePolicy.SENTENCE_CLOZE)),
            words = listOf(wand, WordEntry("fruit-apple", "apple", "苹果"), WordEntry("fruit-banana", "banana", "香蕉")),
            targetWordIds = listOf("magic-wand"),
            shuffleOptions = { it },
            randomDouble = { 0.0 },
        )
        assertEquals("I hold a ____.", phraseEngine.initialState().question.sentenceTemplate)

        val apple = WordEntry(
            "fruit-apple",
            "apple",
            "苹果",
            distractors = listOf("Apple", "banana"),
            example = ExampleSentence(en = "Apple pie has apple slices.", zh = "苹果派里有苹果片。"),
        )
        val appleEngine = BattleEngine(
            config = GameConfig(monsterHp = 99, monsterCount = 1, enabledQuestionTypes = listOf(BattleQuestionTypePolicy.SENTENCE_CLOZE)),
            words = listOf(apple, WordEntry("fruit-orange", "orange", "橙子"), WordEntry("fruit-grape", "grape", "葡萄")),
            targetWordIds = listOf("fruit-apple"),
            shuffleOptions = { it },
            randomDouble = { 0.0 },
        )
        val question = appleEngine.initialState().question
        assertEquals("____ pie has apple slices.", question.sentenceTemplate)
        assertEquals(3, question.options.size)
        assertTrue(question.options.contains("apple"))
        assertTrue(question.options.contains("banana"))
        assertFalse(question.options.contains("Apple"))
    }

    @Test
    fun sentenceClozeOnlyFallsBackToChoiceWithoutExample() {
        val engine = BattleEngine(
            config = GameConfig(monsterHp = 99, monsterCount = 1, enabledQuestionTypes = listOf(BattleQuestionTypePolicy.SENTENCE_CLOZE)),
            words = listOf(
                WordEntry("fruit-orange", "orange", "橙子"),
                WordEntry("fruit-banana", "banana", "香蕉"),
                WordEntry("fruit-grape", "grape", "葡萄"),
            ),
            targetWordIds = listOf("fruit-orange"),
            shuffleOptions = { it },
            randomDouble = { 0.0 },
        )

        assertEquals(QuestionKind.Choice, engine.initialState().question.kind)
    }

    @Test
    fun monsterPlanUsesHarmonyQuestionKindFallbackChain() {
        val engine = BattleEngine(
            config = GameConfig(monsterHp = 99, monsterCount = 5),
            words = words,
            shuffleOptions = { it },
            randomDouble = { 0.5 },
        )

        val normal = engine.initialState()
        assertEquals(QuestionKind.Choice, normal.question.kind)
        assertEquals(3, normal.question.options.size)
        assertTrue(normal.question.options.contains(normal.question.correctAnswer))

        val spelling = advanceUntilKind(engine, normal, QuestionKind.FillLetter)
        assertNotNull(spelling)
        val spellingState = spelling!!
        assertEquals(QuestionKind.FillLetter, spellingState.question.kind)
        assertTrue(spellingState.question.letterTemplate.contains("_"))
        assertTrue(spellingState.question.letterOptions.contains(spellingState.question.letterAnswer))

        val boss = advanceUntilKind(engine, spellingState, QuestionKind.Spell)
        assertNotNull(boss)
        val bossState = boss!!
        assertEquals(QuestionKind.Spell, bossState.question.kind)
        assertTrue(bossState.question.spellRevealedMask.first())
        assertEquals(bossState.question.spellLetters.size - 1, bossState.question.spellPool.size)
    }

    @Test
    fun mediumFillLetterFirstCorrectStepAdvancesWithoutDamageOrQuestionRotation() {
        val engine = BattleEngine(
            config = GameConfig(
                monsterHp = 99,
                monsterCount = 5,
                enabledQuestionTypes = listOf(BattleQuestionTypePolicy.FILL_LETTER_MEDIUM),
            ),
            words = words,
            shuffleOptions = { it },
            randomDouble = { 0.999 },
        )
        val normal = engine.initialState()
        val elite = normal
        assertEquals(QuestionKind.FillLetterMedium, elite.question.kind)

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
    fun fillLetterDistractorsComeFromShuffledCandidatePool() {
        val lowRandom = engineWithRandomSequence(0.0, 0.0, 0.0, 0.0)
        val highRandom = engineWithRandomSequence(0.0, 0.5, 0.5, 0.5)

        val lowQuestion = lowRandom.submitAnswer(lowRandom.initialState(), "apple").question
        val highQuestion = highRandom.submitAnswer(highRandom.initialState(), "apple").question

        assertEquals(QuestionKind.FillLetter, lowQuestion.kind)
        assertEquals(QuestionKind.FillLetter, highQuestion.kind)
        assertFillLetterDistractorsExcludeWordLetters(lowQuestion)
        assertFillLetterDistractorsExcludeWordLetters(highQuestion)
    }

    @Test
    fun shortBossWordFallsBackFromSpellToMediumFillLetter() {
        val shortWords = listOf(
            WordEntry("w-ox", "ox", "牛"),
            WordEntry("w-strawberry", "strawberry", "草莓"),
            WordEntry("w-cat", "cat", "猫"),
            WordEntry("w-dog", "dog", "狗"),
            WordEntry("w-sun", "sun", "太阳"),
        )
        val engine = BattleEngine(
            config = GameConfig(
                monsterHp = 99,
                monsterCount = 5,
                enabledQuestionTypes = listOf(BattleQuestionTypePolicy.FILL_LETTER_MEDIUM),
            ),
            words = shortWords,
            shuffleOptions = { it },
            randomDouble = { 0.999 },
        )

        val boss = engine.initialState()

        assertEquals(QuestionKind.FillLetterMedium, boss.question.kind)
        assertEquals("strawberry", boss.question.correctAnswer)
    }

    @Test
    fun phraseFillLetterShowsSpacesAndDoesNotHideArticles() {
        val phraseWords = listOf(
            WordEntry("fruit-apple", "apple", "苹果"),
            WordEntry("phrase-a-puppy", "an puppy", "一只小狗"),
            WordEntry("phrase-magic-wand", "magic wand", "魔法棒"),
            WordEntry("fruit-banana", "banana", "香蕉"),
            WordEntry("fruit-orange", "orange", "橙子"),
        )
        val engine = BattleEngine(
            config = GameConfig(
                monsterHp = 99,
                monsterCount = 5,
                enabledQuestionTypes = listOf(BattleQuestionTypePolicy.FILL_LETTER),
            ),
            words = phraseWords,
            targetWordIds = listOf("phrase-a-puppy"),
            shuffleOptions = { it },
            randomDouble = { 0.0 },
        )

        val phraseState = engine.initialState()

        val phrase = phraseState.question
        assertEquals(QuestionKind.FillLetter, phrase.kind)
        assertEquals("an puppy", phrase.correctAnswer)
        assertTrue(phrase.letterTemplate.contains("   "))
        assertFalse(phrase.letterAnswer == "a" || phrase.letterAnswer == "n")
    }

    @Test
    fun phraseSpellShowsSpacesAndPrefillsArticles() {
        val phraseWords = listOf(
            WordEntry("fruit-apple", "apple", "苹果"),
            WordEntry("phrase-the-apple", "the apple", "这个苹果"),
            WordEntry("fruit-orange", "orange", "橙子"),
            WordEntry("animal-monkey", "monkey", "猴子"),
            WordEntry("fruit-banana", "banana", "香蕉"),
        )
        val engine = BattleEngine(
            config = GameConfig(
                monsterHp = 99,
                monsterCount = 5,
                enabledQuestionTypes = listOf(BattleQuestionTypePolicy.SPELL),
            ),
            words = phraseWords,
            targetWordIds = listOf("phrase-the-apple"),
            shuffleOptions = { it },
            randomDouble = { 0.0 },
        )

        val bossState = engine.initialState()

        val boss = bossState.question
        assertEquals(QuestionKind.Spell, boss.kind)
        assertEquals("the apple", boss.spellLetters.joinToString(""))
        assertEquals(listOf(true, true, true, true, true), boss.spellRevealedMask.take(5))
        assertEquals(listOf("e", "l", "p", "p"), boss.spellPool.sorted())
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

    private fun advanceUntilKind(engine: BattleEngine, start: BattleState, kind: QuestionKind): BattleState? {
        var state = start
        repeat(20) {
            if (state.question.kind == kind) return state
            if (state.status != BattleStatus.Playing) return null
            state = engine.submitAnswer(state, answerFor(state.question))
        }
        return null
    }

    private fun advanceUntilAnswerKind(
        engine: BattleEngine,
        start: BattleState,
        answer: String,
        kind: QuestionKind,
    ): BattleState? {
        var state = start
        repeat(30) {
            if (state.question.correctAnswer == answer && state.question.kind == kind) return state
            if (state.status != BattleStatus.Playing) return null
            state = engine.submitAnswer(state, answerFor(state.question))
        }
        return null
    }

    private fun assertFillLetterDistractorsExcludeWordLetters(question: Question) {
        assertEquals(3, question.letterOptions.size)
        assertTrue(question.letterOptions.contains(question.letterAnswer))
        val wordLetters = question.correctAnswer.lowercase().filter { it in 'a'..'z' }.map { it.toString() }.toSet()
        question.letterOptions.filter { it != question.letterAnswer }.forEach { distractor ->
            assertFalse(wordLetters.contains(distractor))
        }
    }

    private fun engineWithRandomSequence(vararg values: Double): BattleEngine {
        var index = 0
        return BattleEngine(
            config = GameConfig(monsterHp = 1, monsterCount = 5),
            words = words,
            shuffleOptions = { it },
            randomDouble = {
                val value = values.getOrElse(index) { values.last() }
                index += 1
                value
            },
        )
    }
}
