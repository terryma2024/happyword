package cool.happyword.wordmagic.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class LearningRecorderTest {
    @Test
    fun recordsAnswersByPackAndWordAndBuildsSessionSummary() {
        val recorder = LearningRecorder()
        recorder.recordAnswer(
            packId = "fruit-forest",
            wordId = "fruit-apple",
            correct = true,
            answeredAtMs = 100L,
        )
        recorder.recordAnswer(
            packId = "fruit-forest",
            wordId = "fruit-apple",
            correct = false,
            answeredAtMs = 200L,
        )
        recorder.recordSession(
            BattleSessionRecord(
                packId = "fruit-forest",
                won = true,
                stars = 3,
                correctCount = 4,
                wrongCount = 0,
                defeatedMonsters = 5,
                completedAtMs = 300L,
            ),
        )

        val stat = recorder.statsSnapshot().single()
        assertEquals("fruit-forest", stat.packId)
        assertEquals("fruit-apple", stat.wordId)
        assertEquals(2, stat.seenCount)
        assertEquals(1, stat.correctCount)
        assertEquals(200L, stat.lastSeenAtMs)
        assertTrue(recorder.sessionSnapshot().single().perfect)
    }

    @Test
    fun recentWrongIdsAreMostRecentFirstAndLimited() {
        val recorder = LearningRecorder()
        recorder.recordAnswer("fruit-forest", "fruit-apple", correct = false, answeredAtMs = 100L)
        recorder.recordAnswer("fruit-forest", "fruit-banana", correct = false, answeredAtMs = 300L)
        recorder.recordAnswer("fruit-forest", "fruit-pear", correct = true, answeredAtMs = 400L)
        recorder.recordAnswer("school-castle", "school-book", correct = false, answeredAtMs = 200L)

        assertEquals(
            listOf("fruit-banana", "school-book"),
            recorder.recentWrongIds(limit = 2),
        )
    }
}
