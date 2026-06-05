package cool.happyword.wordmagic.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MonsterProgressTest {
    @Test
    fun parseDefaultsToEmptySnapshot() {
        val snapshot = MonsterProgressSnapshot.parse("")

        assertEquals(1, snapshot.version)
        assertEquals(emptyList<MonsterProgressRecord>(), snapshot.records)
    }

    @Test
    fun parseFiltersInvalidRecordsAndNormalizesMilestones() {
        val snapshot = MonsterProgressSnapshot.parse(
            """{
                "version":2,
                "records":[
                    {"catalogIndex":1,"encountered":true,"defeatCount":51,"claimedMilestones":[50,50,25,100]},
                    {"catalogIndex":0,"encountered":true,"defeatCount":9,"claimedMilestones":[50]},
                    {"catalogIndex":2,"encountered":false,"defeatCount":-3,"claimedMilestones":[100]},
                    {"catalogIndex":1,"encountered":false,"defeatCount":99,"claimedMilestones":[100]}
                ]
            }""".trimIndent(),
        )

        assertEquals(2, snapshot.version)
        assertEquals(2, snapshot.records.size)
        assertEquals(
            MonsterProgressRecord(
                catalogIndex = 1,
                encountered = true,
                defeatCount = 51,
                claimedMilestones = listOf(50, 100),
            ),
            snapshot.recordFor(1),
        )
        assertEquals(
            MonsterProgressRecord(catalogIndex = 2, claimedMilestones = listOf(100)),
            snapshot.recordFor(2),
        )
    }

    @Test
    fun encounterRevealsWithoutIncrementingDefeatCount() {
        val snapshot = MonsterProgressSnapshot().recordEncounter(3)

        assertEquals(MonsterProgressRecord(catalogIndex = 3, encountered = true), snapshot.recordFor(3))
    }

    @Test
    fun defeatMarksEncounteredAndIncrementsOnlyThatMonster() {
        val snapshot = MonsterProgressSnapshot()
            .recordDefeat(2)
            .recordDefeat(2)
            .recordDefeat(4)

        assertEquals(2, snapshot.recordFor(2).defeatCount)
        assertTrue(snapshot.recordFor(2).encountered)
        assertEquals(1, snapshot.recordFor(4).defeatCount)
        assertEquals(0, snapshot.recordFor(5).defeatCount)
    }

    @Test
    fun rewardStateShowsDisabledProgressEnabledAndClaimed() {
        assertEquals(
            MonsterRewardState(milestone = 50, amount = 50, label = "50 金币 17/50", enabled = false, claimed = false),
            MonsterRewardState.forMilestone(defeatCount = 17, claimed = false, milestone = 50),
        )
        assertEquals(
            MonsterRewardState(milestone = 50, amount = 50, label = "领 50 金币", enabled = true, claimed = false),
            MonsterRewardState.forMilestone(defeatCount = 50, claimed = false, milestone = 50),
        )
        assertEquals(
            MonsterRewardState(milestone = 100, amount = 100, label = "已领 100 金币", enabled = false, claimed = true),
            MonsterRewardState.forMilestone(defeatCount = 100, claimed = true, milestone = 100),
        )
    }

    @Test
    fun canCatchUpClaimFiftyAndHundredAtOneHundredDefeats() {
        var snapshot = MonsterProgressSnapshot()
        repeat(100) {
            snapshot = snapshot.recordDefeat(1)
        }
        var account = CoinAccount(balance = 0, earnedByDay = mapOf("2026-06-05" to 20))

        val fifty = snapshot.claimReward(1, 50, account)
        snapshot = fifty.snapshot
        account = fifty.account
        val hundred = snapshot.claimReward(1, 100, account)

        assertTrue(fifty.claimed)
        assertTrue(hundred.claimed)
        assertEquals(150, hundred.account.balance)
        assertEquals(20, hundred.account.earnedByDay["2026-06-05"])
        assertEquals(listOf("monster-codex:50:1", "monster-codex:100:1"), hundred.account.transactions.map { it.reason })
        assertEquals(100, hundred.snapshot.recordFor(1).defeatCount)
        assertEquals(listOf(50, 100), hundred.snapshot.recordFor(1).claimedMilestones)
    }

    @Test
    fun claimRewardRejectsDuplicatesAndUnderThreshold() {
        var snapshot = MonsterProgressSnapshot()
        repeat(50) {
            snapshot = snapshot.recordDefeat(1)
        }
        val account = CoinAccount(balance = 0)

        val underThreshold = snapshot.claimReward(1, 100, account)
        val firstClaim = snapshot.claimReward(1, 50, account)
        val duplicate = firstClaim.snapshot.claimReward(1, 50, firstClaim.account)

        assertFalse(underThreshold.claimed)
        assertTrue(firstClaim.claimed)
        assertFalse(duplicate.claimed)
        assertEquals(50, duplicate.account.balance)
    }

    @Test
    fun maskedQuestionMarksPreservesCharacterCount() {
        assertEquals("????", maskedQuestionMarks("软泥小灵"))
        assertEquals("??????", maskedQuestionMarks("「普通怪物」"))
        assertEquals("??????????????", maskedQuestionMarks("Dragon 是住在云朵后面"))
    }

    @Test
    fun firstThreeMonsterDisplayNamesChangeWithoutChangingIdsAssetsOrOrder() {
        val catalog = MonsterCatalog.default()

        assertEquals("slime", catalog.entries[0].id)
        assertEquals("软泥小灵", catalog.entries[0].nameEn)
        assertEquals("character_slime", catalog.entries[0].rawResourceName)
        assertEquals("zombie", catalog.entries[1].id)
        assertEquals("书页僵僵", catalog.entries[1].nameEn)
        assertEquals("character_zombie", catalog.entries[1].rawResourceName)
        assertEquals("dragon", catalog.entries[2].id)
        assertEquals("云眠巨龙", catalog.entries[2].nameEn)
        assertEquals("character_dragon", catalog.entries[2].rawResourceName)
    }
}
