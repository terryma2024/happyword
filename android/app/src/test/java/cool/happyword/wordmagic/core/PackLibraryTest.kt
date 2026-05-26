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
        assertEquals(builtin.scene.storyZh, merged.scene.storyZh)
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
