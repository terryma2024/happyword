package cool.happyword.wordmagic.core

data class TodayPlan(
    val review: List<WordEntry>,
    val learning: List<WordEntry>,
    val newWords: List<WordEntry>,
)

class TodayPlanService {
    fun build(library: PackLibrary, activeIds: List<String>, stats: List<WordLearningStat>): TodayPlan {
        val statsByWord = stats.associateBy { it.wordId }
        val activeWords = library.activePacks(activeIds).flatMap { it.words }
        val review = activeWords.filter { word ->
            val stat = statsByWord[word.id]
            stat != null && stat.wrongCount > 0
        }
        val learning = activeWords.filter { word ->
            val stat = statsByWord[word.id]
            stat != null && stat.wrongCount == 0 && stat.seenCount > 0
        }
        val newWords = activeWords.filter { word -> statsByWord[word.id] == null }
        return TodayPlan(review = review, learning = learning, newWords = newWords)
    }
}
