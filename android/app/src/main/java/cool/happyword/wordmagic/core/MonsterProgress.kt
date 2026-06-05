package cool.happyword.wordmagic.core

const val MONSTER_PROGRESS_PREFS_KEY: String = "monster_progress/snapshot_v1"
const val MONSTER_MYSTERY_RESOURCE_NAME: String = "character_monster_mystery_question"

data class MonsterProgressRecord(
    val catalogIndex: Int = 0,
    val encountered: Boolean = false,
    val defeatCount: Int = 0,
    val claimedMilestones: List<Int> = emptyList(),
)

data class MonsterRewardState(
    val milestone: Int,
    val amount: Int,
    val label: String,
    val enabled: Boolean,
    val claimed: Boolean,
) {
    companion object {
        fun forMilestone(defeatCount: Int, claimed: Boolean, milestone: Int): MonsterRewardState {
            val amount = milestoneCoinAmount(milestone)
            if (claimed) {
                return MonsterRewardState(milestone, amount, "已领 $amount 金币", enabled = false, claimed = true)
            }
            if (amount > 0 && defeatCount >= milestone) {
                return MonsterRewardState(milestone, amount, "领 $amount 金币", enabled = true, claimed = false)
            }
            val safeDefeats = defeatCount.coerceAtLeast(0)
            return MonsterRewardState(milestone, amount, "$amount 金币 $safeDefeats/$milestone", enabled = false, claimed = false)
        }
    }
}

data class MonsterClaimRewardResult(
    val claimed: Boolean,
    val snapshot: MonsterProgressSnapshot,
    val account: CoinAccount,
)

data class MonsterProgressSnapshot(
    val version: Int = 1,
    val records: List<MonsterProgressRecord> = emptyList(),
) {
    fun recordFor(catalogIndex: Int): MonsterProgressRecord {
        val index = catalogIndex.coerceAtLeast(0)
        return records.firstOrNull { it.catalogIndex == index } ?: MonsterProgressRecord(catalogIndex = index)
    }

    fun recordEncounter(catalogIndex: Int): MonsterProgressSnapshot {
        val index = catalogIndex.coerceAtLeast(0)
        if (index <= 0) return this
        val record = recordFor(index).copy(catalogIndex = index, encountered = true)
        return upsert(record)
    }

    fun recordDefeat(catalogIndex: Int): MonsterProgressSnapshot {
        val index = catalogIndex.coerceAtLeast(0)
        if (index <= 0) return this
        val current = recordFor(index)
        val next = current.copy(
            catalogIndex = index,
            encountered = true,
            defeatCount = current.defeatCount.coerceAtLeast(0) + 1,
        )
        return upsert(next)
    }

    fun rewardState(catalogIndex: Int, milestone: Int): MonsterRewardState {
        val record = recordFor(catalogIndex)
        return MonsterRewardState.forMilestone(
            defeatCount = record.defeatCount,
            claimed = milestone in record.claimedMilestones,
            milestone = milestone,
        )
    }

    fun claimReward(catalogIndex: Int, milestone: Int, account: CoinAccount): MonsterClaimRewardResult {
        val index = catalogIndex.coerceAtLeast(0)
        val record = recordFor(index)
        val amount = milestoneCoinAmount(milestone)
        if (!record.encountered || amount <= 0 || record.defeatCount < milestone || milestone in record.claimedMilestones) {
            return MonsterClaimRewardResult(false, this, account)
        }
        val credited = account.creditCapFree("monster-codex:$milestone:$index", amount)
        if (credited.delta <= 0) {
            return MonsterClaimRewardResult(false, this, account)
        }
        val nextRecord = record.copy(claimedMilestones = normalizeMilestones(record.claimedMilestones + milestone))
        return MonsterClaimRewardResult(true, upsert(nextRecord), credited.account)
    }

    fun serialize(): String {
        val serializedRecords = records
            .filter { it.catalogIndex > 0 }
            .sortedBy { it.catalogIndex }
            .joinToString(",") { record ->
                val milestones = normalizeMilestones(record.claimedMilestones).joinToString(",", prefix = "[", postfix = "]")
                """{"catalogIndex":${record.catalogIndex},"encountered":${record.encountered},"defeatCount":${record.defeatCount.coerceAtLeast(0)},"claimedMilestones":$milestones}"""
            }
        return """{"version":$version,"records":[$serializedRecords]}"""
    }

    private fun upsert(record: MonsterProgressRecord): MonsterProgressSnapshot {
        if (record.catalogIndex <= 0) return this
        val normalized = record.copy(
            defeatCount = record.defeatCount.coerceAtLeast(0),
            claimedMilestones = normalizeMilestones(record.claimedMilestones),
        )
        val without = records.filterNot { it.catalogIndex == normalized.catalogIndex }
        return copy(records = (without + normalized).sortedBy { it.catalogIndex })
    }

    companion object {
        fun parse(raw: String?): MonsterProgressSnapshot {
            if (raw.isNullOrBlank()) return MonsterProgressSnapshot()
            val version = intField(raw, "version") ?: 1
            val records = mutableListOf<MonsterProgressRecord>()
            val seen = mutableSetOf<Int>()
            val recordsBlock = arrayBlock(raw, "records")
            for (match in Regex("""\{[^{}]*\}""").findAll(recordsBlock)) {
                val item = match.value
                val catalogIndex = intField(item, "catalogIndex") ?: 0
                if (catalogIndex <= 0 || catalogIndex in seen) continue
                seen += catalogIndex
                records += MonsterProgressRecord(
                    catalogIndex = catalogIndex,
                    encountered = booleanField(item, "encountered") ?: false,
                    defeatCount = (intField(item, "defeatCount") ?: 0).coerceAtLeast(0),
                    claimedMilestones = normalizeMilestones(intArrayField(item, "claimedMilestones")),
                )
            }
            return MonsterProgressSnapshot(version = version, records = records.sortedBy { it.catalogIndex })
        }
    }
}

fun maskedQuestionMarks(source: String): String = "?".repeat(source.length)

fun milestoneCoinAmount(milestone: Int): Int = when (milestone) {
    50 -> 50
    100 -> 100
    else -> 0
}

private fun normalizeMilestones(raw: List<Int>): List<Int> =
    raw.map { it }
        .filter { it == 50 || it == 100 }
        .distinct()
        .sorted()

private fun intField(json: String, key: String): Int? =
    Regex(""""${Regex.escape(key)}"\s*:\s*(-?\d+)""").find(json)?.groupValues?.get(1)?.toIntOrNull()

private fun booleanField(json: String, key: String): Boolean? =
    Regex(""""${Regex.escape(key)}"\s*:\s*(true|false)""").find(json)?.groupValues?.get(1)?.toBooleanStrictOrNull()

private fun intArrayField(json: String, key: String): List<Int> =
    arrayBlock(json, key)
        .split(",")
        .mapNotNull { it.trim().toIntOrNull() }

private fun arrayBlock(json: String, key: String): String {
    val keyMatch = Regex(""""${Regex.escape(key)}"\s*:""").find(json) ?: return ""
    val start = json.indexOf('[', keyMatch.range.last + 1)
    if (start < 0) return ""
    var depth = 0
    for (i in start until json.length) {
        when (json[i]) {
            '[' -> depth += 1
            ']' -> {
                depth -= 1
                if (depth == 0) return json.substring(start + 1, i)
            }
        }
    }
    return ""
}
