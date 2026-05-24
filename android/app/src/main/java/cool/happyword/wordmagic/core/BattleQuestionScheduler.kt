package cool.happyword.wordmagic.core

enum class BattleScheduleMode {
    SingleType,
    IntroOnly,
    ChallengeOnly,
    TwoPhase,
}

data class BattleQuestionPick(
    val kind: String = "",
    val preferredWordId: String = "",
)

typealias WordKindSupportFn = (wordId: String, kind: String) -> Boolean

private val INTRO_KINDS = listOf(
    BattleQuestionTypePolicy.CHOICE,
    BattleQuestionTypePolicy.FILL_LETTER,
)
private val CHALLENGE_KINDS = listOf(
    BattleQuestionTypePolicy.FILL_LETTER_MEDIUM,
    BattleQuestionTypePolicy.SPELL,
    BattleQuestionTypePolicy.SENTENCE_CLOZE,
)

fun intersectKinds(pool: List<String>, enabled: List<String>): List<String> =
    pool.filter { enabled.contains(it) }

fun deriveScheduleMode(
    enabledTypes: List<String>,
    introPool: List<String>,
    challengePool: List<String>,
): BattleScheduleMode {
    val safe = BattleQuestionTypePolicy.sanitizeEnabledQuestionTypes(enabledTypes)
    if (safe.size == 1) return BattleScheduleMode.SingleType
    if (introPool.isEmpty()) return BattleScheduleMode.ChallengeOnly
    if (challengePool.isEmpty()) return BattleScheduleMode.IntroOnly
    return BattleScheduleMode.TwoPhase
}

class BattleQuestionScheduler(
    rawPlanWordIds: List<String>,
    enabledTypes: List<String>,
    private val rng: () -> Double = { Math.random() },
) {
    private val mode: BattleScheduleMode
    private val effectiveIntroPool: List<String>
    private val effectiveChallengePool: List<String>
    private val singleType: String
    private val planWordIds: List<String>
    private val shuffledWordIds: List<String>
    private var wordCursor = 0
    private val servedChoice = mutableListOf<String>()
    private val servedFillLetter = mutableListOf<String>()
    private var introPassComplete = false
    private var lastIntroKind = ""

    init {
        val safe = BattleQuestionTypePolicy.sanitizeEnabledQuestionTypes(enabledTypes)
        effectiveIntroPool = intersectKinds(INTRO_KINDS, safe)
        effectiveChallengePool = intersectKinds(CHALLENGE_KINDS, safe)
        mode = deriveScheduleMode(safe, effectiveIntroPool, effectiveChallengePool)
        singleType = if (safe.size == 1) safe[0] else ""
        planWordIds = rawPlanWordIds.filter { it.isNotEmpty() }.distinct()
        shuffledWordIds = shuffleIds(planWordIds)
    }

    fun scheduleMode(): BattleScheduleMode = mode

    fun isIntroPassActive(): Boolean =
        when (mode) {
            BattleScheduleMode.ChallengeOnly, BattleScheduleMode.SingleType -> false
            BattleScheduleMode.TwoPhase -> !introPassComplete
            BattleScheduleMode.IntroOnly -> !introPassComplete
        }

    fun activePhasePool(): List<String> =
        when (mode) {
            BattleScheduleMode.SingleType -> listOf(singleType)
            BattleScheduleMode.ChallengeOnly -> effectiveChallengePool
            BattleScheduleMode.IntroOnly, BattleScheduleMode.TwoPhase ->
                if (isIntroPassActive() || mode == BattleScheduleMode.IntroOnly) {
                    effectiveIntroPool
                } else {
                    effectiveChallengePool
                }
        }

    fun markServed(wordId: String, kind: String, canServe: WordKindSupportFn) {
        if (kind == BattleQuestionTypePolicy.CHOICE && !servedChoice.contains(wordId)) {
            servedChoice.add(wordId)
        }
        if (kind == BattleQuestionTypePolicy.FILL_LETTER && !servedFillLetter.contains(wordId)) {
            servedFillLetter.add(wordId)
        }
        if ((mode == BattleScheduleMode.TwoPhase || mode == BattleScheduleMode.IntroOnly) && !introPassComplete) {
            if (checkIntroPassComplete(canServe)) {
                introPassComplete = true
            }
        }
    }

    fun pickNext(lastWordId: String?, canServe: WordKindSupportFn): BattleQuestionPick =
        when (mode) {
            BattleScheduleMode.SingleType -> BattleQuestionPick(kind = singleType)
            BattleScheduleMode.ChallengeOnly -> BattleQuestionPick(kind = rollChallengeKind())
            BattleScheduleMode.TwoPhase ->
                if (introPassComplete) {
                    BattleQuestionPick(kind = rollChallengeKind())
                } else {
                    pickIntroPass(lastWordId, canServe)
                }
            BattleScheduleMode.IntroOnly ->
                if (introPassComplete) {
                    pickIntroSustain(lastWordId, canServe)
                } else {
                    pickIntroPass(lastWordId, canServe)
                }
        }

    private fun rollChallengeKind(): String {
        if (effectiveChallengePool.size == 1) return effectiveChallengePool[0]
        if (effectiveChallengePool.size >= 2) {
            val index = (rng().coerceIn(0.0, 0.999999) * effectiveChallengePool.size)
                .toInt()
                .coerceIn(0, effectiveChallengePool.lastIndex)
            return effectiveChallengePool[index]
        }
        return BattleQuestionTypePolicy.CHOICE
    }

    private fun pickIntroPass(lastWordId: String?, canServe: WordKindSupportFn): BattleQuestionPick {
        val pick = scanIntroWords(lastWordId, canServe, requireUnserved = true)
        if (pick.kind.isNotEmpty()) {
            lastIntroKind = pick.kind
            return pick
        }
        introPassComplete = true
        return BattleQuestionPick(kind = rollChallengeKind())
    }

    private fun pickIntroSustain(lastWordId: String?, canServe: WordKindSupportFn): BattleQuestionPick {
        val pick = scanIntroWords(lastWordId, canServe, requireUnserved = false)
        if (pick.kind.isNotEmpty()) {
            lastIntroKind = pick.kind
            return pick
        }
        return BattleQuestionPick(kind = effectiveIntroPool.firstOrNull() ?: BattleQuestionTypePolicy.CHOICE)
    }

    private fun scanIntroWords(
        lastWordId: String?,
        canServe: WordKindSupportFn,
        requireUnserved: Boolean,
    ): BattleQuestionPick {
        val order = if (shuffledWordIds.isNotEmpty()) shuffledWordIds else planWordIds
        val attempts = if (order.isEmpty()) 1 else order.size
        for (attempt in 0 until attempts) {
            val wordId = if (order.isEmpty()) "" else order[(wordCursor + attempt) % order.size]
            if (wordId.isEmpty()) continue
            if (lastWordId != null && wordId == lastWordId && order.size > 1) continue
            val kinds = availableIntroKindsForWord(wordId, canServe, requireUnserved)
            if (kinds.isEmpty()) continue
            wordCursor = if (order.isEmpty()) 0 else (wordCursor + attempt + 1) % order.size
            return BattleQuestionPick(
                kind = pickAlternatingIntroKind(kinds),
                preferredWordId = wordId,
            )
        }
        return BattleQuestionPick()
    }

    private fun availableIntroKindsForWord(
        wordId: String,
        canServe: WordKindSupportFn,
        requireUnserved: Boolean,
    ): List<String> {
        val kinds = mutableListOf<String>()
        for (kind in effectiveIntroPool) {
            if (!canServe(wordId, kind)) continue
            if (requireUnserved && isServed(wordId, kind)) continue
            if (!requireUnserved && isServed(wordId, kind)) continue
            kinds.add(kind)
        }
        if (!requireUnserved && kinds.isEmpty()) {
            for (kind in effectiveIntroPool) {
                if (canServe(wordId, kind)) kinds.add(kind)
            }
        }
        return kinds
    }

    private fun pickAlternatingIntroKind(kinds: List<String>): String {
        if (kinds.size == 1) return kinds[0]
        if (lastIntroKind == BattleQuestionTypePolicy.CHOICE &&
            kinds.contains(BattleQuestionTypePolicy.FILL_LETTER)
        ) {
            return BattleQuestionTypePolicy.FILL_LETTER
        }
        if (lastIntroKind == BattleQuestionTypePolicy.FILL_LETTER &&
            kinds.contains(BattleQuestionTypePolicy.CHOICE)
        ) {
            return BattleQuestionTypePolicy.CHOICE
        }
        return kinds[0]
    }

    private fun isServed(wordId: String, kind: String): Boolean =
        when (kind) {
            BattleQuestionTypePolicy.CHOICE -> servedChoice.contains(wordId)
            BattleQuestionTypePolicy.FILL_LETTER -> servedFillLetter.contains(wordId)
            else -> false
        }

    private fun checkIntroPassComplete(canServe: WordKindSupportFn): Boolean {
        if (planWordIds.isEmpty()) return true
        for (wordId in planWordIds) {
            for (kind in effectiveIntroPool) {
                if (canServe(wordId, kind) && !isServed(wordId, kind)) return false
            }
        }
        return true
    }

    private fun shuffleIds(ids: List<String>): List<String> {
        if (ids.size <= 1) return ids
        val out = ids.toMutableList()
        for (index in out.lastIndex downTo 1) {
            val swapIndex = (rng().coerceIn(0.0, 0.999999) * (index + 1)).toInt().coerceIn(0, index)
            val tmp = out[index]
            out[index] = out[swapIndex]
            out[swapIndex] = tmp
        }
        return out
    }
}
