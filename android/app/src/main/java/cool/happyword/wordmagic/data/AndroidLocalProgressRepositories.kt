package cool.happyword.wordmagic.data

import android.content.Context
import cool.happyword.wordmagic.core.ActiveBattleSnapshot
import cool.happyword.wordmagic.core.BattleState
import cool.happyword.wordmagic.core.BattleStatus
import cool.happyword.wordmagic.core.BattleServedQuestion
import cool.happyword.wordmagic.core.BuiltinPacks
import cool.happyword.wordmagic.core.CoinAccount
import cool.happyword.wordmagic.core.CheckInSnapshot
import cool.happyword.wordmagic.core.LearningRecorder
import cool.happyword.wordmagic.core.PackSelectionStore
import cool.happyword.wordmagic.core.RedemptionHistoryStore
import cool.happyword.wordmagic.core.RedemptionRecord
import cool.happyword.wordmagic.core.WishItem
import cool.happyword.wordmagic.core.WishlistState
import cool.happyword.wordmagic.core.CustomWishRules
import cool.happyword.wordmagic.core.GameConfig
import cool.happyword.wordmagic.core.DailyLearningState
import cool.happyword.wordmagic.core.DailyReviewSnapshot
import cool.happyword.wordmagic.core.Question
import cool.happyword.wordmagic.core.QuestionKind
import cool.happyword.wordmagic.core.WordLearningStat
import cool.happyword.wordmagic.core.WordAnswerOutcome
import cool.happyword.wordmagic.core.WordMemoryState
import org.json.JSONArray
import org.json.JSONObject

class AndroidLocalProgressRepositories(context: Context) {
    private val prefs = context.getSharedPreferences("wordmagic-local-progress", Context.MODE_PRIVATE)

    fun loadSelection(): PackSelectionStore {
        val ids = prefs.getString("activePackIds", null)
            ?.split(",")
            ?.filter { it.isNotBlank() }
            ?: BuiltinPacks.defaultActiveOrder
        val pins = prefs.getStringSet("pinnedPackIds", emptySet()) ?: emptySet()
        val perfectScores = prefs.getString("perfectScoresByPack", "").orEmpty()
            .lineSequence()
            .mapNotNull { line ->
                val parts = line.split('\t')
                if (parts.size == 2) parts[0] to parts[1].toIntOrNull().orZero() else null
            }
            .toMap()
        return PackSelectionStore.initial(ids).copy(
            pinnedPackIds = pins,
            perfectScoresByPack = perfectScores,
        )
    }

    fun saveSelection(selection: PackSelectionStore) {
        prefs.edit()
            .putString("activePackIds", selection.activePackIds.joinToString(","))
            .putStringSet("pinnedPackIds", selection.pinnedPackIds)
            .putString("perfectScoresByPack", selection.perfectScoresByPack.entries.joinToString("\n") { "${it.key}\t${it.value}" })
            .apply()
    }

    fun loadGameConfig(): GameConfig {
        val defaults = GameConfig()
        return GameConfig(
            playerHp = prefs.getInt("gameConfig.playerMaxHp", defaults.playerHp),
            monsterHp = prefs.getInt("gameConfig.monsterMaxHp", defaults.monsterHp),
            monsterCount = prefs.getInt("gameConfig.monstersTotal", defaults.monsterCount),
            timerSeconds = prefs.getInt("gameConfig.timerSeconds", defaults.timerSeconds),
            autoPronunciation = prefs.getBoolean("gameConfig.autoPronunciation", defaults.autoPronunciation),
            enabledQuestionTypes = prefs.getString("gameConfig.enabledQuestionTypes", null)
                ?.split(",")
                ?.filter { it.isNotBlank() }
                ?: defaults.enabledQuestionTypes,
        )
    }

    fun saveGameConfig(config: GameConfig) {
        prefs.edit()
            .putInt("gameConfig.playerMaxHp", config.playerHp)
            .putInt("gameConfig.monsterMaxHp", config.monsterHp)
            .putInt("gameConfig.monstersTotal", config.monsterCount)
            .putInt("gameConfig.timerSeconds", config.timerSeconds)
            .putBoolean("gameConfig.autoPronunciation", config.autoPronunciation)
            .putString("gameConfig.enabledQuestionTypes", config.enabledQuestionTypes.joinToString(","))
            .apply()
    }

    fun loadCoinAccount(): CoinAccount {
        val earned = prefs.getString("coinEarnedByDay", "").orEmpty()
            .lineSequence()
            .mapNotNull { line ->
                val parts = line.split('\t')
                if (parts.size == 2) parts[0] to parts[1].toIntOrNull().orZero() else null
            }
            .toMap()
        return CoinAccount(balance = prefs.getInt("coinBalance", 10), earnedByDay = earned)
    }

    fun saveCoinAccount(account: CoinAccount) {
        prefs.edit()
            .putInt("coinBalance", account.balance)
            .putString("coinEarnedByDay", account.earnedByDay.entries.joinToString("\n") { "${it.key}\t${it.value}" })
            .apply()
    }

    fun loadCheckIns(): CheckInSnapshot {
        val checked = prefs.getString("checkInCheckedDayKeys", "").orEmpty()
            .lineSequence()
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .toList()
        val bonuses = prefs.getString("checkInWeeklyBonusDayKeys", "").orEmpty()
            .lineSequence()
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .toList()
        return CheckInSnapshot(
            checkedDayKeys = checked,
            weeklyBonusDayKeys = bonuses,
            lastSyncedAtMs = prefs.getString("checkInLastSyncedAtMs", "0").orEmpty().toLongOrNull() ?: 0L,
            pendingSync = prefs.getBoolean("checkInPendingSync", false),
        ).recomputed()
    }

    fun saveCheckIns(snapshot: CheckInSnapshot) {
        prefs.edit()
            .putString("checkInCheckedDayKeys", snapshot.checkedDayKeys.joinToString("\n"))
            .putString("checkInWeeklyBonusDayKeys", snapshot.weeklyBonusDayKeys.joinToString("\n"))
            .putString("checkInLastSyncedAtMs", snapshot.lastSyncedAtMs.coerceAtLeast(0L).toString())
            .putBoolean("checkInPendingSync", snapshot.pendingSync)
            .apply()
    }

    fun loadWishlist(): WishlistState {
        val base = WishlistState.default()
        val raw = prefs.getString("wishlistCustom", null).orEmpty()
        if (raw.isBlank()) {
            return base
        }
        val customs = raw.lineSequence().mapNotNull { line ->
            val parts = line.split('\t')
            if (parts.size < 4) {
                return@mapNotNull null
            }
            val id = parts[0].trim()
            val title = parts[1].trim()
            val cost = parts[2].toIntOrNull() ?: return@mapNotNull null
            val icon = parts[3].trim().ifEmpty { CustomWishRules.DEFAULT_EMOJI }
            if (!id.startsWith(CustomWishRules.ID_PREFIX) || title.isEmpty()) {
                return@mapNotNull null
            }
            WishItem(id = id, title = title, cost = cost, icon = icon, custom = true)
        }.toList()
        return base.copy(customWishes = customs)
    }

    fun saveWishlist(state: WishlistState) {
        val serialized = state.customWishes.joinToString("\n") { w ->
            val safeTitle = w.title.replace(Regex("[\t\n\r]"), " ")
            val safeIcon = w.icon.replace(Regex("[\t\n\r]"), " ")
            "${w.id}\t$safeTitle\t${w.cost}\t$safeIcon"
        }
        prefs.edit().putString("wishlistCustom", serialized).apply()
    }

    fun loadRedemptionHistory(): RedemptionHistoryStore {
        val records = prefs.getString("redemptionHistory", "").orEmpty()
            .lineSequence()
            .mapNotNull { line ->
                val parts = line.split('\t')
                when (parts.size) {
                    7 -> RedemptionRecord(
                        id = parts[0],
                        wishId = parts[1],
                        title = parts[2],
                        cost = parts[3].toIntOrNull().orZero(),
                        redeemedAtMs = parts[4].toLongOrNull() ?: 0L,
                        status = parts[5],
                        iconEmoji = parts[6],
                    )
                    6 -> RedemptionRecord(
                        id = parts[0],
                        wishId = parts[1],
                        title = parts[2],
                        cost = parts[3].toIntOrNull().orZero(),
                        redeemedAtMs = parts[4].toLongOrNull() ?: 0L,
                        status = parts[5],
                        iconEmoji = "",
                    )
                    else -> null
                }
            }
            .toList()
        return RedemptionHistoryStore(records)
    }

    fun saveRedemptionHistory(history: RedemptionHistoryStore) {
        prefs.edit()
            .putString(
                "redemptionHistory",
                history.records.joinToString("\n") {
                    "${it.id}\t${it.wishId}\t${it.title}\t${it.cost}\t${it.redeemedAtMs}\t${it.status}\t${it.iconEmoji}"
                },
            )
            .apply()
    }

    fun loadLearningRecorder(): LearningRecorder {
        val stats = prefs.getString("learningStats", "").orEmpty()
            .lineSequence()
            .mapNotNull { line ->
                val parts = line.split('\t')
                if (parts.size >= 6) {
                    val consecutiveCorrect = parts.getOrNull(9)?.toIntOrNull().orZero()
                    val consecutiveWrong = parts.getOrNull(10)?.toIntOrNull().orZero()
                    val lastOutcome = parseOutcome(parts.getOrNull(12), consecutiveCorrect, consecutiveWrong)
                    WordLearningStat(
                        packId = parts[0],
                        wordId = parts[1],
                        seenCount = parts[2].toIntOrNull().orZero(),
                        correctCount = parts[3].toIntOrNull().orZero(),
                        wrongCount = parts[4].toIntOrNull().orZero(),
                        lastSeenAtMs = parts[5].toLongOrNull() ?: 0L,
                        nextReviewMs = parts.getOrNull(6)?.toLongOrNull() ?: 0L,
                        memoryState = parseMemoryState(parts.getOrNull(7)),
                        consecutiveCorrect = consecutiveCorrect,
                        consecutiveWrong = consecutiveWrong,
                        mastery = parts.getOrNull(11)?.toIntOrNull().orZero(),
                        lastOutcome = lastOutcome,
                    )
                } else {
                    null
                }
            }
            .toList()
        return LearningRecorder(initialStats = stats)
    }

    fun saveLearningRecorder(recorder: LearningRecorder) {
        prefs.edit()
            .putString(
                "learningStats",
                recorder.statsSnapshot().joinToString("\n") {
                    "${it.packId}\t${it.wordId}\t${it.seenCount}\t${it.correctCount}\t${it.wrongCount}\t${it.lastSeenAtMs}\t${it.nextReviewMs}\t${it.memoryState.name}\t1\t${it.consecutiveCorrect}\t${it.consecutiveWrong}\t${it.mastery}\t${it.lastOutcome.name}"
                },
            )
            .apply()
    }

    fun loadDailyLearningState(): DailyLearningState {
        val raw = prefs.getString(DAILY_LEARNING_STATE_KEY, "").orEmpty()
        val parts = raw.split('\t')
        if (parts.size < 7) {
            return DailyLearningState.empty("")
        }
        val wordIds = splitCsv(parts[5])
        val reviewed = splitCsv(parts[6]).filter { it in wordIds.toSet() }
        return DailyLearningState(
            dayKey = parts[0],
            packBattleWon = parts[1].toBooleanStrictOrNull() ?: false,
            reviewAllDone = parts[2].toBooleanStrictOrNull() ?: wordIds.all { it in reviewed.toSet() },
            reviewSnapshot = DailyReviewSnapshot(
                dayKey = parts[0],
                generatedAtMs = parts[3].toLongOrNull() ?: 0L,
                sourceCutoffMs = parts[4].toLongOrNull() ?: 0L,
                wordIds = wordIds,
                reviewedWordIds = reviewed,
            ),
        )
    }

    fun saveDailyLearningState(state: DailyLearningState) {
        prefs.edit()
            .putString(
                DAILY_LEARNING_STATE_KEY,
                listOf(
                    state.dayKey,
                    state.packBattleWon.toString(),
                    state.reviewAllDone.toString(),
                    state.reviewSnapshot.generatedAtMs.toString(),
                    state.reviewSnapshot.sourceCutoffMs.toString(),
                    state.reviewSnapshot.wordIds.joinToString(","),
                    state.reviewSnapshot.reviewedWordIds.joinToString(","),
                ).joinToString("\t"),
            )
            .apply()
    }

    fun loadActiveBattleSnapshot(): ActiveBattleSnapshot? {
        val raw = prefs.getString(ACTIVE_BATTLE_SNAPSHOT_KEY, "").orEmpty()
        if (raw.isBlank()) return null
        return runCatching {
            val json = JSONObject(raw)
            val state = battleStateFromJson(json.getJSONObject("state"))
            ActiveBattleSnapshot(
                packId = json.optString("packId"),
                isReview = json.optBoolean("isReview", false),
                dailyDayKey = json.optString("dailyDayKey"),
                targetWordIds = json.optJSONArray("targetWordIds").toStringList(),
                config = gameConfigFromJson(json.optJSONObject("config")),
                state = state,
                timeLeft = json.optInt("timeLeft", GameConfig().timerSeconds).coerceAtLeast(1),
                runId = json.optInt("runId", 0),
                servedQuestions = json.optJSONArray("servedQuestions").toServedQuestions(),
            ).takeIf { it.state.status == BattleStatus.Playing }
        }.getOrNull()
    }

    fun saveActiveBattleSnapshot(snapshot: ActiveBattleSnapshot) {
        prefs.edit()
            .putString(
                ACTIVE_BATTLE_SNAPSHOT_KEY,
                JSONObject()
                    .put("packId", snapshot.packId)
                    .put("isReview", snapshot.isReview)
                    .put("dailyDayKey", snapshot.dailyDayKey)
                    .put("targetWordIds", stringJsonArray(snapshot.targetWordIds))
                    .put("config", gameConfigToJson(snapshot.config))
                    .put("state", battleStateToJson(snapshot.state))
                    .put("timeLeft", snapshot.timeLeft)
                    .put("runId", snapshot.runId)
                    .put("servedQuestions", servedQuestionsToJson(snapshot.servedQuestions))
                    .toString(),
            )
            .apply()
    }

    fun clearActiveBattleSnapshot() {
        prefs.edit().remove(ACTIVE_BATTLE_SNAPSHOT_KEY).apply()
    }

    private fun Int?.orZero(): Int = this ?: 0

    private fun splitCsv(raw: String): List<String> =
        raw.split(",").map { it.trim() }.filter { it.isNotEmpty() }

    private fun gameConfigToJson(config: GameConfig): JSONObject =
        JSONObject()
            .put("playerHp", config.playerHp)
            .put("monsterHp", config.monsterHp)
            .put("monsterCount", config.monsterCount)
            .put("timerSeconds", config.timerSeconds)
            .put("autoPronunciation", config.autoPronunciation)
            .put("enabledQuestionTypes", stringJsonArray(config.enabledQuestionTypes))

    private fun gameConfigFromJson(json: JSONObject?): GameConfig {
        val defaults = GameConfig()
        if (json == null) return defaults
        return GameConfig(
            playerHp = json.optInt("playerHp", defaults.playerHp),
            monsterHp = json.optInt("monsterHp", defaults.monsterHp),
            monsterCount = json.optInt("monsterCount", defaults.monsterCount),
            timerSeconds = json.optInt("timerSeconds", defaults.timerSeconds),
            autoPronunciation = json.optBoolean("autoPronunciation", defaults.autoPronunciation),
            enabledQuestionTypes = json.optJSONArray("enabledQuestionTypes").toStringList().ifEmpty { defaults.enabledQuestionTypes },
        )
    }

    private fun battleStateToJson(state: BattleState): JSONObject =
        JSONObject()
            .put("playerHp", state.playerHp)
            .put("monsterHp", state.monsterHp)
            .put("monsterIndex", state.monsterIndex)
            .put("combo", state.combo)
            .put("correctCount", state.correctCount)
            .put("wrongCount", state.wrongCount)
            .put("defeatedMonsters", state.defeatedMonsters)
            .put("question", questionToJson(state.question))
            .put("status", state.status.name)
            .put("currentMonsterBonus", state.currentMonsterBonus)
            .put("bonusKillCount", state.bonusKillCount)
            .put("defeatedMonsterLevelScore", state.defeatedMonsterLevelScore)
            .put("monsterCatalogIndex", state.monsterCatalogIndex)

    private fun battleStateFromJson(json: JSONObject): BattleState =
        BattleState(
            playerHp = json.optInt("playerHp"),
            monsterHp = json.optInt("monsterHp"),
            monsterIndex = json.optInt("monsterIndex", 1),
            combo = json.optInt("combo"),
            correctCount = json.optInt("correctCount"),
            wrongCount = json.optInt("wrongCount"),
            defeatedMonsters = json.optInt("defeatedMonsters"),
            question = questionFromJson(json.optJSONObject("question")),
            status = BattleStatus.values().firstOrNull { it.name == json.optString("status") } ?: BattleStatus.Playing,
            currentMonsterBonus = json.optBoolean("currentMonsterBonus"),
            bonusKillCount = json.optInt("bonusKillCount"),
            defeatedMonsterLevelScore = json.optInt("defeatedMonsterLevelScore"),
            monsterCatalogIndex = json.optInt("monsterCatalogIndex", 1),
        )

    private fun questionToJson(question: Question): JSONObject =
        JSONObject()
            .put("prompt", question.prompt)
            .put("correctAnswer", question.correctAnswer)
            .put("options", stringJsonArray(question.options))
            .put("wordId", question.wordId)
            .put("kind", question.kind.name)
            .put("letterTemplate", question.letterTemplate)
            .put("missingIndex", question.missingIndex)
            .put("letterOptions", stringJsonArray(question.letterOptions))
            .put("letterAnswer", question.letterAnswer)
            .put("letterTemplateBase", question.letterTemplateBase)
            .put("missingIndices", intJsonArray(question.missingIndices))
            .put("letterOptionsSteps", nestedStringJsonArray(question.letterOptionsSteps))
            .put("letterAnswers", stringJsonArray(question.letterAnswers))
            .put("currentStep", question.currentStep)
            .put("spellLetters", stringJsonArray(question.spellLetters))
            .put("spellRevealedMask", booleanJsonArray(question.spellRevealedMask))
            .put("spellPool", stringJsonArray(question.spellPool))
            .put("sentenceTemplate", question.sentenceTemplate)
            .put("sentenceZh", question.sentenceZh)

    private fun questionFromJson(json: JSONObject?): Question {
        if (json == null) return Question("", "", emptyList())
        return Question(
            prompt = json.optString("prompt"),
            correctAnswer = json.optString("correctAnswer"),
            options = json.optJSONArray("options").toStringList(),
            wordId = json.optString("wordId"),
            kind = QuestionKind.values().firstOrNull { it.name == json.optString("kind") } ?: QuestionKind.Choice,
            letterTemplate = json.optString("letterTemplate"),
            missingIndex = json.optInt("missingIndex", -1),
            letterOptions = json.optJSONArray("letterOptions").toStringList(),
            letterAnswer = json.optString("letterAnswer"),
            letterTemplateBase = json.optString("letterTemplateBase"),
            missingIndices = json.optJSONArray("missingIndices").toIntList(),
            letterOptionsSteps = json.optJSONArray("letterOptionsSteps").toNestedStringList(),
            letterAnswers = json.optJSONArray("letterAnswers").toStringList(),
            currentStep = json.optInt("currentStep"),
            spellLetters = json.optJSONArray("spellLetters").toStringList(),
            spellRevealedMask = json.optJSONArray("spellRevealedMask").toBooleanList(),
            spellPool = json.optJSONArray("spellPool").toStringList(),
            sentenceTemplate = json.optString("sentenceTemplate"),
            sentenceZh = json.optString("sentenceZh"),
        )
    }

    private fun stringJsonArray(values: List<String>): JSONArray =
        JSONArray().also { array -> values.forEach { array.put(it) } }

    private fun intJsonArray(values: List<Int>): JSONArray =
        JSONArray().also { array -> values.forEach { array.put(it) } }

    private fun booleanJsonArray(values: List<Boolean>): JSONArray =
        JSONArray().also { array -> values.forEach { array.put(it) } }

    private fun nestedStringJsonArray(values: List<List<String>>): JSONArray =
        JSONArray().also { outer ->
            values.forEach { inner -> outer.put(stringJsonArray(inner)) }
        }

    private fun servedQuestionsToJson(values: List<BattleServedQuestion>): JSONArray =
        JSONArray().also { array ->
            values.forEach { served ->
                array.put(
                    JSONObject()
                        .put("wordId", served.wordId)
                        .put("typeId", served.typeId),
                )
            }
        }

    private fun JSONArray?.toStringList(): List<String> {
        if (this == null) return emptyList()
        return (0 until length()).mapNotNull { index -> optString(index).takeIf { it.isNotEmpty() } }
    }

    private fun JSONArray?.toIntList(): List<Int> {
        if (this == null) return emptyList()
        return (0 until length()).map { index -> optInt(index) }
    }

    private fun JSONArray?.toBooleanList(): List<Boolean> {
        if (this == null) return emptyList()
        return (0 until length()).map { index -> optBoolean(index) }
    }

    private fun JSONArray?.toNestedStringList(): List<List<String>> {
        if (this == null) return emptyList()
        return (0 until length()).map { index -> optJSONArray(index).toStringList() }
    }

    private fun JSONArray?.toServedQuestions(): List<BattleServedQuestion> {
        if (this == null) return emptyList()
        return (0 until length()).mapNotNull { index ->
            val row = optJSONObject(index) ?: return@mapNotNull null
            val wordId = row.optString("wordId")
            val typeId = row.optString("typeId")
            if (wordId.isBlank() || typeId.isBlank()) null else BattleServedQuestion(wordId, typeId)
        }
    }

    private fun parseOutcome(raw: String?, consecutiveCorrect: Int, consecutiveWrong: Int): WordAnswerOutcome =
        when (raw) {
            WordAnswerOutcome.Correct.name -> WordAnswerOutcome.Correct
            WordAnswerOutcome.Wrong.name -> WordAnswerOutcome.Wrong
            WordAnswerOutcome.Unknown.name -> WordAnswerOutcome.Unknown
            else -> when {
                consecutiveWrong > 0 -> WordAnswerOutcome.Wrong
                consecutiveCorrect > 0 -> WordAnswerOutcome.Correct
                else -> WordAnswerOutcome.Unknown
            }
        }

    private fun parseMemoryState(raw: String?): WordMemoryState =
        WordMemoryState.values().firstOrNull { it.name == raw } ?: WordMemoryState.New

    companion object {
        private const val DAILY_LEARNING_STATE_KEY = "daily_learning_state/snapshot_v1"
        private const val ACTIVE_BATTLE_SNAPSHOT_KEY = "active_battle/snapshot_v1"
    }
}
