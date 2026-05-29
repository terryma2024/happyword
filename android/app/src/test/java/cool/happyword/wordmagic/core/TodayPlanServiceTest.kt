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

    @Test
    fun buildUiUsesSelectedFamilyPackWhenActiveListAlsoContainsBuiltin() {
        val familyPack = BuiltinPacks.all.first().copy(
            id = "family-snacks",
            nameEn = "Family Snacks",
            nameZh = "家庭零食",
            source = PackSource.Family,
            version = 1,
            words = listOf(
                WordEntry("family-cookie", "cookie", "饼干"),
                WordEntry("family-bread", "bread", "面包"),
            ),
        )
        val library = PackLibrary.merge(BuiltinPacks.all, emptyList(), listOf(familyPack))

        val ui = TodayPlanService().buildUi(
            library = library,
            activeIds = listOf("fruit-forest", "family-snacks"),
            selectedPackId = "family-snacks",
            stats = emptyList(),
            regionDisplayName = "家庭零食",
            nowMs = 100L,
            dailyState = DailyLearningState(
                dayKey = "19700101",
                packBattleWon = false,
                reviewAllDone = false,
                reviewSnapshot = DailyReviewSnapshot(
                    dayKey = "19700101",
                    generatedAtMs = 100L,
                    sourceCutoffMs = 100L,
                    wordIds = listOf("fruit-apple", "family-bread"),
                ),
            ),
        )

        assertEquals("家庭零食", ui.regionDisplayName)
        assertEquals(listOf("family-bread"), ui.review.map { it.entry.id })
        assertEquals(listOf("family-cookie"), ui.newWords.map { it.entry.id })
    }
}
