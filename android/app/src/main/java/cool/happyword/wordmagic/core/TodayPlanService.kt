package cool.happyword.wordmagic.core

import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

data class TodayPlan(
    val review: List<WordEntry>,
    val learning: List<WordEntry>,
    val newWords: List<WordEntry>,
)

data class TodayPlanWordRow(
    val entry: WordEntry,
    val doneHighlight: Boolean,
    val stat: WordLearningStat?,
)

data class TodayPlanUi(
    val regionDisplayName: String,
    val dayKey: String,
    val progressText: String,
    val review: List<TodayPlanWordRow>,
    val learning: List<TodayPlanWordRow>,
    val newWords: List<TodayPlanWordRow>,
) {
    fun total(): Int = review.size + learning.size + newWords.size

    fun doneCount(): Int = (review + learning + newWords).count { it.doneHighlight }
}

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

    /**
     * Plan data plus header fields and per-row stats for the read-only
     * Today Plan screen (aligned with HarmonyOS TodayPlanPage).
     */
    fun buildUi(
        library: PackLibrary,
        activeIds: List<String>,
        stats: List<WordLearningStat>,
        regionDisplayName: String,
        nowMs: Long,
        dailyState: DailyLearningState? = null,
    ): TodayPlanUi {
        val plan = build(library, activeIds, stats)
        val startOfDayMs = startOfDayMillis(nowMs)
        val statsByWordId = stats
            .groupBy { it.wordId }
            .mapValues { (_, list) -> list.maxBy { it.lastSeenAtMs } }
        val reviewedDailyIds = dailyState?.reviewSnapshot?.reviewedWordIds?.toSet().orEmpty()
        fun row(word: WordEntry, forceDailyReview: Boolean = false): TodayPlanWordRow {
            val st = statsByWordId[word.id]
            val done = if (forceDailyReview) {
                word.id in reviewedDailyIds
            } else {
                st != null &&
                st.lastSeenAtMs >= startOfDayMs &&
                st.correctCount > st.wrongCount
            }
            return TodayPlanWordRow(entry = word, doneHighlight = done, stat = st)
        }
        val wordsById = library.allPacks().flatMap { it.words }.associateBy { it.id }
        val reviewRows = dailyState?.reviewSnapshot?.wordIds
            ?.mapNotNull { wordsById[it] }
            ?.map { row(it, forceDailyReview = true) }
            ?: plan.review.map(::row)
        val progress = if (dailyState != null) {
            DailyLearningStateService().homeStatus(dailyState).label
        } else {
            "今天的计划：${plan.review.size + plan.learning.size + plan.newWords.size} 个单词"
        }
        return TodayPlanUi(
            regionDisplayName = regionDisplayName,
            dayKey = localDayKey(nowMs),
            progressText = progress,
            review = reviewRows,
            learning = plan.learning.map(::row),
            newWords = plan.newWords.map(::row),
        )
    }

    companion object {
        private val dayKeyFormatter: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyyMMdd")

        fun localDayKey(nowMs: Long): String =
            Instant.ofEpochMilli(nowMs).atZone(ZoneId.systemDefault()).toLocalDate().format(dayKeyFormatter)

        fun startOfDayMillis(nowMs: Long): Long {
            val zone = ZoneId.systemDefault()
            val localDate = Instant.ofEpochMilli(nowMs).atZone(zone).toLocalDate()
            return localDate.atStartOfDay(zone).toInstant().toEpochMilli()
        }

        /** Rough memory label from aggregate stats (Harmony uses a richer scheduler). */
        fun describeMemoryStat(stat: WordLearningStat?): String {
            if (stat == null) return "新词"
            if (stat.wrongCount > 0) return "待复习"
            if (stat.seenCount == 0) return "新词"
            if (stat.accuracyPercent >= 90) return "掌握"
            if (stat.accuracyPercent >= 60) return "熟悉"
            return "学习中"
        }
    }
}
