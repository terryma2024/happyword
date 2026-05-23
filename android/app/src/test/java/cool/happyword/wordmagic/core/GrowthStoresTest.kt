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
        assertEquals("star", result.history.records.first().iconEmoji)
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
    fun monsterCatalogIncludesExpandedAndroidRuntimeAssets() {
        val catalog = MonsterCatalog.default()

        assertEquals(100, catalog.entries.size)
        assertEquals("Slime", catalog.current().nameEn)
        assertEquals("Zombie", catalog.next().current().nameEn)
        assertEquals("Slime", catalog.previous().current().nameEn)
        assertEquals("Music Box Fairy", catalog.copy(index = 99).current().nameEn)
        assertEquals("character_music_box_fairy", catalog.copy(index = 99).current().rawResourceName)
    }

    @Test
    fun monsterCatalogExposesHarmonyLevelDistribution() {
        val catalog = MonsterCatalog.default()

        assertEquals(MonsterLevel.Beginner, catalog.entries[0].level)
        assertEquals(MonsterLevel.Intermediate, catalog.entries[1].level)
        assertEquals(MonsterLevel.Advanced, catalog.entries[7].level)
        assertEquals(MonsterLevel.Super, catalog.entries[9].level)
        assertEquals("Super", catalog.entries[9].levelLabelZh)

        val counts = catalog.entries.groupingBy { it.level }.eachCount()
        assertEquals(10, counts[MonsterLevel.Beginner])
        assertEquals(60, counts[MonsterLevel.Intermediate])
        assertEquals(20, counts[MonsterLevel.Advanced])
        assertEquals(10, counts[MonsterLevel.Super])
    }

    @Test
    fun tryAddCustomWishRejectsNonNumericCost() {
        val s = WishlistState.default()
        val (next, err) = s.tryAddCustomWish("玩具", "abc", "", 1L)
        assertEquals(s, next)
        assertEquals("魔法币数量必须是数字", err)
    }

    @Test
    fun tryAddCustomWishAppendsCustomWish() {
        val s = WishlistState.default()
        val (next, err) = s.tryAddCustomWish("新玩具", "10", "", 9_999L)
        assertEquals(null, err)
        assertEquals(4, next.allWishes().size)
        val added = next.customWishes.single()
        assertEquals("新玩具", added.title)
        assertEquals(10, added.cost)
        assertEquals("⭐", added.icon)
        assertTrue(added.custom)
        assertTrue(added.id.startsWith("custom-"))
    }

    @Test
    fun removeCustomWishRemovesById() {
        val custom = WishItem("custom-test-1", "临时", 10, "🎈", custom = true)
        val s = WishlistState.default().copy(customWishes = listOf(custom))
        val next = s.removeCustomWish("custom-test-1")
        assertEquals(3, next.allWishes().size)
        assertTrue(next.customWishes.isEmpty())
    }

    @Test
    fun removeCustomWishNoOpForCatalogWishId() {
        val s = WishlistState.default()
        assertEquals(s, s.removeCustomWish("wish-ipad-20min"))
    }

    @Test
    fun removeCustomWishNoOpForUnknownId() {
        val s = WishlistState.default()
        assertEquals(s, s.removeCustomWish("custom-missing"))
    }
}
