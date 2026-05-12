package cool.happyword.wordmagic.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class GrowthStoresTest {
    @Test
    fun coinAccountCapsDailyBattleRewardsAtTwenty() {
        val account = CoinAccount(balance = 18, earnedByDay = mapOf("2026-05-11" to 18))
        val credited = account.creditBattleReward(stars = 3, dayKey = "2026-05-11")

        assertEquals(20, credited.account.balance)
        assertEquals(2, credited.delta)
    }

    @Test
    fun redeemWishDebitsCoinsAndAddsNewestHistory() {
        val wish = WishItem("toy-1", "贴纸", 5, "star", custom = false)
        val state = WishlistState(defaultWishes = listOf(wish), customWishes = emptyList())
        val result = RedemptionHistoryStore().redeem(
            account = CoinAccount(balance = 8),
            wishlist = state,
            wishId = "toy-1",
            redeemedAtMs = 100L,
            parentApproved = true,
        )

        assertTrue(result.accepted)
        assertEquals(3, result.account.balance)
        assertEquals("贴纸", result.history.records.first().title)
    }

    @Test
    fun redeemWithoutParentApprovalDoesNotMutateCoinsOrHistory() {
        val wish = WishItem("toy-1", "贴纸", 5, "star", custom = false)
        val result = RedemptionHistoryStore().redeem(
            account = CoinAccount(balance = 8),
            wishlist = WishlistState(defaultWishes = listOf(wish), customWishes = emptyList()),
            wishId = "toy-1",
            redeemedAtMs = 100L,
            parentApproved = false,
        )

        assertFalse(result.accepted)
        assertEquals(8, result.account.balance)
        assertEquals(0, result.history.records.size)
        assertEquals("需要家长确认", result.message)
    }

    @Test
    fun monsterCatalogCyclesThroughCopiedRuntimeAssets() {
        val catalog = MonsterCatalog.default()

        assertEquals(100, catalog.entries.size)
        assertEquals("Slime", catalog.current().nameEn)
        assertEquals("Zombie", catalog.next().current().nameEn)
        assertEquals("Music Box Fairy", catalog.previous().current().nameEn)
        assertEquals("character_music_box_fairy", catalog.previous().current().rawResourceName)
    }
}
