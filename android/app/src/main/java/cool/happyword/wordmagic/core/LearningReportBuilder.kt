package cool.happyword.wordmagic.core

data class PackReportRow(
    val packId: String,
    val nameEn: String,
    val nameZh: String,
    val active: Boolean,
    val totalWords: Int,
    val seenWords: Int,
    val correctAnswers: Int,
    val wrongAnswers: Int,
    val accuracyPercent: Int,
)

data class LearningReport(
    val totalWords: Int,
    val totalSeenWords: Int,
    val totalCorrectAnswers: Int,
    val totalWrongAnswers: Int,
    val accuracyPercent: Int,
    val packRows: List<PackReportRow>,
)

class LearningReportBuilder {
    fun build(
        library: PackLibrary,
        activeIds: List<String>,
        stats: List<WordLearningStat>,
    ): LearningReport {
        val statsByPackWord = stats.associateBy { "${it.packId}::${it.wordId}" }
        val activeRows = library.activePacks(activeIds).map { pack -> rowFor(pack, true, statsByPackWord) }
        val inactiveRows = library.inactivePacks(activeIds)
            .map { pack -> rowFor(pack, false, statsByPackWord) }
            .filter { it.seenWords > 0 }
            .sortedWith(compareBy<PackReportRow> { it.accuracyPercent }.thenBy { it.packId })
        val rows = activeRows + inactiveRows
        val uniqueSeen = stats.map { it.wordId }.toSet().size
        val correct = stats.sumOf { it.correctCount }
        val wrong = stats.sumOf { it.wrongCount }
        val attempts = correct + wrong
        return LearningReport(
            totalWords = library.allPacks().flatMap { it.words }.map { it.id }.toSet().size,
            totalSeenWords = uniqueSeen,
            totalCorrectAnswers = correct,
            totalWrongAnswers = wrong,
            accuracyPercent = if (attempts == 0) 0 else (correct * 100) / attempts,
            packRows = rows,
        )
    }

    private fun rowFor(pack: WordPack, active: Boolean, statsByPackWord: Map<String, WordLearningStat>): PackReportRow {
        val packStats = pack.words.mapNotNull { word -> statsByPackWord["${pack.id}::${word.id}"] }
        val correct = packStats.sumOf { it.correctCount }
        val wrong = packStats.sumOf { it.wrongCount }
        val attempts = correct + wrong
        return PackReportRow(
            packId = pack.id,
            nameEn = pack.nameEn,
            nameZh = pack.nameZh,
            active = active,
            totalWords = pack.words.size,
            seenWords = packStats.count { it.seenCount > 0 },
            correctAnswers = correct,
            wrongAnswers = wrong,
            accuracyPercent = if (attempts == 0) 0 else (correct * 100) / attempts,
        )
    }
}
