package cool.happyword.wordmagic.core

private enum class MonsterQuestionRole {
    Normal,
    Spelling,
    Elite,
    Boss,
}

internal object BattleRewardCalc {
    fun coinValueFor(level: MonsterLevel): Int {
        return when (level) {
            MonsterLevel.Beginner -> 1
            MonsterLevel.Intermediate -> 2
            MonsterLevel.Advanced -> 3
            MonsterLevel.Super -> 4
        }
    }

    fun coinAward(monsterLevelScore: Int): Int = monsterLevelScore.coerceAtLeast(0)

    @Suppress("UNUSED_PARAMETER")
    fun retiredBonusCoinDelta(stars: Int, bonusKillCount: Int, won: Boolean): Int = 0
}

class BattleEngine(
    private val config: GameConfig = GameConfig(),
    private val words: List<WordEntry> = demoWords,
    targetWordIds: List<String> = words.map { it.id },
    private val shuffleOptions: (List<String>) -> List<String> = { options -> options.shuffled() },
    private val randomDouble: () -> Double = { Math.random() },
    private val monsterCatalogIndex: ((Int) -> Int)? = null,
    servedQuestions: List<BattleServedQuestion> = emptyList(),
) {
    private val targetWordIds: List<String> = targetWordIds.filter { it.isNotBlank() }.distinct()
    private val scheduler: BattleQuestionScheduler = BattleQuestionScheduler(
        rawPlanWordIds = this.targetWordIds,
        enabledTypes = config.sanitizedQuestionTypes(),
        rng = randomDouble,
    )
    private var typeWordCursor = 0

    init {
        if (servedQuestions.isNotEmpty()) {
            scheduler.restoreServedQuestions(servedQuestions, canServeQuestionType())
        }
    }

    /** V0.8.4 — Spell wrong letter tap: −1 HP without advancing the question. */
    fun applySpellLetterPenalty(state: BattleState): Pair<Int, BattleState> {
        if (state.status != BattleStatus.Playing) return 0 to state
        val nextPlayerHp = (state.playerHp - 1).coerceAtLeast(0)
        val nextState = state.copy(
            playerHp = nextPlayerHp,
            status = if (nextPlayerHp <= 0) BattleStatus.Lost else BattleStatus.Playing,
        )
        return 1 to nextState
    }

    fun spellLetterPenaltyOutcome(state: BattleState): BattleAnswerOutcome {
        val (damage, nextState) = applySpellLetterPenalty(state)
        return BattleAnswerOutcome(
            selectedAnswer = "",
            correctAnswer = state.question.correctAnswer,
            question = state.question,
            correct = false,
            damage = damage,
            comboTriggered = false,
            monsterDefeated = false,
            playerDamaged = damage > 0,
            battleEnded = nextState.status != BattleStatus.Playing,
            nextState = nextState,
        )
    }

    fun initialState(): BattleState {
        val catalogIndex = catalogIndexFor(1)
        val question = nextScheduledQuestion(null, monsterIndex = 1)
        return BattleState(
            playerHp = config.playerHp,
            monsterHp = config.monsterHp,
            monsterIndex = 1,
            combo = 0,
            correctCount = 0,
            wrongCount = 0,
            defeatedMonsters = 0,
            question = question,
            currentMonsterBonus = rollsBonusMonster(monsterIndex = catalogIndex),
            monsterCatalogIndex = catalogIndex,
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
            val attackDamage = monsterAttackDamage(state.monsterCatalogIndex)
            val nextPlayerHp = (state.playerHp - attackDamage).coerceAtLeast(0)
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
                damage = attackDamage,
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
        val bonusKillCount = state.bonusKillCount + if (state.currentMonsterBonus) 1 else 0
        val defeatedMonsterLevelScore = state.defeatedMonsterLevelScore + BattleRewardCalc.coinValueFor(
            MonsterLevel.forCatalogIndex(state.monsterCatalogIndex),
        )
        if (defeated >= config.monsterCount) {
            val nextState = state.copy(
                monsterHp = 0,
                combo = nextCombo,
                correctCount = state.correctCount + 1,
                defeatedMonsters = defeated,
                bonusKillCount = bonusKillCount,
                defeatedMonsterLevelScore = defeatedMonsterLevelScore,
                status = BattleStatus.Won,
            )
            return correctOutcome(state, answer, damage, comboTriggered, monsterDefeated = true, nextState = nextState)
        }

        val nextMonsterIndex = state.monsterIndex + 1
        val nextMonsterCatalogIndex = catalogIndexFor(nextMonsterIndex)
        val nextState = state.copy(
            monsterHp = config.monsterHp,
            monsterIndex = nextMonsterIndex,
            combo = nextCombo,
            correctCount = state.correctCount + 1,
            defeatedMonsters = defeated,
            bonusKillCount = bonusKillCount,
            defeatedMonsterLevelScore = defeatedMonsterLevelScore,
            question = nextQuestionAfter(state.question.wordId, nextMonsterIndex),
            currentMonsterBonus = rollsBonusMonster(nextMonsterCatalogIndex),
            monsterCatalogIndex = nextMonsterCatalogIndex,
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
        val coinDelta = BattleRewardCalc.coinAward(state.defeatedMonsterLevelScore)
        return SessionResult(
            won = state.status == BattleStatus.Won,
            stars = stars,
            defeatedMonsters = state.defeatedMonsters,
            correctCount = state.correctCount,
            wrongCount = state.wrongCount,
            learnedWordCount = state.correctCount,
            coinDelta = coinDelta,
            bonusKillCount = state.bonusKillCount,
            monsterLevelScore = state.defeatedMonsterLevelScore,
        )
    }

    private fun isCorrectAnswer(question: Question, answer: String): Boolean {
        return when (question.kind) {
            QuestionKind.Choice -> answer == question.correctAnswer
            QuestionKind.SentenceCloze -> answer == question.correctAnswer
            QuestionKind.FillLetter -> answer == question.letterAnswer
            QuestionKind.FillLetterMedium -> answer == question.letterAnswers.getOrNull(question.currentStep)
            QuestionKind.Spell -> answer == question.correctAnswer
        }
    }

    private fun enabledKindSet(): Set<QuestionKind> =
        config.sanitizedQuestionTypes().mapNotNull { BattleQuestionTypePolicy.typeIdToKind(it) }.toSet()

    private fun kindEnabled(kind: QuestionKind): Boolean = enabledKindSet().contains(kind)

    private fun nextScheduledQuestion(lastWordId: String?, monsterIndex: Int): Question {
        if (words.isEmpty()) {
            return stateFallbackQuestion(lastWordId ?: "")
        }
        val canServe = canServeQuestionType()
        val pick = scheduler.pickNext(lastWordId, canServe)
        val word = when {
            pick.preferredWordId.isNotEmpty() -> words.find { it.id == pick.preferredWordId }
            else -> null
        } ?: pickWordForType(pick.kind, lastWordId) ?: words.first()
        val phasePool = scheduler.activePhasePool()
        val resolvedType = BattleQuestionTypePolicy.resolveQuestionTypeWithinPool(word, pick.kind, phasePool)
        val question = questionForType(word, resolvedType, monsterIndex)
        scheduler.markServed(word.id, BattleQuestionTypePolicy.kindToTypeId(question.kind), canServe)
        return question
    }

    private fun canServeQuestionType(): WordKindSupportFn =
        { wordId, kind ->
            words.find { it.id == wordId }?.let { BattleQuestionTypePolicy.wordSupportsQuestionType(it, kind) }
                ?: false
        }

    private fun pickWordForType(typeId: String, lastWordId: String?): WordEntry? {
        val targetWords = targetWordIds.mapNotNull { id -> words.find { it.id == id } }
        pickSupportedWordFrom(targetWords, typeId, lastWordId)?.let { return it }
        if (words.isEmpty()) return null
        val fallbackWords = targetWords.ifEmpty { words }
        val currentIndex = fallbackWords.indexOfFirst { it.id == lastWordId }
        val nextIndex = when {
            fallbackWords.size == 1 -> 0
            currentIndex < 0 -> 0
            else -> (currentIndex + 1) % fallbackWords.size
        }
        return fallbackWords[nextIndex]
    }

    private fun pickSupportedWordFrom(candidates: List<WordEntry>, typeId: String, lastWordId: String?): WordEntry? {
        if (candidates.isEmpty()) return null
        var skippedLast: WordEntry? = null
        repeat(candidates.size) {
            val entry = candidates[typeWordCursor % candidates.size]
            typeWordCursor = (typeWordCursor + 1) % candidates.size
            if (!BattleQuestionTypePolicy.wordSupportsQuestionType(entry, typeId)) return@repeat
            if (candidates.size > 1 && entry.id == lastWordId) {
                if (skippedLast == null) skippedLast = entry
                return@repeat
            }
            return entry
        }
        return skippedLast
    }

    private fun questionForType(word: WordEntry, typeId: String, monsterIndex: Int): Question {
        val builders: List<(WordEntry) -> Question?> = when (typeId) {
            BattleQuestionTypePolicy.SPELL -> listOf(::spellQuestionFor, ::mediumFillLetterQuestionFor, ::fillLetterQuestionFor, { w -> choiceQuestionFor(w) })
            BattleQuestionTypePolicy.SENTENCE_CLOZE -> listOf(::sentenceClozeQuestionFor, ::mediumFillLetterQuestionFor, ::spellQuestionFor, ::fillLetterQuestionFor, { w -> choiceQuestionFor(w) })
            BattleQuestionTypePolicy.FILL_LETTER_MEDIUM -> listOf(::mediumFillLetterQuestionFor, ::fillLetterQuestionFor, { w -> choiceQuestionFor(w) })
            BattleQuestionTypePolicy.FILL_LETTER -> listOf(::fillLetterQuestionFor, { w -> choiceQuestionFor(w) })
            else -> listOf({ w -> choiceQuestionFor(w) })
        }
        for (builder in builders) {
            val q = builder(word) ?: continue
            if (kindEnabled(q.kind)) return q
        }
        return choiceQuestionFor(word)
    }

    private fun questionFor(word: WordEntry, monsterIndex: Int): Question {
        return nextScheduledQuestion(word.id, monsterIndex)
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

    private fun sentenceClozeQuestionFor(word: WordEntry): Question? {
        val example = word.example ?: return null
        val span = findSentenceClozeTargetSpan(example.en, word.word) ?: return null
        if (example.zh.trim().isEmpty()) return null
        val options = sentenceClozeOptionsFor(word)
        if (options.size < 3) return null
        val template = example.en.substring(0, span.start) + "____" + example.en.substring(span.endExclusive)
        return Question(
            prompt = word.meaning,
            correctAnswer = word.word,
            options = shuffleWithRandom(options.take(3)),
            wordId = word.id,
            kind = QuestionKind.SentenceCloze,
            sentenceTemplate = template,
            sentenceZh = example.zh,
        )
    }

    private fun sentenceClozeOptionsFor(word: WordEntry): List<String> {
        val out = mutableListOf<String>()
        fun push(value: String) {
            val trimmed = value.trim()
            if (trimmed.isNotEmpty() && out.none { it.equals(trimmed, ignoreCase = true) }) {
                out.add(trimmed)
            }
        }
        push(word.word)
        word.distractors.forEach(::push)
        for (entry in words) {
            if (entry.id == word.id) continue
            push(entry.word)
            if (out.size >= 3) break
        }
        return out
    }

    private fun fillLetterQuestionFor(word: WordEntry): Question? {
        val tokens = phraseTokens(word.word)
        val letters = tokens.filter { it.isLetter }.map { it.glyph }
        val fillable = tokens.filter { it.isLetter && !it.isArticle }
        if (fillable.size < 3) return null
        val missingToken = fillable[randomInt(1, fillable.lastIndex)]
        val missingIndex = missingToken.originalIndex
        val letterAnswer = missingToken.glyph
        val template = templateFromTokens(tokens, setOf(missingIndex))
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
        val tokens = phraseTokens(word.word)
        val letters = tokens.filter { it.isLetter }.map { it.glyph }
        val fillable = tokens.filter { it.isLetter && !it.isArticle }
        if (fillable.size < 4) return null
        var first = randomInt(1, fillable.lastIndex)
        var second = randomInt(1, fillable.lastIndex)
        if (second == first) {
            second += 1
            if (second > fillable.lastIndex) second = 1
        }
        var firstToken = fillable[first]
        var secondToken = fillable[second]
        if (firstToken.originalIndex > secondToken.originalIndex) {
            val tmp = firstToken
            firstToken = secondToken
            secondToken = tmp
        }
        val missingIndices = listOf(firstToken.originalIndex, secondToken.originalIndex)
        val answers = listOf(firstToken.glyph, secondToken.glyph)
        val template = templateFromTokens(tokens, missingIndices.toSet())
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
        val tokens = phraseTokens(word.word)
        val fillableIndices = tokens.indices.filter { tokens[it].isLetter && !tokens[it].isArticle }
        if (fillableIndices.size !in 4..9) return null
        val letters = tokens.map { it.glyph }
        val mask = tokens.mapIndexed { index, token ->
            !token.isLetter || token.isArticle || index == fillableIndices.first()
        }
        val pool = shuffleWithRandom(fillableIndices.drop(1).map { letters[it] })
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
        val blankIndex = question.letterTemplateBase.indexOf('_')
        if (blankIndex < 0) return question
        val template = question.letterTemplateBase.replaceRange(blankIndex, blankIndex + 1, chosen)
        val nextStep = (question.currentStep + 1).coerceAtMost(1)
        return question.copy(
            letterTemplateBase = template,
            currentStep = nextStep,
            options = question.letterOptionsSteps.getOrElse(nextStep) { emptyList() },
        )
    }

    private fun nextQuestionAfter(currentWordId: String, monsterIndex: Int): Question =
        nextScheduledQuestion(currentWordId, monsterIndex)

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

    private fun letterOptionsFor(letters: List<String>, answer: String, otherAnswer: String? = null): List<String> {
        val wordLetters = letters.toSet()
        val distractors = alphabet.filter { it !in wordLetters && it != answer && it != otherAnswer }
        val fallback = alphabet.filter { it != answer && it != otherAnswer }
        val pool = shuffleWithRandom(if (distractors.size >= 2) distractors else fallback).take(2)
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

    private fun catalogIndexFor(monsterIndex: Int): Int {
        monsterCatalogIndex?.invoke(monsterIndex)?.let { return it }
        val canServe: WordKindSupportFn = { wordId, kind ->
            words.find { it.id == wordId }?.let { BattleQuestionTypePolicy.wordSupportsQuestionType(it, kind) }
                ?: false
        }
        return scheduler.catalogIndexForMonster(monsterIndex, canServe)
    }

    private fun monsterAttackDamage(monsterIndex: Int): Int {
        return when (MonsterLevel.forCatalogIndex(monsterIndex)) {
            MonsterLevel.Advanced, MonsterLevel.Super -> if (randomDouble() < 0.5) 2 else 1
            else -> 1
        }
    }

    private fun rollsBonusMonster(monsterIndex: Int): Boolean {
        when (MonsterLevel.forCatalogIndex(monsterIndex)) {
            MonsterLevel.Advanced, MonsterLevel.Super -> Unit
            else -> return false
        }
        return randomDouble() < 0.3
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

private data class PhraseToken(
    val glyph: String,
    val originalIndex: Int,
    val isLetter: Boolean,
    val isArticle: Boolean,
)

private fun phraseTokens(raw: String): List<PhraseToken> {
    val chars = raw.lowercase().toList()
    val articlePositions = mutableSetOf<Int>()
    var index = 0
    while (index < chars.size) {
        if (chars[index] !in 'a'..'z') {
            index += 1
            continue
        }
        val start = index
        val builder = StringBuilder()
        while (index < chars.size && chars[index] in 'a'..'z') {
            builder.append(chars[index])
            index += 1
        }
        if (builder.toString() in setOf("a", "an", "the")) {
            for (position in start until index) {
                articlePositions.add(position)
            }
        }
    }
    return chars.mapIndexedNotNull { position, char ->
        when {
            char in 'a'..'z' -> PhraseToken(char.toString(), position, isLetter = true, isArticle = position in articlePositions)
            char == ' ' -> PhraseToken(" ", position, isLetter = false, isArticle = false)
            else -> null
        }
    }
}

private fun templateFromTokens(tokens: List<PhraseToken>, missingPositions: Set<Int>): String {
    return tokens.joinToString(" ") { token ->
        if (token.isLetter && token.originalIndex in missingPositions) "_" else token.glyph
    }
}
