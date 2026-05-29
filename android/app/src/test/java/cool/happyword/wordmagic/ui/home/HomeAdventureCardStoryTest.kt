package cool.happyword.wordmagic.ui.home

import cool.happyword.wordmagic.core.PackSource
import cool.happyword.wordmagic.core.SceneMetadata
import cool.happyword.wordmagic.core.WordEntry
import cool.happyword.wordmagic.core.WordPack
import org.junit.Assert.assertEquals
import org.junit.Test

class HomeAdventureCardStoryTest {
    @Test
    fun adventureCardLayoutKeepsBottomBreathingRoomAndMoreStorySpace() {
        assertEquals(28, HomeAdventureCardLayoutStyle.pageBottomPaddingDp)
        assertEquals(24, HomeAdventureCardLayoutStyle.cardBottomPaddingDp)
        assertEquals(16, HomeAdventureCardLayoutStyle.storyTopPaddingDp)
        assertEquals(2, HomeAdventureCardLayoutStyle.storyMaxLines)
        assertEquals(14, HomeAdventureCardLayoutStyle.buttonTopGapMinDp)
    }

    @Test
    fun dailyStatusBadgeUsesHarmonyReferenceNeutralPillStyle() {
        assertEquals(0xFFF2DFC9.toInt(), HomeDailyStatusBadgeStyle.backgroundArgb)
        assertEquals(0xFF8C877F.toInt(), HomeDailyStatusBadgeStyle.textArgb)
        assertEquals(16, HomeDailyStatusBadgeStyle.fontSizeSp)
        assertEquals(22, HomeDailyStatusBadgeStyle.horizontalPaddingDp)
        assertEquals(8, HomeDailyStatusBadgeStyle.verticalPaddingDp)
        assertEquals(22, HomeDailyStatusBadgeStyle.cornerRadiusDp)
    }

    @Test
    fun reviewCountBadgeUsesIosToolbarOverlayStyle() {
        assertEquals(0xFFE63946.toInt(), HomeReviewCountBadgeStyle.backgroundArgb)
        assertEquals(20, HomeReviewCountBadgeStyle.minSizeDp)
        assertEquals(10, HomeReviewCountBadgeStyle.cornerRadiusDp)
        assertEquals(12, HomeReviewCountBadgeStyle.fontSizeSp)
        assertEquals(6, HomeReviewCountBadgeStyle.horizontalPaddingDp)
        assertEquals(8, HomeReviewCountBadgeStyle.topEndOffsetXDp)
        assertEquals(2, HomeReviewCountBadgeStyle.topEndOffsetYDp)
    }

    @Test
    fun storyLinePrefersEnglishSceneStory() {
        val pack = pack(
            storyEn = "A moonlit path opens for the newest word quest.",
            storyZh = "月光小路打开新的单词冒险。",
            words = listOf(
                WordEntry("w1", "moon", "月亮", difficulty = 1),
                WordEntry("w2", "planet", "行星", difficulty = 4),
            ),
        )

        assertEquals(
            "A moonlit path opens for the newest word quest.",
            adventureCardStoryLine(pack),
        )
    }

    @Test
    fun storyLineFallsBackToDifficultySummaryAndOmitsZeroBuckets() {
        val pack = pack(
            storyEn = "",
            storyZh = "不会显示中文故事。",
            words = listOf(
                WordEntry("w1", "cat", "猫", difficulty = 1),
                WordEntry("w2", "rabbit", "兔子", difficulty = 2),
                WordEntry("w3", "castle", "城堡", difficulty = 3),
                WordEntry("w4", "constellation", "星座", difficulty = 5),
            ),
        )

        assertEquals(
            "本词包 4 个单词，其中 2 个低难度，1 个中难度，1 个高难度",
            adventureCardStoryLine(pack),
        )
    }

    @Test
    fun storyLineSummaryDoesNotMentionDifficultyBucketsWithNoWords() {
        val pack = pack(
            storyEn = " ",
            storyZh = "",
            words = listOf(
                WordEntry("w1", "comet", "彗星", difficulty = 4),
                WordEntry("w2", "galaxy", "星系", difficulty = 5),
            ),
        )

        assertEquals(
            "本词包 2 个单词，其中 2 个高难度",
            adventureCardStoryLine(pack),
        )
    }

    private fun pack(storyEn: String, storyZh: String, words: List<WordEntry>): WordPack =
        WordPack(
            id = "test-pack",
            nameEn = "Test Pack",
            nameZh = "测试词包",
            source = PackSource.Family,
            version = 1,
            publishedAtMs = null,
            scene = SceneMetadata(
                bgPrimary = "#FFFFFF",
                bgAccent = "#EEEEEE",
                bossName = "Boss",
                monsterPlan = listOf("slime"),
                bossCandidates = listOf("slime"),
                storyZh = storyZh,
                storyEn = storyEn,
            ),
            words = words,
        )
}
