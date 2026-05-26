package cool.happyword.wordmagic.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class TodayPlanServiceTest {
    @Test
    fun bucketsActivePackWordsByLocalStats() {
        val library = PackLibrary.merge(BuiltinPacks.all, emptyList(), emptyList())
        val recorder = LearningRecorder()
        recorder.recordAnswer("fruit-forest", "fruit-apple", true, 100L)
        recorder.recordAnswer("fruit-forest", "fruit-banana", false, 200L)

        val plan = TodayPlanService().build(
            library = library,
            activeIds = listOf("fruit-forest"),
            stats = recorder.statsSnapshot(),
        )

        assertEquals(listOf("fruit-banana"), plan.review.map { it.id })
        assertEquals(listOf("fruit-apple"), plan.learning.map { it.id })
        assertEquals(
            listOf(
                "fruit-orange",
                "fruit-grape",
                "fruit-pear",
                "fruit-peach",
                "fruit-lemon",
                "fruit-mango",
                "fruit-melon",
                "fruit-cherry",
                "fruit-strawberry",
                "fruit-pineapple",
                "fruit-watermelon",
                "fruit-kiwi",
                "fruit-blueberry",
            ),
            plan.newWords.map { it.id },
        )
    }

    @Test
    fun buildUiCarriesHeaderAndRowFlags() {
        val library = PackLibrary.merge(BuiltinPacks.all, emptyList(), emptyList())
        val recorder = LearningRecorder()
        val noon = TodayPlanService.startOfDayMillis(System.currentTimeMillis()) + 60_000L
        recorder.recordAnswer("fruit-forest", "fruit-apple", true, noon)

        val ui = TodayPlanService().buildUi(
            library = library,
            activeIds = listOf("fruit-forest"),
            stats = recorder.statsSnapshot(),
            regionDisplayName = "水果森林",
            nowMs = noon,
        )

        assertEquals("水果森林", ui.regionDisplayName)
        assertEquals(TodayPlanService.localDayKey(noon), ui.dayKey)
        assertTrue(ui.learning.any { it.entry.id == "fruit-apple" && it.doneHighlight })
    }
}
