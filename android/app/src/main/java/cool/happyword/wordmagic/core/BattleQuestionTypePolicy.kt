package cool.happyword.wordmagic.core

/** Parity with Harmony `BattleQuestionTypePolicy.ets` / iOS `BattleQuestionTypePolicy.swift`. */
object BattleQuestionTypePolicy {
    const val CHOICE = "choice"
    const val FILL_LETTER = "fill-letter"
    const val FILL_LETTER_MEDIUM = "fill-letter-medium"
    const val SPELL = "spell"
    const val SENTENCE_CLOZE = "sentence-cloze"

    val defaultOrderedTypeIds: List<String> = listOf(CHOICE, FILL_LETTER, FILL_LETTER_MEDIUM, SPELL, SENTENCE_CLOZE)

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
            SENTENCE_CLOZE -> "句子填词"
            else -> "题型"
        }

    fun typeIdToKind(typeId: String): QuestionKind? =
        when (typeId) {
            CHOICE -> QuestionKind.Choice
            FILL_LETTER -> QuestionKind.FillLetter
            FILL_LETTER_MEDIUM -> QuestionKind.FillLetterMedium
            SPELL -> QuestionKind.Spell
            SENTENCE_CLOZE -> QuestionKind.SentenceCloze
            else -> null
        }

    fun kindToTypeId(kind: QuestionKind): String =
        when (kind) {
            QuestionKind.Choice -> CHOICE
            QuestionKind.FillLetter -> FILL_LETTER
            QuestionKind.FillLetterMedium -> FILL_LETTER_MEDIUM
            QuestionKind.Spell -> SPELL
            QuestionKind.SentenceCloze -> SENTENCE_CLOZE
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
            SENTENCE_CLOZE -> wordSupportsSentenceCloze(word)
            else -> false
        }
    }

    fun anyWordSupportsQuestionTypes(words: List<WordEntry>, typeIds: List<String>): Boolean =
        words.any { word -> typeIds.any { typeId -> wordSupportsQuestionType(word, typeId) } }

    fun questionTypeFallbackChain(primaryType: String): List<String> =
        when (primaryType) {
            SPELL -> listOf(SPELL, FILL_LETTER_MEDIUM, FILL_LETTER, CHOICE)
            SENTENCE_CLOZE -> listOf(SENTENCE_CLOZE, FILL_LETTER_MEDIUM, SPELL, FILL_LETTER, CHOICE)
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

data class SentenceClozeTargetSpan(val start: Int, val endExclusive: Int)

fun findSentenceClozeTargetSpan(exampleEn: String, targetWord: String): SentenceClozeTargetSpan? {
    val target = targetWord.trim()
    if (exampleEn.isEmpty() || target.isEmpty()) return null
    for (index in exampleEn.indices) {
        val end = matchTargetAt(exampleEn, target, index)
        if (end >= 0 && hasLetterBoundary(exampleEn, index, end)) {
            return SentenceClozeTargetSpan(index, end)
        }
    }
    return null
}

fun wordSupportsSentenceCloze(word: WordEntry): Boolean {
    val example = word.example ?: return false
    if (example.en.trim().isEmpty() || example.zh.trim().isEmpty()) return false
    return findSentenceClozeTargetSpan(example.en, word.word) != null
}

private fun isAsciiLetter(c: Char): Boolean = c.lowercaseChar() in 'a'..'z'

private fun isWhitespace(c: Char): Boolean = c == ' ' || c == '\t' || c == '\n' || c == '\r'

private fun hasLetterBoundary(raw: String, start: Int, endExclusive: Int): Boolean {
    val before = if (start > 0) raw[start - 1] else null
    val after = if (endExclusive < raw.length) raw[endExclusive] else null
    return before?.let(::isAsciiLetter) != true && after?.let(::isAsciiLetter) != true
}

private fun matchTargetAt(raw: String, target: String, start: Int): Int {
    val lowerRaw = raw.lowercase()
    val lowerTarget = target.lowercase().trim()
    var rawIndex = start
    var targetIndex = 0
    while (targetIndex < lowerTarget.length) {
        val targetChar = lowerTarget[targetIndex]
        if (isWhitespace(targetChar)) {
            var targetSpaceEnd = targetIndex
            while (targetSpaceEnd < lowerTarget.length && isWhitespace(lowerTarget[targetSpaceEnd])) {
                targetSpaceEnd += 1
            }
            if (rawIndex >= lowerRaw.length || !isWhitespace(lowerRaw[rawIndex])) return -1
            while (rawIndex < lowerRaw.length && isWhitespace(lowerRaw[rawIndex])) {
                rawIndex += 1
            }
            targetIndex = targetSpaceEnd
            continue
        }
        if (rawIndex >= lowerRaw.length || lowerRaw[rawIndex] != targetChar) return -1
        rawIndex += 1
        targetIndex += 1
    }
    return rawIndex
}
