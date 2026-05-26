package cool.happyword.wordmagic.core

enum class WordAnswerOutcome {
    Correct,
    Wrong,
    Unknown,
}

enum class WordMemoryState {
    New,
    Learning,
    Review,
    Familiar,
    Mastered,
}

data class WordLearningStat(
    val packId: String,
    val wordId: String,
    val seenCount: Int,
    val correctCount: Int,
    val wrongCount: Int,
    val lastSeenAtMs: Long,
    val nextReviewMs: Long = 0L,
    val memoryState: WordMemoryState = WordMemoryState.New,
    val consecutiveCorrect: Int = 0,
    val consecutiveWrong: Int = 0,
    val mastery: Int = 0,
    val lastOutcome: WordAnswerOutcome = WordAnswerOutcome.Unknown,
) {
    val accuracyPercent: Int
        get() = if (seenCount == 0) 0 else (correctCount * 100) / seenCount

    fun inferredLastOutcome(): WordAnswerOutcome = when {
        lastOutcome != WordAnswerOutcome.Unknown -> lastOutcome
        consecutiveWrong > 0 -> WordAnswerOutcome.Wrong
        consecutiveCorrect > 0 -> WordAnswerOutcome.Correct
        else -> WordAnswerOutcome.Unknown
    }
}

data class BattleSessionRecord(
    val packId: String,
    val won: Boolean,
    val stars: Int,
    val correctCount: Int,
    val wrongCount: Int,
    val defeatedMonsters: Int,
    val completedAtMs: Long,
) {
    val perfect: Boolean
        get() = won && wrongCount == 0
}

class LearningRecorder(
    initialStats: List<WordLearningStat> = emptyList(),
    initialSessions: List<BattleSessionRecord> = emptyList(),
) {
    private val statsByKey = linkedMapOf<String, WordLearningStat>()
    private val sessions = mutableListOf<BattleSessionRecord>()

    init {
        initialStats.forEach { statsByKey[key(it.packId, it.wordId)] = it }
        sessions += initialSessions
    }

    fun recordAnswer(packId: String, wordId: String, correct: Boolean, answeredAtMs: Long) {
        val key = key(packId, wordId)
        val previous = statsByKey[key]
        val nextCorrectStreak = if (correct) (previous?.consecutiveCorrect ?: 0) + 1 else 0
        val nextWrongStreak = if (correct) 0 else (previous?.consecutiveWrong ?: 0) + 1
        statsByKey[key] = WordLearningStat(
            packId = packId,
            wordId = wordId,
            seenCount = (previous?.seenCount ?: 0) + 1,
            correctCount = (previous?.correctCount ?: 0) + if (correct) 1 else 0,
            wrongCount = (previous?.wrongCount ?: 0) + if (correct) 0 else 1,
            lastSeenAtMs = answeredAtMs,
            nextReviewMs = nextReviewMs(answeredAtMs, correct),
            memoryState = nextMemoryState(previous, correct, nextCorrectStreak),
            consecutiveCorrect = nextCorrectStreak,
            consecutiveWrong = nextWrongStreak,
            mastery = ((previous?.mastery ?: 0) + if (correct) 12 else -20).coerceIn(0, 100),
            lastOutcome = if (correct) WordAnswerOutcome.Correct else WordAnswerOutcome.Wrong,
        )
    }

    fun recordSession(record: BattleSessionRecord) {
        sessions += record
    }

    fun statsSnapshot(): List<WordLearningStat> = statsByKey.values.toList()

    fun sessionSnapshot(): List<BattleSessionRecord> = sessions.toList()

    fun recentWrongIds(limit: Int): List<String> {
        if (limit <= 0) return emptyList()
        return statsByKey.values
            .filter { it.wrongCount > 0 }
            .sortedWith(
                compareByDescending<WordLearningStat> { it.lastSeenAtMs }
                    .thenBy { it.wordId },
            )
            .map { it.wordId }
            .distinct()
            .take(limit)
    }

    private fun key(packId: String, wordId: String): String = "$packId::$wordId"

    private fun nextReviewMs(answeredAtMs: Long, correct: Boolean): Long =
        answeredAtMs + if (correct) DAY_MS else THIRTY_MINUTES_MS

    private fun nextMemoryState(previous: WordLearningStat?, correct: Boolean, correctStreak: Int): WordMemoryState {
        if (!correct) return WordMemoryState.Review
        return when {
            correctStreak >= 5 -> WordMemoryState.Mastered
            correctStreak >= 2 -> WordMemoryState.Familiar
            previous?.memoryState == WordMemoryState.New || previous == null -> WordMemoryState.Learning
            else -> previous.memoryState
        }
    }

    companion object {
        private const val THIRTY_MINUTES_MS = 30L * 60L * 1000L
        private const val DAY_MS = 24L * 60L * 60L * 1000L
    }
}
