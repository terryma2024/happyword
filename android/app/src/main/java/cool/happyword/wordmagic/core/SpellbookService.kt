package cool.happyword.wordmagic.core

enum class SpellbookCardState {
    Locked,
    Seen,
    Mastered,
}

data class SpellbookProgress(
    val totalCount: Int,
    val seenCount: Int,
    val masteredCount: Int,
) {
    val isComplete: Boolean
        get() = totalCount > 0 && masteredCount == totalCount
}

object SpellbookService {
    const val REWARD_COINS: Int = 50

    fun cardState(word: WordEntry, stat: WordLearningStat?): SpellbookCardState {
        if (word.id.isBlank() || stat == null || stat.seenCount <= 0) return SpellbookCardState.Locked
        return if (stat.memoryState == WordMemoryState.Mastered) SpellbookCardState.Mastered else SpellbookCardState.Seen
    }

    fun progress(words: List<WordEntry>, statsByWordId: Map<String, WordLearningStat>): SpellbookProgress {
        var seen = 0
        var mastered = 0
        words.forEach { word ->
            when (cardState(word, statsByWordId[word.id])) {
                SpellbookCardState.Locked -> Unit
                SpellbookCardState.Seen -> seen += 1
                SpellbookCardState.Mastered -> {
                    seen += 1
                    mastered += 1
                }
            }
        }
        return SpellbookProgress(totalCount = words.size, seenCount = seen, masteredCount = mastered)
    }
}
