package cool.happyword.wordmagic.core

/**
 * Mutable per-word stats used only by [LearningReportBuilder] to mirror the
 * HarmonyOS `WordStat` + `MemoryScheduler` pipeline. Android persistence still
 * stores the slimmer [WordLearningStat] rows; we reconstruct scheduler state
 * by replaying merged wrong/correct counts in chronological order (wrongs first,
 * then corrects) so promotions match the shipped Harmony replay semantics.
 */
internal class ReportWordStat(
    var wordId: String = "",
    var seenCount: Int = 0,
    var correctCount: Int = 0,
    var wrongCount: Int = 0,
    var lastAnsweredMs: Long = 0L,
    var lastCorrectMs: Long = 0L,
    var nextReviewMs: Long = 0L,
    var memoryState: String = "new",
    var consecutiveCorrect: Int = 0,
    var consecutiveWrong: Int = 0,
    var mastery: Double = 0.0,
)

internal enum class ReportMemoryState(val wire: String) {
    NEW("new"),
    LEARNING("learning"),
    REVIEW("review"),
    FAMILIAR("familiar"),
    MASTERED("mastered"),
}

private const val INTERVAL_30_MIN_MS: Long = 30L * 60L * 1000L
private const val INTERVAL_1_DAY_MS: Long = 24L * 3600L * 1000L
private const val INTERVAL_3_DAY_MS: Long = 3L * INTERVAL_1_DAY_MS
private const val INTERVAL_14_DAY_MS: Long = 14L * INTERVAL_1_DAY_MS

private const val PROMOTE_TO_FAMILIAR_AT: Int = 2
private const val PROMOTE_TO_MASTERED_AT: Int = 5
private const val LEGACY_FAMILIAR_CORRECT_AT: Int = 4
private const val LEGACY_MASTERED_CORRECT_AT: Int = 10

private const val MASTERY_DELTA_CORRECT: Double = 0.1
private const val MASTERY_DELTA_WRONG: Double = 0.2

internal fun clampMastery(value: Double): Double = value.coerceIn(0.0, 1.0)

/**
 * Port of `harmonyos/.../MemoryScheduler.ets` for report reconstruction only.
 */
internal class ReportMemoryScheduler {
    fun applyAnswer(stat: ReportWordStat, correct: Boolean, nowMs: Long) {
        val current = coerceState(stat.memoryState)
        if (correct) {
            stat.lastCorrectMs = nowMs
            applyCorrect(stat, current, nowMs)
        } else {
            applyWrong(stat, nowMs)
        }
    }

    fun classify(stat: ReportWordStat, nowMs: Long): ReportMemoryState {
        if (stat.nextReviewMs > 0L && stat.nextReviewMs <= nowMs) {
            return ReportMemoryState.REVIEW
        }
        return coerceState(stat.memoryState)
    }

    private fun applyCorrect(stat: ReportWordStat, current: ReportMemoryState, nowMs: Long) {
        when (current) {
            ReportMemoryState.NEW -> {
                stat.memoryState = ReportMemoryState.LEARNING.wire
                stat.nextReviewMs = nowMs + INTERVAL_1_DAY_MS
            }
            ReportMemoryState.LEARNING -> {
                if (qualifiesForFamiliar(stat)) {
                    stat.memoryState = ReportMemoryState.FAMILIAR.wire
                    stat.nextReviewMs = nowMs + INTERVAL_3_DAY_MS
                } else {
                    stat.nextReviewMs = nowMs + INTERVAL_1_DAY_MS
                }
            }
            ReportMemoryState.REVIEW -> {
                stat.memoryState = ReportMemoryState.LEARNING.wire
                stat.nextReviewMs = nowMs + INTERVAL_1_DAY_MS
            }
            ReportMemoryState.FAMILIAR -> {
                if (qualifiesForMastered(stat)) {
                    stat.memoryState = ReportMemoryState.MASTERED.wire
                    stat.nextReviewMs = nowMs + INTERVAL_14_DAY_MS
                } else {
                    stat.nextReviewMs = nowMs + INTERVAL_3_DAY_MS
                }
            }
            ReportMemoryState.MASTERED -> {
                stat.nextReviewMs = nowMs + INTERVAL_14_DAY_MS
            }
        }
    }

    private fun qualifiesForFamiliar(stat: ReportWordStat): Boolean {
        if (stat.consecutiveCorrect >= PROMOTE_TO_FAMILIAR_AT) {
            return true
        }
        return stat.correctCount >= LEGACY_FAMILIAR_CORRECT_AT
    }

    private fun qualifiesForMastered(stat: ReportWordStat): Boolean {
        if (stat.consecutiveCorrect >= PROMOTE_TO_MASTERED_AT) {
            return true
        }
        return stat.correctCount >= LEGACY_MASTERED_CORRECT_AT
    }

    private fun applyWrong(stat: ReportWordStat, nowMs: Long) {
        stat.memoryState = ReportMemoryState.REVIEW.wire
        stat.nextReviewMs = nowMs + INTERVAL_30_MIN_MS
    }

    private fun coerceState(label: String): ReportMemoryState {
        return when (label) {
            ReportMemoryState.LEARNING.wire -> ReportMemoryState.LEARNING
            ReportMemoryState.REVIEW.wire -> ReportMemoryState.REVIEW
            ReportMemoryState.FAMILIAR.wire -> ReportMemoryState.FAMILIAR
            ReportMemoryState.MASTERED.wire -> ReportMemoryState.MASTERED
            else -> ReportMemoryState.NEW
        }
    }
}

internal fun mergeWordLearningStats(stats: List<WordLearningStat>): Map<String, MergedWordProgress> {
    val out = linkedMapOf<String, MergedWordProgress>()
    for (s in stats) {
        val m = out.getOrPut(s.wordId) { MergedWordProgress(s.wordId) }
        m.seen += s.seenCount
        m.correct += s.correctCount
        m.wrong += s.wrongCount
        m.lastMs = maxOf(m.lastMs, s.lastSeenAtMs)
    }
    return out
}

internal data class MergedWordProgress(
    val wordId: String,
    var seen: Int = 0,
    var correct: Int = 0,
    var wrong: Int = 0,
    var lastMs: Long = 0L,
)

/**
 * Rebuild a Harmony-shaped `ReportWordStat` from merged counters by replaying
 * answers. Wrong answers are replayed before correct ones so the memory ladder
 * stays pessimistic when ordering is unknown (matches worst-case promotion).
 */
internal fun replayReportWordStat(merged: MergedWordProgress, nowMs: Long): ReportWordStat {
    val stat = ReportWordStat(wordId = merged.wordId)
    val scheduler = ReportMemoryScheduler()
    val correctLeft = merged.correct.coerceAtLeast(0)
    val wrongLeft = merged.wrong.coerceAtLeast(0)
    val endMs = if (merged.lastMs > 0L) merged.lastMs else nowMs
    val totalReplay = (correctLeft + wrongLeft).coerceAtLeast(0)
    var t = endMs - totalReplay.toLong()
    if (t < 0L) {
        t = 0L
    }
    repeat(wrongLeft) {
        applyRecordedAnswer(stat, correct = false, timeMs = t, scheduler = scheduler)
        t += 1L
    }
    repeat(correctLeft) {
        applyRecordedAnswer(stat, correct = true, timeMs = t, scheduler = scheduler)
        t += 1L
    }
    stat.lastAnsweredMs = endMs
    return stat
}

private fun applyRecordedAnswer(
    stat: ReportWordStat,
    correct: Boolean,
    timeMs: Long,
    scheduler: ReportMemoryScheduler,
) {
    stat.seenCount += 1
    if (correct) {
        stat.correctCount += 1
        stat.consecutiveCorrect += 1
        stat.consecutiveWrong = 0
        stat.mastery = clampMastery(stat.mastery + MASTERY_DELTA_CORRECT)
    } else {
        stat.wrongCount += 1
        stat.consecutiveWrong += 1
        stat.consecutiveCorrect = 0
        stat.mastery = clampMastery(stat.mastery - MASTERY_DELTA_WRONG)
    }
    stat.lastAnsweredMs = timeMs
    scheduler.applyAnswer(stat, correct, timeMs)
}

internal fun localStartOfDayMillis(nowMs: Long): Long {
    val cal = java.util.Calendar.getInstance()
    cal.timeInMillis = nowMs
    cal.set(java.util.Calendar.HOUR_OF_DAY, 0)
    cal.set(java.util.Calendar.MINUTE, 0)
    cal.set(java.util.Calendar.SECOND, 0)
    cal.set(java.util.Calendar.MILLISECOND, 0)
    return cal.timeInMillis
}
