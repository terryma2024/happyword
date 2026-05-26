package cool.happyword.wordmagic.data

import android.content.Context
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
import cool.happyword.wordmagic.core.WordLearningStat
import cool.happyword.wordmagic.core.WordAnswerOutcome
import cool.happyword.wordmagic.core.WordMemoryState

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

    private fun Int?.orZero(): Int = this ?: 0

    private fun splitCsv(raw: String): List<String> =
        raw.split(",").map { it.trim() }.filter { it.isNotEmpty() }

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
    }
}
