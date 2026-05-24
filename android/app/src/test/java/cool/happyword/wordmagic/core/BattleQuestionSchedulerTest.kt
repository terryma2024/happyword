package cool.happyword.wordmagic.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class BattleQuestionSchedulerTest {
    @Test
    fun singleTypeAlwaysReturnsThatKind() {
        val scheduler = BattleQuestionScheduler(
            rawPlanWordIds = listOf("w-a", "w-b"),
            enabledTypes = listOf(BattleQuestionTypePolicy.SPELL),
            rng = { 0.0 },
        )
        assertEquals(BattleScheduleMode.SingleType, scheduler.scheduleMode())
        repeat(6) {
            assertEquals(BattleQuestionTypePolicy.SPELL, scheduler.pickNext(null) { _, _ -> true }.kind)
        }
    }

    @Test
    fun introOnlyNeverReturnsChallengeKind() {
        val scheduler = BattleQuestionScheduler(
            rawPlanWordIds = listOf("w-a", "w-b", "w-c"),
            enabledTypes = listOf(BattleQuestionTypePolicy.CHOICE, BattleQuestionTypePolicy.FILL_LETTER),
            rng = { 0.25 },
        )
        assertEquals(BattleScheduleMode.IntroOnly, scheduler.scheduleMode())
        val canServe: WordKindSupportFn = { _, _ -> true }
        repeat(12) { index ->
            val kind = scheduler.pickNext(null, canServe).kind
            assertFalse(
                kind == BattleQuestionTypePolicy.FILL_LETTER_MEDIUM ||
                    kind == BattleQuestionTypePolicy.SPELL ||
                    kind == BattleQuestionTypePolicy.SENTENCE_CLOZE,
            )
            scheduler.markServed("w-${index % 3}", kind, canServe)
        }
    }

    @Test
    fun challengeRollsAcrossAllEnabledChallengeTypes() {
        val seen = mutableSetOf<String>()
        for (seed in 0 until 80) {
            val scheduler = BattleQuestionScheduler(
                rawPlanWordIds = listOf("w-a"),
                enabledTypes = listOf(
                    BattleQuestionTypePolicy.FILL_LETTER_MEDIUM,
                    BattleQuestionTypePolicy.SPELL,
                    BattleQuestionTypePolicy.SENTENCE_CLOZE,
                ),
                rng = { (seed % 17).toDouble() / 17.0 },
            )
            seen.add(scheduler.pickNext(null) { _, _ -> true }.kind)
        }

        assertTrue(seen.contains(BattleQuestionTypePolicy.FILL_LETTER_MEDIUM))
        assertTrue(seen.contains(BattleQuestionTypePolicy.SPELL))
        assertTrue(seen.contains(BattleQuestionTypePolicy.SENTENCE_CLOZE))
    }

    @Test
    fun challengeRollsNeverReturnSentenceClozeWhenDisabled() {
        val scheduler = BattleQuestionScheduler(
            rawPlanWordIds = listOf("w-a"),
            enabledTypes = listOf(BattleQuestionTypePolicy.FILL_LETTER_MEDIUM, BattleQuestionTypePolicy.SPELL),
            rng = { 0.99 },
        )

        repeat(10) {
            assertFalse(scheduler.pickNext(null) { _, _ -> true }.kind == BattleQuestionTypePolicy.SENTENCE_CLOZE)
        }
    }

    @Test
    fun spellWrongTapPenaltyAtOneHpEndsBattle() {
        val engine = BattleEngine(config = GameConfig(playerHp = 1))
        val initial = engine.initialState()
        val (_, next) = engine.applySpellLetterPenalty(initial)
        assertEquals(0, next.playerHp)
        assertEquals(BattleStatus.Lost, next.status)
    }
}
