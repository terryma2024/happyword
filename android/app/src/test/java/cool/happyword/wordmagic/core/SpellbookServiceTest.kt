package cool.happyword.wordmagic.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SpellbookServiceTest {
    @Test
    fun cardStateUsesSeenCountBeforeMemoryState() {
        val word = word("word-1")

        assertEquals(SpellbookCardState.Locked, SpellbookService.cardState(word, null))
        assertEquals(SpellbookCardState.Locked, SpellbookService.cardState(word, stat("pack", word.id, seenCount = 0, memoryState = WordMemoryState.Mastered)))
        assertEquals(SpellbookCardState.Seen, SpellbookService.cardState(word, stat("pack", word.id, seenCount = 1, memoryState = WordMemoryState.Learning)))
        assertEquals(SpellbookCardState.Mastered, SpellbookService.cardState(word, stat("pack", word.id, seenCount = 1, memoryState = WordMemoryState.Mastered)))
    }

    @Test
    fun packProgressRequiresEveryWordMasteredAndRejectsEmptyPacks() {
        val words = listOf(word("one"), word("two"))
        val partial = mapOf(
            "one" to stat("pack", "one", seenCount = 3, memoryState = WordMemoryState.Mastered),
            "two" to stat("pack", "two", seenCount = 1, memoryState = WordMemoryState.Familiar),
        )
        val complete = mapOf(
            "one" to stat("pack", "one", seenCount = 3, memoryState = WordMemoryState.Mastered),
            "two" to stat("pack", "two", seenCount = 3, memoryState = WordMemoryState.Mastered),
        )

        assertEquals(1, SpellbookService.progress(words, partial).masteredCount)
        assertFalse(SpellbookService.progress(words, partial).isComplete)
        assertTrue(SpellbookService.progress(words, complete).isComplete)
        assertFalse(SpellbookService.progress(emptyList(), emptyMap()).isComplete)
    }

    @Test
    fun spellbookRewardIsUncappedAndClaimedOncePerPack() {
        val rewards = SpellbookRewardSnapshot()
        val first = rewards.claim("fruit-forest", CoinAccount(balance = 0))
        val second = first.snapshot.claim("fruit-forest", first.account)

        assertTrue(first.claimed)
        assertFalse(second.claimed)
        assertEquals(SpellbookService.REWARD_COINS, first.account.balance)
        assertEquals(SpellbookService.REWARD_COINS, second.account.balance)
        assertTrue(first.snapshot.isClaimed("fruit-forest"))
    }

    @Test
    fun sceneMetadataStoresSpellbookCoverUrl() {
        val scene = SceneMetadata(
            bgPrimary = "",
            bgAccent = "",
            bossName = "",
            monsterPlan = emptyList(),
            bossCandidates = emptyList(),
            storyZh = "",
            spellbookCoverUrl = "https://cdn.example/cover.png",
        )

        assertEquals("https://cdn.example/cover.png", scene.spellbookCoverUrl)
    }

    private fun word(id: String) = WordEntry(id = id, word = id, meaning = "meaning")

    private fun stat(packId: String, wordId: String, seenCount: Int, memoryState: WordMemoryState): WordLearningStat =
        WordLearningStat(
            packId = packId,
            wordId = wordId,
            seenCount = seenCount,
            correctCount = if (memoryState == WordMemoryState.Mastered) seenCount else 0,
            wrongCount = 0,
            lastSeenAtMs = 0L,
            memoryState = memoryState,
        )
}
