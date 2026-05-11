package cool.happyword.wordmagic.core

data class PackSelectionMutation(
    val selection: PackSelectionStore,
    val accepted: Boolean,
    val message: String = "",
)

data class PackSelectionStore(
    val activePackIds: List<String>,
    val pinnedPackIds: Set<String>,
    val perfectScoresByPack: Map<String, Int>,
    val lastSelectionUpdatedAtMs: Long,
) {
    fun activate(packId: String, nowMs: Long = System.currentTimeMillis()): PackSelectionMutation {
        if (packId in activePackIds) return PackSelectionMutation(this, true)
        if (activePackIds.size >= MAX_ACTIVE) {
            return PackSelectionMutation(this, false, "最多只能同时启用 5 个词包")
        }
        return PackSelectionMutation(copy(activePackIds = activePackIds + packId, lastSelectionUpdatedAtMs = nowMs), true)
    }

    fun deactivate(packId: String, nowMs: Long = System.currentTimeMillis()): PackSelectionMutation {
        return PackSelectionMutation(
            copy(
                activePackIds = activePackIds.filterNot { it == packId },
                pinnedPackIds = pinnedPackIds - packId,
                lastSelectionUpdatedAtMs = nowMs,
            ),
            true,
        )
    }

    fun togglePin(packId: String, nowMs: Long = System.currentTimeMillis()): PackSelectionMutation {
        if (packId !in activePackIds) return PackSelectionMutation(this, false, "只能固定已启用的词包")
        val nextPins = if (packId in pinnedPackIds) pinnedPackIds - packId else pinnedPackIds + packId
        return PackSelectionMutation(copy(pinnedPackIds = nextPins, lastSelectionUpdatedAtMs = nowMs), true)
    }

    fun prune(library: PackLibrary, nowMs: Long = System.currentTimeMillis()): PackSelectionStore {
        val nextActive = library.existingIdsInOrder(activePackIds).take(MAX_ACTIVE)
        return copy(
            activePackIds = nextActive,
            pinnedPackIds = pinnedPackIds.intersect(nextActive.toSet()),
            perfectScoresByPack = perfectScoresByPack.filterKeys { it in nextActive },
            lastSelectionUpdatedAtMs = nowMs,
        )
    }

    fun recordPerfectRun(packId: String, library: PackLibrary, nowMs: Long = System.currentTimeMillis()): PackSelectionMutation {
        if (packId !in activePackIds || packId in pinnedPackIds) {
            return PackSelectionMutation(this, true)
        }
        val nextScore = (perfectScoresByPack[packId] ?: 0) + 1
        if (nextScore < PERFECT_RUNS_TO_ROTATE) {
            return PackSelectionMutation(
                copy(perfectScoresByPack = perfectScoresByPack + (packId to nextScore)),
                true,
            )
        }
        val candidate = rotationCandidates(library).firstOrNull()
        if (candidate == null) {
            return PackSelectionMutation(
                copy(perfectScoresByPack = perfectScoresByPack + (packId to nextScore)),
                true,
            )
        }
        val rotated = activePackIds.map { if (it == packId) candidate.id else it }
        return PackSelectionMutation(
            copy(
                activePackIds = rotated,
                perfectScoresByPack = perfectScoresByPack - packId,
                lastSelectionUpdatedAtMs = nowMs,
            ),
            true,
            "已轮换到 ${candidate.nameZh}",
        )
    }

    private fun rotationCandidates(library: PackLibrary): List<WordPack> {
        return library.inactivePacks(activePackIds)
            .sortedWith(
                compareBy<WordPack> {
                    when (it.source) {
                        PackSource.Family -> 0
                        PackSource.Global -> 1
                        PackSource.Builtin -> 2
                    }
                }.thenByDescending { it.publishedAtMs ?: 0L }.thenBy { it.id },
            )
    }

    companion object {
        const val MAX_ACTIVE = 5
        const val PERFECT_RUNS_TO_ROTATE = 3

        fun initial(defaultIds: List<String>, nowMs: Long = 0L): PackSelectionStore {
            return PackSelectionStore(
                activePackIds = defaultIds.distinct().take(MAX_ACTIVE),
                pinnedPackIds = emptySet(),
                perfectScoresByPack = emptyMap(),
                lastSelectionUpdatedAtMs = nowMs,
            )
        }
    }
}
