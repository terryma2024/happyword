package cool.happyword.wordmagic.core

private enum class MonsterQuestionRole {
    Normal,
    Spelling,
    Elite,
    Boss,
}

class BattleEngine(
    private val config: GameConfig = GameConfig(),
    private val words: List<WordEntry> = demoWords,
    private val shuffleOptions: (List<String>) -> List<String> = { options -> options.shuffled() },
    private val randomDouble: () -> Double = { Math.random() },
) {
    fun initialState(): BattleState {
        val question = questionFor(words.first(), monsterIndex = 1)
        return BattleState(
            playerHp = config.playerHp,
            monsterHp = config.monsterHp,
            monsterIndex = 1,
            combo = 0,
            correctCount = 0,
            wrongCount = 0,
            defeatedMonsters = 0,
            question = question,
        )
    }

    fun submitAnswer(state: BattleState, answer: String): BattleState {
        return submitAnswerWithOutcome(state, answer).nextState
    }

    fun submitAnswerWithOutcome(state: BattleState, answer: String): BattleAnswerOutcome {
        if (state.status != BattleStatus.Playing) {
            return BattleAnswerOutcome(
                selectedAnswer = answer,
                correctAnswer = state.question.correctAnswer,
                question = state.question,
                correct = false,
                damage = 0,
                comboTriggered = false,
                monsterDefeated = false,
                playerDamaged = false,
                battleEnded = true,
                nextState = state,
            )
        }

        val correct = isCorrectAnswer(state.question, answer)
        if (state.question.kind == QuestionKind.FillLetterMedium && correct && state.question.currentStep == 0) {
            val advancedQuestion = advanceMediumQuestion(state.question, answer)
            return BattleAnswerOutcome(
                selectedAnswer = answer,
                correctAnswer = state.question.correctAnswer,
                question = state.question,
                correct = true,
                damage = 0,
                comboTriggered = false,
                monsterDefeated = false,
                playerDamaged = false,
                battleEnded = false,
                nextState = state.copy(question = advancedQuestion),
                advancedStep = true,
            )
        }

        if (!correct) {
            val nextPlayerHp = (state.playerHp - 1).coerceAtLeast(0)
            val nextState = state.copy(
                playerHp = nextPlayerHp,
                combo = 0,
                wrongCount = state.wrongCount + 1,
                question = if (nextPlayerHp <= 0) state.question else nextQuestionAfter(state.question.wordId, state.monsterIndex),
                status = if (nextPlayerHp <= 0) BattleStatus.Lost else BattleStatus.Playing,
            )
            return BattleAnswerOutcome(
                selectedAnswer = answer,
                correctAnswer = state.question.correctAnswer,
                question = state.question,
                correct = false,
                damage = 1,
                comboTriggered = false,
                monsterDefeated = false,
                playerDamaged = true,
                battleEnded = nextState.status != BattleStatus.Playing,
                nextState = nextState,
            )
        }

        val rawCombo = state.combo + 1
        val comboTriggered = rawCombo >= 3
        val damage = if (comboTriggered) 2 else 1
        val nextCombo = if (comboTriggered) 0 else rawCombo
        val nextMonsterHp = state.monsterHp - damage
        if (nextMonsterHp > 0) {
            val nextState = state.copy(
                monsterHp = nextMonsterHp,
                combo = nextCombo,
                correctCount = state.correctCount + 1,
                question = nextQuestionAfter(state.question.wordId, state.monsterIndex),
            )
            return correctOutcome(state, answer, damage, comboTriggered, monsterDefeated = false, nextState = nextState)
        }

        val defeated = state.defeatedMonsters + 1
        if (defeated >= config.monsterCount) {
            val nextState = state.copy(
                monsterHp = 0,
                combo = nextCombo,
                correctCount = state.correctCount + 1,
                defeatedMonsters = defeated,
                status = BattleStatus.Won,
            )
            return correctOutcome(state, answer, damage, comboTriggered, monsterDefeated = true, nextState = nextState)
        }

        val nextMonsterIndex = state.monsterIndex + 1
        val nextState = state.copy(
            monsterHp = config.monsterHp,
            monsterIndex = nextMonsterIndex,
            combo = nextCombo,
            correctCount = state.correctCount + 1,
            defeatedMonsters = defeated,
            question = nextQuestionAfter(state.question.wordId, nextMonsterIndex),
        )
        return correctOutcome(state, answer, damage, comboTriggered, monsterDefeated = true, nextState = nextState)
    }

    fun resultFor(state: BattleState): SessionResult {
        val total = state.correctCount + state.wrongCount
        val accuracy = if (total == 0) 0.0 else state.correctCount.toDouble() / total.toDouble()
        val stars = when {
            state.status == BattleStatus.Won && accuracy >= 0.8 -> 3
            state.status == BattleStatus.Won || state.defeatedMonsters >= 3 -> 2
            state.defeatedMonsters >= 1 -> 1
            else -> 0
        }
        return SessionResult(
            won = state.status == BattleStatus.Won,
            stars = stars,
            defeatedMonsters = state.defeatedMonsters,
            correctCount = state.correctCount,
            wrongCount = state.wrongCount,
            learnedWordCount = state.correctCount,
            coinDelta = stars,
        )
    }

    private fun isCorrectAnswer(question: Question, answer: String): Boolean {
        return when (question.kind) {
            QuestionKind.Choice -> answer == question.correctAnswer
            QuestionKind.FillLetter -> answer == question.letterAnswer
            QuestionKind.FillLetterMedium -> answer == question.letterAnswers.getOrNull(question.currentStep)
            QuestionKind.Spell -> answer == question.correctAnswer
        }
    }

    private fun questionFor(word: WordEntry, monsterIndex: Int): Question {
        return when (questionRoleFor(monsterIndex)) {
            MonsterQuestionRole.Boss -> spellQuestionFor(word)
                ?: mediumFillLetterQuestionFor(word)
                ?: fillLetterQuestionFor(word)
                ?: choiceQuestionFor(word)
            MonsterQuestionRole.Elite -> mediumFillLetterQuestionFor(word)
                ?: fillLetterQuestionFor(word)
                ?: choiceQuestionFor(word)
            MonsterQuestionRole.Spelling -> fillLetterQuestionFor(word) ?: choiceQuestionFor(word)
            MonsterQuestionRole.Normal -> choiceQuestionFor(word)
        }
    }

    private fun choiceQuestionFor(word: WordEntry): Question {
        val options = (listOf(word.word) + words.map { it.word }.filter { it != word.word })
            .distinct()
            .take(3)
        return Question(
            prompt = word.meaning,
            correctAnswer = word.word,
            options = shuffleOptions(options),
            wordId = word.id,
            kind = QuestionKind.Choice,
        )
    }

    private fun fillLetterQuestionFor(word: WordEntry): Question? {
        val letters = alphabeticLetters(word.word)
        if (letters.size < 3) return null
        val missingIndex = randomInt(1, letters.lastIndex)
        val letterAnswer = letters[missingIndex]
        val template = letters.mapIndexed { index, letter -> if (index == missingIndex) "_" else letter }.joinToString(" ")
        val options = letterOptionsFor(letters, letterAnswer)
        return Question(
            prompt = word.meaning,
            correctAnswer = word.word,
            options = options,
            wordId = word.id,
            kind = QuestionKind.FillLetter,
            letterTemplate = template,
            missingIndex = missingIndex,
            letterOptions = options,
            letterAnswer = letterAnswer,
        )
    }

    private fun mediumFillLetterQuestionFor(word: WordEntry): Question? {
        val letters = alphabeticLetters(word.word)
        if (letters.size < 4) return null
        var first = randomInt(1, letters.lastIndex)
        var second = randomInt(1, letters.lastIndex)
        if (second == first) {
            second += 1
            if (second > letters.lastIndex) second = 1
        }
        if (first > second) {
            val tmp = first
            first = second
            second = tmp
        }
        val missingIndices = listOf(first, second)
        val answers = listOf(letters[first], letters[second])
        val template = letters.mapIndexed { index, letter ->
            if (index == first || index == second) "_" else letter
        }.joinToString(" ")
        val optionSteps = listOf(
            letterOptionsFor(letters, answers[0], answers[1]),
            letterOptionsFor(letters, answers[1], answers[0]),
        )
        return Question(
            prompt = word.meaning,
            correctAnswer = word.word,
            options = optionSteps[0],
            wordId = word.id,
            kind = QuestionKind.FillLetterMedium,
            letterTemplateBase = template,
            missingIndices = missingIndices,
            letterOptionsSteps = optionSteps,
            letterAnswers = answers,
            currentStep = 0,
        )
    }

    private fun spellQuestionFor(word: WordEntry): Question? {
        val letters = alphabeticLetters(word.word)
        if (letters.size !in 4..9) return null
        val mask = letters.mapIndexed { index, _ -> index == 0 }
        val pool = shuffleWithRandom(letters.drop(1))
        return Question(
            prompt = word.meaning,
            correctAnswer = word.word,
            options = listOf(word.word),
            wordId = word.id,
            kind = QuestionKind.Spell,
            spellLetters = letters,
            spellRevealedMask = mask,
            spellPool = pool,
        )
    }

    private fun advanceMediumQuestion(question: Question, chosen: String): Question {
        val parts = question.letterTemplateBase.split(" ").toMutableList()
        val index = question.missingIndices.getOrNull(question.currentStep) ?: return question
        if (index in parts.indices) {
            parts[index] = chosen
        }
        val nextStep = (question.currentStep + 1).coerceAtMost(1)
        return question.copy(
            letterTemplateBase = parts.joinToString(" "),
            currentStep = nextStep,
            options = question.letterOptionsSteps.getOrElse(nextStep) { emptyList() },
        )
    }

    private fun nextQuestionAfter(currentWordId: String, monsterIndex: Int): Question {
        if (words.isEmpty()) {
            return stateFallbackQuestion(currentWordId)
        }
        val currentIndex = words.indexOfFirst { it.id == currentWordId || it.word == currentWordId }
        val nextIndex = when {
            words.size == 1 -> 0
            currentIndex < 0 -> 0
            else -> (currentIndex + 1) % words.size
        }
        return questionFor(words[nextIndex], monsterIndex)
    }

    private fun stateFallbackQuestion(currentAnswer: String): Question {
        return Question(
            prompt = currentAnswer,
            correctAnswer = currentAnswer,
            options = listOf(currentAnswer),
            wordId = currentAnswer,
        )
    }

    private fun correctOutcome(
        previousState: BattleState,
        answer: String,
        damage: Int,
        comboTriggered: Boolean,
        monsterDefeated: Boolean,
        nextState: BattleState,
    ): BattleAnswerOutcome {
        return BattleAnswerOutcome(
            selectedAnswer = answer,
            correctAnswer = previousState.question.correctAnswer,
            question = previousState.question,
            correct = true,
            damage = damage,
            comboTriggered = comboTriggered,
            monsterDefeated = monsterDefeated,
            playerDamaged = false,
            battleEnded = nextState.status != BattleStatus.Playing,
            nextState = nextState,
        )
    }

    private fun questionRoleFor(monsterIndex: Int): MonsterQuestionRole {
        return when {
            config.monsterCount >= 5 && monsterIndex == config.monsterCount -> MonsterQuestionRole.Boss
            monsterIndex == 2 -> MonsterQuestionRole.Spelling
            monsterIndex == 3 -> MonsterQuestionRole.Elite
            else -> MonsterQuestionRole.Normal
        }
    }

    private fun alphabeticLetters(word: String): List<String> {
        return word.lowercase().filter { it in 'a'..'z' }.map { it.toString() }
    }

    private fun letterOptionsFor(letters: List<String>, answer: String, otherAnswer: String? = null): List<String> {
        val wordLetters = letters.toSet()
        val distractors = alphabet.filter { it !in wordLetters && it != answer && it != otherAnswer }.take(2)
        val fallback = alphabet.filter { it != answer && it != otherAnswer }.take(2)
        val pool = if (distractors.size >= 2) distractors else fallback
        return shuffleWithRandom(listOf(answer, pool[0], pool[1]))
    }

    private fun shuffleWithRandom(values: List<String>): List<String> {
        val out = values.toMutableList()
        for (index in out.lastIndex downTo 1) {
            val raw = (randomDouble().coerceIn(0.0, 0.999999) * (index + 1)).toInt()
            val swapIndex = raw.coerceIn(0, index)
            val tmp = out[index]
            out[index] = out[swapIndex]
            out[swapIndex] = tmp
        }
        return out
    }

    private fun randomInt(minInclusive: Int, maxInclusive: Int): Int {
        if (maxInclusive < minInclusive) return minInclusive
        val span = maxInclusive - minInclusive + 1
        val offset = (randomDouble().coerceIn(0.0, 0.999999) * span).toInt().coerceIn(0, span - 1)
        return minInclusive + offset
    }

    companion object {
        private val alphabet = ('a'..'z').map { it.toString() }

        val demoWords = listOf(
            WordEntry("apple", "apple", "苹果"),
            WordEntry("banana", "banana", "香蕉"),
            WordEntry("cat", "cat", "猫"),
            WordEntry("dog", "dog", "狗"),
            WordEntry("sun", "sun", "太阳"),
        )
    }
}
