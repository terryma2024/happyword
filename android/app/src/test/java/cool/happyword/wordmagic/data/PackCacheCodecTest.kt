package cool.happyword.wordmagic.data

import cool.happyword.wordmagic.core.PackSource
import cool.happyword.wordmagic.core.SceneMetadata
import cool.happyword.wordmagic.core.WordEntry
import cool.happyword.wordmagic.core.WordPack
import org.junit.Assert.assertEquals
import org.junit.Test

class PackCacheCodecTest {
    @Test
    fun cacheRoundTripPreservesBilingualStoryAndWordDifficulty() {
        val pack = WordPack(
            id = "family-space",
            nameEn = "Family Space",
            nameZh = "家庭太空",
            source = PackSource.Family,
            version = 2,
            publishedAtMs = 3_000L,
            scene = SceneMetadata(
                bgPrimary = "#FFF7E6",
                bgAccent = "#FFD2A6",
                bossName = "Space Boss",
                monsterPlan = listOf("slime"),
                bossCandidates = listOf("slime"),
                storyZh = "星星排成小路，带孩子读出太空单词。",
                storyEn = "Stars make a path for every space word.",
                spellbookCoverUrl = "https://cdn.example/family-space.png",
            ),
            words = listOf(
                WordEntry("space-moon", "moon", "月亮", difficulty = 2),
                WordEntry("space-planet", "planet", "行星", difficulty = 4),
            ),
        )

        val decoded = PackCacheCodec.decode(PackCacheCodec.encode(listOf(pack)), PackSource.Family)

        assertEquals(1, decoded.size)
        assertEquals("Stars make a path for every space word.", decoded.single().scene.storyEn)
        assertEquals("星星排成小路，带孩子读出太空单词。", decoded.single().scene.storyZh)
        assertEquals("https://cdn.example/family-space.png", decoded.single().scene.spellbookCoverUrl)
        assertEquals(listOf(2, 4), decoded.single().words.map { it.difficulty })
    }

    @Test
    fun cacheDecoderKeepsLegacyRowsWithoutEnglishStoryCompatible() {
        val legacy = listOf(
            "global-colors",
            "Color Harbor",
            "颜色港湾",
            "Global",
            "1",
            "2000",
            "旧版中文故事。",
            "color-red,red,红色;color-blue,blue,蓝色",
        ).joinToString("\t")

        val decoded = PackCacheCodec.decode(legacy, PackSource.Global)

        assertEquals(1, decoded.size)
        assertEquals("", decoded.single().scene.storyEn)
        assertEquals("旧版中文故事。", decoded.single().scene.storyZh)
        assertEquals(listOf(1, 1), decoded.single().words.map { it.difficulty })
    }
}
