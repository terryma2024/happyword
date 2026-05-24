package cool.happyword.wordmagic.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PackModelsTest {
    @Test
    fun builtinCatalogContainsFiveHarmonyAlignedPacks() {
        val packs = BuiltinPacks.all

        assertEquals(
            listOf("fruit-forest", "school-castle", "home-cottage", "animal-safari", "ocean-realm"),
            packs.map { it.id },
        )
        assertEquals(PackSource.Builtin, packs.first().source)
        assertEquals("Fruit Forest", packs.first().nameEn)
        assertEquals("水果森林", packs.first().nameZh)
        assertTrue(packs.first().words.any { it.word == "apple" && it.meaning == "苹果" })
        assertTrue(packs.all { it.scene.monsterPlan.isNotEmpty() })
    }

    @Test
    fun builtinPackSceneColorsMatchHarmonyRegions() {
        val colors = BuiltinPacks.all.associate { it.id to (it.scene.bgPrimary to it.scene.bgAccent) }

        assertEquals("#FFF6E0" to "#FFD49A", colors["fruit-forest"])
        assertEquals("#E8F0FE" to "#AECBFA", colors["school-castle"])
        assertEquals("#FFF1E6" to "#F4B98A", colors["home-cottage"])
        assertEquals("#FFF4D9" to "#E0B973", colors["animal-safari"])
        assertEquals("#E0F4F7" to "#7BB6BF", colors["ocean-realm"])
    }

    @Test
    fun builtinPacksHaveSentenceClozeExamplesForEveryWord() {
        BuiltinPacks.all.forEach { pack ->
            pack.words.forEach { word ->
                assertTrue("${pack.id} ${word.id} missing example", word.example != null)
                assertTrue(
                    "${pack.id} ${word.id} cannot generate sentence cloze",
                    BattleQuestionTypePolicy.wordSupportsQuestionType(word, BattleQuestionTypePolicy.SENTENCE_CLOZE),
                )
            }
        }
    }
}
