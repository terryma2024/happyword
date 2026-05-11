package cool.happyword.wordmagic.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PackSelectionStoreTest {
    @Test
    fun defaultsUseFiveBuiltinIdsAndRejectSixthActivePack() {
        val store = PackSelectionStore.initial(BuiltinPacks.defaultActiveOrder)

        assertEquals(5, store.activePackIds.size)
        assertFalse(store.activate("extra-pack").accepted)
        assertEquals("最多只能同时启用 5 个词包", store.activate("extra-pack").message)
    }

    @Test
    fun deactivatingPinnedPackClearsPin() {
        val store = PackSelectionStore.initial(BuiltinPacks.defaultActiveOrder)
            .togglePin("fruit-forest")
            .selection
            .deactivate("fruit-forest")
            .selection

        assertFalse("fruit-forest" in store.pinnedPackIds)
        assertFalse("fruit-forest" in store.activePackIds)
    }

    @Test
    fun threePerfectRunsRotateUnpinnedPackToBestCandidate() {
        val store = PackSelectionStore.initial(BuiltinPacks.defaultActiveOrder)
        val candidate = WordPack(
            id = "family-space",
            nameEn = "Family Space",
            nameZh = "家庭太空",
            source = PackSource.Family,
            version = 1,
            publishedAtMs = 9_000L,
            scene = BuiltinPacks.all.first().scene,
            words = listOf(WordEntry("space-moon", "moon", "月亮")),
        )
        val library = PackLibrary.merge(BuiltinPacks.all, emptyList(), listOf(candidate))

        val rotated = store
            .recordPerfectRun("fruit-forest", library).selection
            .recordPerfectRun("fruit-forest", library).selection
            .recordPerfectRun("fruit-forest", library).selection

        assertFalse("fruit-forest" in rotated.activePackIds)
        assertTrue("family-space" in rotated.activePackIds)
        assertEquals(5, rotated.activePackIds.size)
    }
}
