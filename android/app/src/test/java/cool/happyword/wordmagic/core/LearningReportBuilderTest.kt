package cool.happyword.wordmagic.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class LearningReportBuilderTest {
    @Test
    fun buildsPackRowsWithActiveFirstAndHarmonyStyleTotals() {
        val library = PackLibrary.merge(BuiltinPacks.all, emptyList(), emptyList())
        val recorder = LearningRecorder()
        recorder.recordAnswer("fruit-forest", "fruit-apple", true, 100L)
        recorder.recordAnswer("fruit-forest", "fruit-apple", true, 200L)
        recorder.recordAnswer("school-castle", "school-book", false, 300L)

        val report = LearningReportBuilder().build(
            library = library,
            activeIds = listOf("school-castle", "fruit-forest"),
            stats = recorder.statsSnapshot(),
            nowMs = 400L,
        )

        assertEquals(3, report.totalSeen)
        assertEquals(2, report.totalCorrect)
        assertEquals("school-castle", report.packs[0].packId)
        assertEquals("fruit-forest", report.packs[1].packId)
        assertTrue(report.packs[0].active)
        assertEquals(0, report.packs[0].accuracyPct)
        assertEquals(100, report.packs[1].accuracyPct)
    }
}
