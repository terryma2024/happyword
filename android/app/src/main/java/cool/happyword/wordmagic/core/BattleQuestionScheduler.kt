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

private data class BattleQuestionStage(
    val kind: String,
    val wordIds: List<String>,
    var cursor: Int = 0,
    val servedIds: MutableSet<String> = linkedSetOf(),
)

class BattleQuestionScheduler(
    rawPlanWordIds: List<String>,
    enabledTypes: List<String>,
    private val rng: () -> Double = { Math.random() },
) {
    private val safeTypes = BattleQuestionTypePolicy.sanitizeEnabledQuestionTypes(enabledTypes)
    private val planWordIds = rawPlanWordIds.filter { it.isNotEmpty() }.distinct()
    private var activeStageIndex = 0
    private val monsterCatalogByBattleIndex = mutableMapOf<Int, Int>()
    private val monsterStageByBattleIndex = mutableMapOf<Int, Int>()
    private var stagesCacheKey = ""
    private var stagesCache: List<BattleQuestionStage> = emptyList()

    fun scheduleMode(): BattleScheduleMode {
        val introPool = intersectKinds(
            listOf(BattleQuestionTypePolicy.CHOICE, BattleQuestionTypePolicy.FILL_LETTER),
            safeTypes,
        )
        val challengePool = intersectKinds(
            listOf(
                BattleQuestionTypePolicy.FILL_LETTER_MEDIUM,
                BattleQuestionTypePolicy.SPELL,
                BattleQuestionTypePolicy.SENTENCE_CLOZE,
            ),
            safeTypes,
        )
        return deriveScheduleMode(safeTypes, introPool, challengePool)
    }

    fun isIntroPassActive(): Boolean =
        currentStageKind().let { it == BattleQuestionTypePolicy.CHOICE || it == BattleQuestionTypePolicy.FILL_LETTER }

    fun activePhasePool(): List<String> =
        currentStageKind().let { kind -> if (kind.isEmpty()) emptyList() else listOf(kind) }

    fun pickNext(lastWordId: String?, canServe: WordKindSupportFn): BattleQuestionPick {
        val stage = currentStage(canServe) ?: return BattleQuestionPick(kind = safeTypes.firstOrNull().orEmpty())
        return BattleQuestionPick(
            kind = stage.kind,
            preferredWordId = pickWordFromStage(stage, lastWordId),
        )
    }

    fun markServed(wordId: String, kind: String, canServe: WordKindSupportFn) {
        val stage = currentStage(canServe) ?: return
        if (stage.kind != kind || wordId.isEmpty() || !stage.wordIds.contains(wordId)) return
        stage.servedIds += wordId
        while (activeStageIndex < stages(canServe).lastIndex && currentStage(canServe)?.isCovered() == true) {
            activeStageIndex += 1
        }
    }

    fun restoreServedQuestions(servedQuestions: List<BattleServedQuestion>, canServe: WordKindSupportFn) {
        val stages = stages(canServe)
        for (served in servedQuestions) {
            if (served.wordId.isEmpty() || served.typeId.isEmpty()) continue
            val stage = stages.firstOrNull { it.kind == served.typeId && it.wordIds.contains(served.wordId) }
                ?: continue
            stage.servedIds += served.wordId
        }
        while (activeStageIndex < stages.lastIndex && currentStage(canServe)?.isCovered() == true) {
            activeStageIndex += 1
        }
    }

    fun catalogIndexForMonster(monsterIndex: Int, canServe: WordKindSupportFn): Int {
        val safeMonsterIndex = monsterIndex.coerceAtLeast(1)
        monsterCatalogByBattleIndex[safeMonsterIndex]?.let { return it }
        val stageIndex = monsterStageByBattleIndex.getOrPut(safeMonsterIndex) {
            activeStageIndex.coerceAtMost(stages(canServe).lastIndex.coerceAtLeast(0))
        }
        val stage = stages(canServe).getOrNull(stageIndex) ?: currentStage(canServe)
        val level = monsterLevelForStageQuestionType(stage?.kind.orEmpty())
        val pool = monsterCatalogIndicesForLevel(level)
        val index = (rng().coerceIn(0.0, 0.999999) * pool.size)
            .toInt()
            .coerceIn(0, pool.lastIndex)
        val catalogIndex = pool[index]
        monsterCatalogByBattleIndex[safeMonsterIndex] = catalogIndex
        return catalogIndex
    }

    private fun currentStage(canServe: WordKindSupportFn): BattleQuestionStage? =
        stages(canServe).getOrNull(activeStageIndex.coerceAtMost(stages(canServe).lastIndex.coerceAtLeast(0)))

    private fun currentStageKind(): String = stagesCache.getOrNull(activeStageIndex)?.kind.orEmpty()

    private fun stages(canServe: WordKindSupportFn): List<BattleQuestionStage> {
        val key = safeTypes.joinToString("|") + "::" + planWordIds.joinToString("|")
        if (stagesCacheKey == key && stagesCache.isNotEmpty()) return stagesCache
        stagesCacheKey = key
        stagesCache = safeTypes.mapNotNull { kind ->
            val supported = planWordIds.filter { wordId -> canServe(wordId, kind) }
            if (supported.isEmpty()) null else BattleQuestionStage(kind = kind, wordIds = supported)
        }
        activeStageIndex = activeStageIndex.coerceAtMost(stagesCache.lastIndex.coerceAtLeast(0))
        return stagesCache
    }

    private fun pickWordFromStage(stage: BattleQuestionStage, lastWordId: String?): String {
        if (!stage.isCovered()) {
            val unserved = stage.wordIds.filterNot { it in stage.servedIds }
            return unserved.firstOrNull { it != lastWordId } ?: unserved.firstOrNull().orEmpty()
        }
        val source = stage.wordIds
        if (source.isEmpty()) return stage.wordIds.firstOrNull().orEmpty()
        repeat(source.size) {
            val wordId = source[stage.cursor % source.size]
            stage.cursor = (stage.cursor + 1) % source.size
            if (source.size > 1 && wordId == lastWordId) return@repeat
            return wordId
        }
        return source.first()
    }
}

private fun BattleQuestionStage.isCovered(): Boolean = servedIds.size >= wordIds.size

fun monsterLevelForStageQuestionType(kind: String): MonsterLevel =
    when (kind) {
        BattleQuestionTypePolicy.FILL_LETTER -> MonsterLevel.Intermediate
        BattleQuestionTypePolicy.FILL_LETTER_MEDIUM -> MonsterLevel.Advanced
        BattleQuestionTypePolicy.SPELL,
        BattleQuestionTypePolicy.SENTENCE_CLOZE,
        -> MonsterLevel.Super
        else -> MonsterLevel.Beginner
    }

fun monsterCatalogIndicesForLevel(level: MonsterLevel): List<Int> {
    val catalogSize = MonsterCatalog.default().entries.size
    val indices = (1..catalogSize).filter { MonsterLevel.forCatalogIndex(it) == level }
    return indices.ifEmpty { listOf(1) }
}
