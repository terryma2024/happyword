package cool.happyword.wordmagic.core

/**
 * Per-pack row in the learning report. Mirrors HarmonyOS `PackReport`.
 */
data class PackReport(
    val packId: String,
    val name: String,
    val active: Boolean,
    val totalSeen: Int,
    val totalCorrect: Int,
    val accuracyPct: Int,
)

/**
 * Aggregate snapshot for [LearningReportScreen]. Mirrors HarmonyOS `LearningReport`.
 */
data class LearningReport(
    val accuracyPct: Int,
    val totalSeen: Int,
    val totalCorrect: Int,
    val masteredCount: Int,
    val familiarCount: Int,
    val learningCount: Int,
    val newCount: Int,
    val reviewDoneTodayCount: Int,
    val reviewDueCount: Int,
    val reviewCompletionPct: Int,
    val packs: List<PackReport>,
)

/**
 * Port of `harmonyos/.../LearningReportBuilder.ets` fed by Android's persisted
 * [WordLearningStat] rows (merged per `wordId`, replayed through the Harmony
 * memory scheduler — see `LearningReportMemory.kt`).
 */
class LearningReportBuilder {
    private val scheduler: ReportMemoryScheduler = ReportMemoryScheduler()

    fun build(
        library: PackLibrary,
        activeIds: List<String>,
        stats: List<WordLearningStat>,
        nowMs: Long = System.currentTimeMillis(),
    ): LearningReport {
        val allPacks = library.allPacks()
        val knownWordIds = buildSet {
            for (p in allPacks) {
                for (w in p.words) {
                    add(w.id)
                }
            }
        }

        val merged = mergeWordLearningStats(stats)
        val rebuiltStats = ArrayList<ReportWordStat>()
        for ((wordId, prog) in merged) {
            if (!knownWordIds.contains(wordId)) {
                continue
            }
            rebuiltStats.add(replayReportWordStat(prog, nowMs))
        }
        val statByWordId = rebuiltStats.associateBy { it.wordId }

        val startOfDay = localStartOfDayMillis(nowMs)

        var totalSeen = 0
        var totalCorrect = 0
        var learningCount = 0
        var familiarCount = 0
        var masteredCount = 0
        var reviewDue = 0
        var reviewDoneToday = 0
        var newFromStats = 0

        for (stat in rebuiltStats) {
            if (!knownWordIds.contains(stat.wordId)) {
                continue
            }
            totalSeen += stat.seenCount
            totalCorrect += stat.correctCount
            val state = scheduler.classify(stat, nowMs)
            when (state) {
                ReportMemoryState.NEW -> newFromStats += 1
                ReportMemoryState.MASTERED -> masteredCount += 1
                ReportMemoryState.FAMILIAR -> familiarCount += 1
                ReportMemoryState.REVIEW -> {
                    reviewDue += 1
                    learningCount += 1
                }
                ReportMemoryState.LEARNING -> learningCount += 1
            }
            val isReviewable =
                stat.seenCount > 0 && stat.lastAnsweredMs < startOfDay
            if (isReviewable && stat.lastAnsweredMs >= 0L && state != ReportMemoryState.NEW) {
                if (state != ReportMemoryState.REVIEW) {
                    reviewDue += 1
                }
            }
            val doneToday =
                stat.lastAnsweredMs >= startOfDay && stat.consecutiveCorrect > 0
            if (doneToday) {
                reviewDoneToday += 1
            }
        }

        var unseenInLibrary = 0
        for (id in knownWordIds) {
            if (!statByWordId.containsKey(id)) {
                unseenInLibrary += 1
            }
        }

        val accuracyPct = if (totalSeen > 0) {
            ((totalCorrect * 100.0) / totalSeen).toInt()
        } else {
            0
        }

        val newCount = newFromStats + unseenInLibrary
        val denom = maxOf(reviewDue, reviewDoneToday)
        val reviewCompletionPct = if (denom > 0) {
            ((reviewDoneToday * 100.0) / denom).toInt()
        } else {
            0
        }

        val activeSet = activeIds.toSet()
        val allRows = ArrayList<PackReport>()
        for (pack in allPacks) {
            val isActive = activeSet.contains(pack.id)
            var rowSeen = 0
            var rowCorrect = 0
            for (w in pack.words) {
                val st = statByWordId[w.id]
                if (st != null) {
                    rowSeen += st.seenCount
                    rowCorrect += st.correctCount
                }
            }
            if (isActive || rowSeen > 0) {
                val acc = if (rowSeen > 0) {
                    ((rowCorrect * 100.0) / rowSeen).toInt()
                } else {
                    0
                }
                allRows.add(
                    PackReport(
                        packId = pack.id,
                        name = pack.nameZh,
                        active = isActive,
                        totalSeen = rowSeen,
                        totalCorrect = rowCorrect,
                        accuracyPct = acc,
                    ),
                )
            }
        }

        val orderedActive = ArrayList<PackReport>()
        for (id in activeIds) {
            val row = allRows.firstOrNull { it.active && it.packId == id }
            if (row != null) {
                orderedActive.add(row)
            }
        }
        val inactiveRows = allRows.filterNot { it.active }.toMutableList()
        for (i in 0 until inactiveRows.size) {
            var minIdx = i
            for (j in i + 1 until inactiveRows.size) {
                val aj = inactiveRows[j].accuracyPct
                val ami = inactiveRows[minIdx].accuracyPct
                if (aj < ami || (aj == ami && inactiveRows[j].packId < inactiveRows[minIdx].packId)) {
                    minIdx = j
                }
            }
            if (minIdx != i) {
                val tmp = inactiveRows[i]
                inactiveRows[i] = inactiveRows[minIdx]
                inactiveRows[minIdx] = tmp
            }
        }

        val packsOut = ArrayList<PackReport>()
        packsOut.addAll(orderedActive)
        packsOut.addAll(inactiveRows)

        return LearningReport(
            accuracyPct = accuracyPct,
            totalSeen = totalSeen,
            totalCorrect = totalCorrect,
            masteredCount = masteredCount,
            familiarCount = familiarCount,
            learningCount = learningCount,
            newCount = newCount,
            reviewDoneTodayCount = reviewDoneToday,
            reviewDueCount = reviewDue,
            reviewCompletionPct = reviewCompletionPct,
            packs = packsOut,
        )
    }
}
