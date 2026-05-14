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
}
