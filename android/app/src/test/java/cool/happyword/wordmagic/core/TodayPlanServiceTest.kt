package cool.happyword.wordmagic.core

import org.junit.Assert.assertEquals
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
        assertEquals(listOf("fruit-pear", "fruit-orange", "fruit-grape"), plan.newWords.map { it.id })
    }
}
