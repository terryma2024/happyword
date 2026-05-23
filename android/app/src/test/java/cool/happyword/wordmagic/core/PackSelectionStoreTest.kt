package cool.happyword.wordmagic.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PackSelectionStoreTest {
    @Test
    fun selectionAllowsTenActivePacksAndAutoRotatesUnpinnedOverflow() {
        val ids = listOf("fruit-forest", "home-room", "animal-friends", "color-party", "school-day", "ocean", "space", "music", "art", "sport")
        val store = PackSelectionStore.initial(ids).togglePin("fruit-forest").selection

        assertEquals(10, PackSelectionStore.MAX_ACTIVE)
        assertEquals(ids, store.activePackIds)

        val rotated = store.activate("science").selection

        assertEquals(listOf("fruit-forest", "animal-friends", "color-party", "school-day", "ocean", "space", "music", "art", "sport", "science"), rotated.activePackIds)
        assertEquals(10, rotated.activePackIds.size)
    }

    @Test
    fun selectionRefusesOverflowWhenAllActivePacksArePinned() {
        val ids = listOf("fruit-forest", "home-room", "animal-friends", "color-party", "school-day", "ocean", "space", "music", "art", "sport")
        val store = ids.fold(PackSelectionStore.initial(ids)) { next, id -> next.togglePin(id).selection }

        val result = store.activate("science")

        assertFalse(result.accepted)
        assertEquals("请先取消固定一个词包", result.message)
        assertEquals(ids, result.selection.activePackIds)
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
