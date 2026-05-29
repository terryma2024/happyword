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
        assertEquals(listOf(15, 15, 15, 15, 15), packs.map { it.words.size })
        assertTrue(packs.first().words.any { it.word == "apple" && it.meaning == "苹果" })
        assertTrue(packs.all { it.scene.monsterPlan.isNotEmpty() })
    }

    @Test
    fun builtinPacksCarryHarmonyAlignedBilingualStories() {
        val stories = BuiltinPacks.all.associate { it.id to (it.scene.storyEn to it.scene.storyZh) }

        assertEquals(
            "Tiny lanterns glow as fruit friends guide each new word." to "果林里的小灯亮起，水果朋友带孩子认识新的单词。",
            stories["fruit-forest"],
        )
        assertEquals(
            "The school castle rings its bell and opens a word quest." to "校园城堡敲响铃声，打开一场单词小冒险。",
            stories["school-castle"],
        )
        assertEquals(
            "A cozy cottage hums softly while home words wake up." to "温暖小屋轻轻哼唱，家里的单词一个个醒来。",
            stories["home-cottage"],
        )
        assertEquals(
            "Friendly animals leave paw prints toward today's word trail." to "友好的动物留下脚印，带孩子走上今天的单词小路。",
            stories["animal-safari"],
        )
        assertEquals(
            "Blue waves sparkle as sea friends whisper new words." to "蓝色海浪闪闪发光，海洋朋友悄悄送来新的单词。",
            stories["ocean-realm"],
        )
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
