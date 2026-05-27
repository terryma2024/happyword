package cool.happyword.wordmagic.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDateTime
import java.time.ZoneId

class DailyLearningStateServiceTest {
    private val service = DailyLearningStateService()

    @Test
    fun formatsCompactLocalDayKey() {
        val ms = LocalDateTime.of(2026, 5, 26, 12, 30)
            .atZone(ZoneId.systemDefault())
            .toInstant()
            .toEpochMilli()

        assertEquals("20260526", DailyLearningStateService.localDayKey(ms))
    }

    @Test
    fun snapshotIsStableForTheSameDayAndExcludesSameDayWrongAnswers() {
        val now = LocalDateTime.of(2026, 5, 26, 9, 0)
            .atZone(ZoneId.systemDefault())
            .toInstant()
            .toEpochMilli()
        val start = DailyLearningStateService.localStartOfDayMs(now)
        val activeWords = listOf(
            WordEntry("due", "due", "到期"),
            WordEntry("same-day", "same day", "当天"),
        )
        val stats = listOf(
            WordLearningStat(
                packId = "p",
                wordId = "due",
                seenCount = 2,
                correctCount = 1,
                wrongCount = 1,
                lastSeenAtMs = start - 2_000L,
                nextReviewMs = start - 1_000L,
                memoryState = WordMemoryState.Review,
                lastOutcome = WordAnswerOutcome.Wrong,
            ),
            WordLearningStat(
                packId = "p",
                wordId = "same-day",
                seenCount = 1,
                correctCount = 0,
                wrongCount = 1,
                lastSeenAtMs = start + 1_000L,
                lastOutcome = WordAnswerOutcome.Wrong,
            ),
        )

        val first = service.ensureDailyReviewSnapshot(
            current = DailyLearningState.empty("20260525"),
            nowMs = now,
            activeWords = activeWords,
            selectedPackWordIds = setOf("same-day"),
            stats = stats,
        )
        val second = service.ensureDailyReviewSnapshot(
            current = first,
            nowMs = now + 1_000L,
            activeWords = activeWords,
            selectedPackWordIds = setOf("same-day"),
            stats = stats,
        )

        assertEquals(listOf("due"), first.reviewSnapshot.wordIds)
        assertEquals(first.reviewSnapshot.wordIds, second.reviewSnapshot.wordIds)
        assertEquals(start, first.reviewSnapshot.sourceCutoffMs)
        assertTrue(first.reviewSnapshot.reasonsByWordId.getValue("due").contains(ReviewReason.DueReview))
    }

    @Test
    fun reviewSnapshotIsCappedAtFiftyAndSortedByScoreThenLastAnswerThenId() {
        val now = LocalDateTime.of(2026, 5, 26, 9, 0)
            .atZone(ZoneId.systemDefault())
            .toInstant()
            .toEpochMilli()
        val start = DailyLearningStateService.localStartOfDayMs(now)
        val activeWords = (1..80).map { index ->
            WordEntry("word-${index.toString().padStart(2, '0')}", "word$index", "词$index")
        }
        val stats = activeWords.mapIndexed { index, word ->
            WordLearningStat(
                packId = "p",
                wordId = word.id,
                seenCount = 3,
                correctCount = 1,
                wrongCount = 2,
                lastSeenAtMs = start - index.toLong() - 1L,
                memoryState = WordMemoryState.Learning,
                lastOutcome = WordAnswerOutcome.Wrong,
            )
        }

        val state = service.ensureDailyReviewSnapshot(
            current = DailyLearningState.empty(""),
            nowMs = now,
            activeWords = activeWords,
            selectedPackWordIds = emptySet(),
            stats = stats,
        )

        assertEquals(50, state.reviewSnapshot.wordIds.size)
        assertEquals("word-01", state.reviewSnapshot.wordIds.first())
        assertEquals("word-50", state.reviewSnapshot.wordIds.last())
    }

    @Test
    fun statusMatrixUsesPackWinAndReviewCompletionSeparately() {
        val withTwoReviewWords = DailyLearningState(
            dayKey = "20260526",
            packBattleWon = false,
            reviewAllDone = false,
            reviewSnapshot = DailyReviewSnapshot(
                dayKey = "20260526",
                generatedAtMs = 1L,
                sourceCutoffMs = 0L,
                wordIds = listOf("a", "b"),
                reviewedWordIds = emptyList(),
            ),
        )

        assertEquals("请选择一个场景加战斗", service.homeStatus(withTwoReviewWords).label)
        assertFalse(service.homeStatus(withTwoReviewWords).showReviewCountBadge)
        assertTrue(service.markPackBattleWon(withTwoReviewWords).dailyCheckInCompleted)
        assertFalse(service.markPackBattleWon(withTwoReviewWords).todayAdventureCompleted)

        val afterPackWin = service.markPackBattleWon(withTwoReviewWords)
        assertEquals("请点击复习加战斗(2)", service.homeStatus(afterPackWin).label)
        assertTrue(service.homeStatus(afterPackWin).showReviewCountBadge)

        val allReviewed = service.markReviewedWords(afterPackWin, listOf("a", "b"))
        assertEquals("已完成", service.homeStatus(allReviewed).label)
        assertTrue(allReviewed.reviewAllDone)
        assertTrue(allReviewed.todayAdventureCompleted)
    }

    @Test
    fun reviewMonsterCountUsesRemainingWordsAndCurrentMonsterHp() {
        assertEquals(3, DailyLearningStateService.reviewMonsterCount(requiredWordCount = 20, monsterHp = 5, configuredMonstersTotal = 10))
        assertEquals(1, DailyLearningStateService.reviewMonsterCount(requiredWordCount = 1, monsterHp = 5, configuredMonstersTotal = 10))
        assertEquals(10, DailyLearningStateService.reviewMonsterCount(requiredWordCount = 50, monsterHp = 1, configuredMonstersTotal = 10))
        assertEquals(1, DailyLearningStateService.reviewMonsterCount(requiredWordCount = 0, monsterHp = 5, configuredMonstersTotal = 10))
    }
}
