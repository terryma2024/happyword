package cool.happyword.wordmagic.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class LearningReportBuilderTest {
    @Test
    fun buildsPackRowsWithActiveFirstAndDedupedTotals() {
        val library = PackLibrary.merge(BuiltinPacks.all, emptyList(), emptyList())
        val recorder = LearningRecorder()
        recorder.recordAnswer("fruit-forest", "fruit-apple", true, 100L)
        recorder.recordAnswer("fruit-forest", "fruit-apple", true, 200L)
        recorder.recordAnswer("school-castle", "school-book", false, 300L)

        val report = LearningReportBuilder().build(
            library = library,
            activeIds = listOf("school-castle", "fruit-forest"),
            stats = recorder.statsSnapshot(),
        )

        assertEquals(2, report.totalSeenWords)
        assertEquals(2, report.totalCorrectAnswers)
        assertEquals("school-castle", report.packRows[0].packId)
        assertEquals("fruit-forest", report.packRows[1].packId)
        assertTrue(report.packRows[0].active)
        assertEquals(0, report.packRows[0].accuracyPercent)
        assertEquals(100, report.packRows[1].accuracyPercent)
    }
}
