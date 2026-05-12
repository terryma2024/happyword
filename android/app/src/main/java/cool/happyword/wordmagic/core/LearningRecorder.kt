package cool.happyword.wordmagic.core

data class WordLearningStat(
    val packId: String,
    val wordId: String,
    val seenCount: Int,
    val correctCount: Int,
    val wrongCount: Int,
    val lastSeenAtMs: Long,
) {
    val accuracyPercent: Int
        get() = if (seenCount == 0) 0 else (correctCount * 100) / seenCount
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
        statsByKey[key] = WordLearningStat(
            packId = packId,
            wordId = wordId,
            seenCount = (previous?.seenCount ?: 0) + 1,
            correctCount = (previous?.correctCount ?: 0) + if (correct) 1 else 0,
            wrongCount = (previous?.wrongCount ?: 0) + if (correct) 0 else 1,
            lastSeenAtMs = answeredAtMs,
        )
    }

    fun recordSession(record: BattleSessionRecord) {
        sessions += record
    }

    fun statsSnapshot(): List<WordLearningStat> = statsByKey.values.toList()

    fun sessionSnapshot(): List<BattleSessionRecord> = sessions.toList()

    private fun key(packId: String, wordId: String): String = "$packId::$wordId"
}
