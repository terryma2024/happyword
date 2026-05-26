package cool.happyword.wordmagic.ui.battle

internal data class LetterTemplateSlot(
    val glyph: String,
    val originalIndex: Int,
    val isMissing: Boolean,
    val isPending: Boolean,
)

internal data class LetterTemplateMetrics(
    val width: Int,
    val height: Int,
    val gap: Int,
    val filledFontSize: Int,
    val placeholderFontSize: Int,
)

internal object LetterTemplateLayout {
    fun slots(template: String, missingIndex: Int, pendingIndex: Int = -1): List<LetterTemplateSlot> {
        val output = mutableListOf<LetterTemplateSlot>()
        var index = 0
        while (index < template.length) {
            val char = template[index]
            if (char != ' ') {
                output += LetterTemplateSlot(
                    glyph = char.toString(),
                    originalIndex = index,
                    isMissing = index == missingIndex,
                    isPending = index == pendingIndex,
                )
                index += 1
                continue
            }

            var run = 0
            while (index + run < template.length && template[index + run] == ' ') {
                run += 1
            }
            output += LetterTemplateSlot(
                glyph = " ",
                originalIndex = index,
                isMissing = index == missingIndex,
                isPending = index == pendingIndex,
            )
            index += run
        }
        return output
    }

    fun metricsForGlyphCount(count: Int): LetterTemplateMetrics {
        return when {
            count <= 6 -> LetterTemplateMetrics(width = 16, height = 44, gap = 3, filledFontSize = 30, placeholderFontSize = 26)
            count <= 9 -> LetterTemplateMetrics(width = 16, height = 40, gap = 2, filledFontSize = 25, placeholderFontSize = 22)
            count <= 12 -> LetterTemplateMetrics(width = 16, height = 36, gap = 2, filledFontSize = 22, placeholderFontSize = 20)
            else -> LetterTemplateMetrics(width = 16, height = 32, gap = 2, filledFontSize = 19, placeholderFontSize = 17)
        }
    }
}
