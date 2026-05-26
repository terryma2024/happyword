package cool.happyword.wordmagic.ui.battle

import org.junit.Assert.assertEquals
import org.junit.Test

class LetterTemplateLayoutTest {
    @Test
    fun buildsHarmonyStyleSlotsFromTemplate() {
        val slots = LetterTemplateLayout.slots(
            template = "m_gic wand",
            missingIndex = 1,
            pendingIndex = 7,
        )

        assertEquals(listOf("m", "_", "g", "i", "c", " ", "w", "a", "n", "d"), slots.map { it.glyph })
        assertEquals(listOf(0, 1, 2, 3, 4, 5, 6, 7, 8, 9), slots.map { it.originalIndex })
        assertEquals(listOf(1), slots.filter { it.isMissing }.map { it.originalIndex })
        assertEquals(listOf(7), slots.filter { it.isPending }.map { it.originalIndex })
    }

    @Test
    fun usesCompactMetricBucketsWithoutWideningLongWords() {
        assertEquals(16, LetterTemplateLayout.metricsForGlyphCount(6).width)
        assertEquals(44, LetterTemplateLayout.metricsForGlyphCount(6).height)
        assertEquals(3, LetterTemplateLayout.metricsForGlyphCount(6).gap)
        assertEquals(30, LetterTemplateLayout.metricsForGlyphCount(6).filledFontSize)
        assertEquals(16, LetterTemplateLayout.metricsForGlyphCount(9).width)
        assertEquals(16, LetterTemplateLayout.metricsForGlyphCount(12).width)
        assertEquals(16, LetterTemplateLayout.metricsForGlyphCount(13).width)
        assert(LetterTemplateLayout.metricsForGlyphCount(13).width <= LetterTemplateLayout.metricsForGlyphCount(6).width)
    }
}
