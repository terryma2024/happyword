package cool.happyword.wordmagic.core

/** Parity with Harmony `BattleQuestionTypePolicy.ets` / iOS `BattleQuestionTypePolicy.swift`. */
object BattleQuestionTypePolicy {
    const val CHOICE = "choice"
    const val FILL_LETTER = "fill-letter"
    const val FILL_LETTER_MEDIUM = "fill-letter-medium"
    const val SPELL = "spell"

    val defaultOrderedTypeIds: List<String> = listOf(CHOICE, FILL_LETTER, FILL_LETTER_MEDIUM, SPELL)

    fun sanitizeEnabledQuestionTypes(raw: List<String>): List<String> {
        val out = mutableListOf<String>()
        for (t in defaultOrderedTypeIds) {
            if (raw.contains(t) && !out.contains(t)) {
                out.add(t)
            }
        }
        return if (out.isEmpty()) defaultOrderedTypeIds else out
    }

    fun displayLabel(typeId: String): String =
        when (typeId) {
            CHOICE -> "中文选词"
            FILL_LETTER -> "单字母填空"
            FILL_LETTER_MEDIUM -> "双字母填空"
            SPELL -> "多字母选择"
            else -> "题型"
        }

    fun typeIdToKind(typeId: String): QuestionKind? =
        when (typeId) {
            CHOICE -> QuestionKind.Choice
            FILL_LETTER -> QuestionKind.FillLetter
            FILL_LETTER_MEDIUM -> QuestionKind.FillLetterMedium
            SPELL -> QuestionKind.Spell
            else -> null
        }

    fun kindToTypeId(kind: QuestionKind): String =
        when (kind) {
            QuestionKind.Choice -> CHOICE
            QuestionKind.FillLetter -> FILL_LETTER
            QuestionKind.FillLetterMedium -> FILL_LETTER_MEDIUM
            QuestionKind.Spell -> SPELL
        }

    private fun alphaLetterCount(word: String): Int =
        word.lowercase().count { it in 'a'..'z' }

    fun wordSupportsQuestionType(word: WordEntry, typeId: String): Boolean {
        val letters = alphaLetterCount(word.word)
        return when (typeId) {
            CHOICE -> word.word.isNotEmpty()
            FILL_LETTER -> letters >= 3
            FILL_LETTER_MEDIUM -> letters >= 4
            SPELL -> letters in 4..9
            else -> false
        }
    }

    fun anyWordSupportsQuestionTypes(words: List<WordEntry>, typeIds: List<String>): Boolean =
        words.any { word -> typeIds.any { typeId -> wordSupportsQuestionType(word, typeId) } }

    fun questionTypeFallbackChain(primaryType: String): List<String> =
        when (primaryType) {
            SPELL -> listOf(SPELL, FILL_LETTER_MEDIUM, FILL_LETTER, CHOICE)
            FILL_LETTER_MEDIUM -> listOf(FILL_LETTER_MEDIUM, FILL_LETTER, CHOICE)
            FILL_LETTER -> listOf(FILL_LETTER, CHOICE)
            else -> listOf(CHOICE)
        }

    fun resolveQuestionTypeForWord(word: WordEntry, primaryType: String): String {
        for (typeId in questionTypeFallbackChain(primaryType)) {
            if (wordSupportsQuestionType(word, typeId)) return typeId
        }
        return CHOICE
    }

    fun resolveQuestionTypeWithinPool(word: WordEntry, primaryType: String, pool: List<String>): String {
        for (typeId in questionTypeFallbackChain(primaryType)) {
            if (pool.contains(typeId) && wordSupportsQuestionType(word, typeId)) return typeId
        }
        for (typeId in pool) {
            if (wordSupportsQuestionType(word, typeId)) return typeId
        }
        return CHOICE
    }
}
