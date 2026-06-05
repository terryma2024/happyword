package cool.happyword.wordmagic.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PackLibraryTest {
    @Test
    fun mergePriorityUsesFamilyThenGlobalThenBuiltinAndKeepsBuiltinSceneFallback() {
        val builtin = BuiltinPacks.all.first { it.id == "fruit-forest" }
        val global = builtin.copy(
            nameEn = "Global Fruit",
            source = PackSource.Global,
            version = 2,
            publishedAtMs = 2_000L,
            words = listOf(WordEntry("global-apple", "apple", "苹果")),
        )
        val family = builtin.copy(
            nameEn = "Family Fruit",
            source = PackSource.Family,
            version = 3,
            publishedAtMs = 3_000L,
            scene = SceneMetadata(
                bgPrimary = "#FFFFFF",
                bgAccent = "#FFFFFF",
                bossName = "",
                monsterPlan = emptyList(),
                bossCandidates = emptyList(),
                storyZh = "家庭自己的中文故事。",
                storyEn = "Family words follow a tiny lantern trail.",
            ),
            words = listOf(WordEntry("family-mango", "mango", "芒果")),
        )

        val library = PackLibrary.merge(
            builtin = listOf(builtin),
            global = listOf(global),
            family = listOf(family),
        )

        val merged = library.requirePack("fruit-forest")
        assertEquals("Family Fruit", merged.nameEn)
        assertEquals(PackSource.Family, merged.source)
        assertEquals(builtin.scene.bgPrimary, merged.scene.bgPrimary)
        assertEquals(builtin.scene.bgAccent, merged.scene.bgAccent)
        assertEquals("Family words follow a tiny lantern trail.", merged.scene.storyEn)
        assertEquals("家庭自己的中文故事。", merged.scene.storyZh)
        assertEquals(listOf("mango"), merged.words.map { it.word })
    }

    @Test
    fun missingActiveIdsArePrunedInOrder() {
        val library = PackLibrary.merge(BuiltinPacks.all, emptyList(), emptyList())

        assertEquals(
            listOf("school-castle", "fruit-forest"),
            library.existingIdsInOrder(listOf("missing", "school-castle", "fruit-forest", "missing")),
        )
        assertTrue(library.allPacks().size >= 5)
    }

    @Test
    fun storyAndCoverOnlyGlobalPackReceivesFallbackPaletteAndPreservesMetadata() {
        val global = WordPack(
            id = "gpk-kitchen-bubbles",
            nameEn = "Kitchen Bubbles",
            nameZh = "厨房泡泡",
            source = PackSource.Global,
            version = 1,
            publishedAtMs = 2_000L,
            scene = SceneMetadata(
                bgPrimary = "#FFFFFF",
                bgAccent = "#FFFFFF",
                bossName = "",
                monsterPlan = emptyList(),
                bossCandidates = emptyList(),
                storyZh = "在厨房里，泡泡欢快地跳舞。",
                storyEn = "Tiny bubbles dance through the kitchen words.",
                spellbookCoverUrl = "https://blob.example/covers/kitchen-bubbles.png",
            ),
            words = listOf(
                WordEntry("kitchen-cup", "cup", "杯子"),
                WordEntry("kitchen-spoon", "spoon", "勺子"),
                WordEntry("kitchen-plate", "plate", "盘子"),
            ),
        )

        val library = PackLibrary.merge(BuiltinPacks.all, global = listOf(global), family = emptyList())
        val merged = library.requirePack("gpk-kitchen-bubbles")

        assertTrue(merged.scene.bgPrimary != "#FFFFFF")
        assertTrue(merged.scene.bgAccent != "#FFFFFF")
        assertTrue(merged.scene.bossName.isNotBlank())
        assertTrue(merged.scene.monsterPlan.isNotEmpty())
        assertTrue(merged.scene.bossCandidates.isNotEmpty())
        assertEquals("在厨房里，泡泡欢快地跳舞。", merged.scene.storyZh)
        assertEquals("Tiny bubbles dance through the kitchen words.", merged.scene.storyEn)
        assertEquals("https://blob.example/covers/kitchen-bubbles.png", merged.scene.spellbookCoverUrl)
    }

    @Test
    fun builtinPacksExposeFifteenSentenceReadyWordsEach() {
        val expectedIds = setOf("fruit-forest", "school-castle", "home-cottage", "animal-safari", "ocean-realm")
        assertEquals(expectedIds, BuiltinPacks.all.map { it.id }.toSet())

        BuiltinPacks.all.forEach { pack ->
            assertEquals("word count for ${pack.id}", 15, pack.words.size)
            pack.words.forEach { word ->
                assertTrue("${pack.id}/${word.id} supports sentence cloze", wordSupportsSentenceCloze(word))
            }
        }
    }
}
