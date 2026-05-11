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
}
