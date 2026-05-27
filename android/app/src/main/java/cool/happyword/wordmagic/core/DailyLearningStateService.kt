package cool.happyword.wordmagic.core

import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import kotlin.math.ceil

enum class ReviewReason {
    DueReview,
    RecentWrong,
    WeakWord,
}

data class DailyReviewSnapshot(
    val dayKey: String,
    val generatedAtMs: Long,
    val sourceCutoffMs: Long,
    val wordIds: List<String>,
    val reviewedWordIds: List<String> = emptyList(),
    val reasonsByWordId: Map<String, List<ReviewReason>> = emptyMap(),
)

data class DailyHomeStatus(
    val label: String,
    val remainingReviewCount: Int,
    val showReviewCountBadge: Boolean,
    val reviewAvailable: Boolean,
)

data class DailyLearningState(
    val dayKey: String,
    val packBattleWon: Boolean,
    val reviewAllDone: Boolean,
    val reviewSnapshot: DailyReviewSnapshot,
) {
    val remainingReviewWordIds: List<String>
        get() = reviewSnapshot.wordIds.filterNot { it in reviewSnapshot.reviewedWordIds.toSet() }

    val remainingReviewCount: Int
        get() = remainingReviewWordIds.size

    val todayAdventureCompleted: Boolean
        get() = packBattleWon && reviewAllDone

    val dailyCheckInCompleted: Boolean
        get() = packBattleWon || reviewAllDone

    companion object {
        fun empty(dayKey: String): DailyLearningState =
            DailyLearningState(
                dayKey = dayKey,
                packBattleWon = false,
                reviewAllDone = true,
                reviewSnapshot = DailyReviewSnapshot(
                    dayKey = dayKey,
                    generatedAtMs = 0L,
                    sourceCutoffMs = 0L,
                    wordIds = emptyList(),
                ),
            )
    }
}

class DailyLearningStateService {
    fun ensureDailyReviewSnapshot(
        current: DailyLearningState,
        nowMs: Long,
        activeWords: List<WordEntry>,
        selectedPackWordIds: Set<String>,
        stats: List<WordLearningStat>,
    ): DailyLearningState {
        val dayKey = localDayKey(nowMs)
        if (current.dayKey == dayKey && current.reviewSnapshot.dayKey == dayKey) {
            return current.copy(reviewAllDone = current.remainingReviewCount == 0)
        }
        val cutoff = localStartOfDayMs(nowMs)
        val statByWordId = stats
            .groupBy { it.wordId }
            .mapValues { (_, rows) -> rows.maxBy { it.lastSeenAtMs } }
        val candidates = activeWords.mapNotNull { word ->
            val stat = statByWordId[word.id] ?: return@mapNotNull null
            if (stat.lastSeenAtMs >= cutoff) return@mapNotNull null
            val reasons = reviewReasons(stat, cutoff)
            if (reasons.isEmpty()) return@mapNotNull null
            ReviewCandidate(
                wordId = word.id,
                reasons = reasons,
                score = reviewScore(stat, reasons, cutoff, word.id in selectedPackWordIds),
                lastAnsweredMs = stat.lastSeenAtMs,
            )
        }.sortedWith(
            compareByDescending<ReviewCandidate> { it.score }
                .thenByDescending { it.lastAnsweredMs }
                .thenBy { it.wordId },
        ).take(MAX_REVIEW_WORDS)

        val wordIds = candidates.map { it.wordId }
        val snapshot = DailyReviewSnapshot(
            dayKey = dayKey,
            generatedAtMs = nowMs,
            sourceCutoffMs = cutoff,
            wordIds = wordIds,
            reviewedWordIds = emptyList(),
            reasonsByWordId = candidates.associate { it.wordId to it.reasons },
        )
        return DailyLearningState(
            dayKey = dayKey,
            packBattleWon = false,
            reviewAllDone = wordIds.isEmpty(),
            reviewSnapshot = snapshot,
        )
    }

    fun markPackBattleWon(state: DailyLearningState): DailyLearningState =
        state.copy(packBattleWon = true, reviewAllDone = state.remainingReviewCount == 0)

    fun markReviewedWords(state: DailyLearningState, wordIds: List<String>): DailyLearningState {
        val reviewSet = state.reviewSnapshot.wordIds.toSet()
        val nextReviewed = (state.reviewSnapshot.reviewedWordIds + wordIds.filter { it in reviewSet })
            .distinct()
        val nextSnapshot = state.reviewSnapshot.copy(reviewedWordIds = nextReviewed)
        val remaining = nextSnapshot.wordIds.any { it !in nextReviewed.toSet() }
        return state.copy(reviewSnapshot = nextSnapshot, reviewAllDone = !remaining)
    }

    fun homeStatus(state: DailyLearningState): DailyHomeStatus {
        val remaining = state.remainingReviewCount
        val label = when {
            !state.packBattleWon -> "请选择一个场景加战斗"
            remaining > 0 -> "请点击复习加战斗($remaining)"
            else -> "已完成"
        }
        return DailyHomeStatus(
            label = label,
            remainingReviewCount = remaining,
            showReviewCountBadge = state.packBattleWon && remaining > 0,
            reviewAvailable = remaining > 0,
        )
    }

    private fun reviewReasons(stat: WordLearningStat, cutoffMs: Long): List<ReviewReason> {
        val out = mutableListOf<ReviewReason>()
        if (stat.nextReviewMs > 0L && stat.nextReviewMs <= cutoffMs) {
            out += ReviewReason.DueReview
        }
        if (stat.inferredLastOutcome() == WordAnswerOutcome.Wrong && cutoffMs - stat.lastSeenAtMs <= SEVEN_DAYS_MS) {
            out += ReviewReason.RecentWrong
        }
        val accuracy = stat.correctCount.toDouble() / stat.seenCount.coerceAtLeast(1).toDouble()
        val weak = stat.memoryState != WordMemoryState.Mastered &&
            (
                (stat.seenCount >= 3 && accuracy < 0.6) ||
                    (stat.wrongCount >= 2 && stat.correctCount <= stat.wrongCount) ||
                    (stat.seenCount >= 2 && stat.mastery <= 35)
                )
        if (weak) {
            out += ReviewReason.WeakWord
        }
        return out
    }

    private fun reviewScore(
        stat: WordLearningStat,
        reasons: List<ReviewReason>,
        cutoffMs: Long,
        selectedPackWord: Boolean,
    ): Int {
        val overdueDays = if (stat.nextReviewMs > 0L && stat.nextReviewMs <= cutoffMs) {
            ((cutoffMs - stat.nextReviewMs) / DAY_MS).toInt().coerceIn(0, 14)
        } else {
            0
        }
        val wrongAge = cutoffMs - stat.lastSeenAtMs
        val recentWrongBoost = when {
            ReviewReason.RecentWrong !in reasons -> 0
            wrongAge <= DAY_MS -> 20
            wrongAge <= 3 * DAY_MS -> 10
            wrongAge <= SEVEN_DAYS_MS -> 5
            else -> 0
        }
        return (if (ReviewReason.DueReview in reasons) 100 else 0) +
            (if (ReviewReason.RecentWrong in reasons) 80 else 0) +
            (if (ReviewReason.WeakWord in reasons) 50 else 0) +
            overdueDays * 4 +
            recentWrongBoost +
            if (selectedPackWord) 5 else 0
    }

    private data class ReviewCandidate(
        val wordId: String,
        val reasons: List<ReviewReason>,
        val score: Int,
        val lastAnsweredMs: Long,
    )

    companion object {
        private const val MAX_REVIEW_WORDS = 50
        private const val DAY_MS = 24L * 60L * 60L * 1000L
        private const val SEVEN_DAYS_MS = 7L * DAY_MS
        private val compactDayFormatter: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyyMMdd")

        fun localDayKey(nowMs: Long): String =
            Instant.ofEpochMilli(nowMs).atZone(ZoneId.systemDefault()).toLocalDate().format(compactDayFormatter)

        fun localStartOfDayMs(nowMs: Long): Long {
            val zone = ZoneId.systemDefault()
            return Instant.ofEpochMilli(nowMs).atZone(zone).toLocalDate().atStartOfDay(zone).toInstant().toEpochMilli()
        }

        fun reviewMonsterCount(requiredWordCount: Int, monsterHp: Int, configuredMonstersTotal: Int): Int {
            val defaultHp = GameConfig().monsterHp
            val hp = if (monsterHp > 0) monsterHp else defaultHp
            val configured = configuredMonstersTotal.coerceAtLeast(1)
            val approx = hp * 4.0 / 3.0
            val raw = ceil(requiredWordCount.coerceAtLeast(1) / approx).toInt().coerceAtLeast(1)
            return raw.coerceAtMost(configured)
        }
    }
}
