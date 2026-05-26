package cool.happyword.wordmagic.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Test

class MonsterDialogueCatalogTest {
    @Test
    fun defaultCatalogHasOneHundredCompleteBilingualDialogueRows() {
        val catalog = MonsterCatalog.default()

        assertEquals(100, catalog.entries.size)
        catalog.entries.forEachIndexed { index, entry ->
            val row = entry.dialogue
            assertFalse("missing intro EN at ${index + 1}", row.introLine.en.isBlank())
            assertFalse("missing intro ZH at ${index + 1}", row.introLine.zh.isBlank())
            assertFalse("missing defeat EN at ${index + 1}", row.defeatLine.en.isBlank())
            assertFalse("missing defeat ZH at ${index + 1}", row.defeatLine.zh.isBlank())
            assertNotEquals("fallback intro leaked at ${index + 1}", "Face my word challenge!", row.introLine.en)
        }
    }

    @Test
    fun resolverFallsBackSafelyForUnknownOrPartialRows() {
        val fallback = MonsterDialogueCatalog.resolveDialogue(
            index1Based = 999,
            monsterName = "Tiny Test Boss",
        )
        assertEquals("Tiny Test Boss is ready!", fallback.introLine.en)
        assertEquals("Tiny Test Boss准备好啦！", fallback.introLine.zh)
        assertEquals("Tiny Test Boss yields this round.", fallback.defeatLine.en)
        assertEquals("Tiny Test Boss这回让你赢。", fallback.defeatLine.zh)

        val partial = MonsterDialogue(
            introLine = MonsterDialogueLine(en = "Custom hello", zh = ""),
            defeatLine = MonsterDialogueLine(en = "", zh = "我服啦"),
        )
        val resolved = MonsterDialogueCatalog.resolveDialogue(
            index1Based = 1,
            monsterName = "Slime",
            override = partial,
        )

        assertEquals("Custom hello", resolved.introLine.en)
        assertEquals("Slime准备好啦！", resolved.introLine.zh)
        assertEquals("Slime yields this round.", resolved.defeatLine.en)
        assertEquals("我服啦", resolved.defeatLine.zh)
    }
}
