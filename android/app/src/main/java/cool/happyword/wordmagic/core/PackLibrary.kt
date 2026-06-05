package cool.happyword.wordmagic.core

class PackLibrary private constructor(
    private val packsById: Map<String, WordPack>,
) {
    fun allPacks(): List<WordPack> = packsById.values.toList()

    fun requirePack(id: String): WordPack = packsById[id] ?: error("Unknown pack id: $id")

    fun findPack(id: String): WordPack? = packsById[id]

    fun existingIdsInOrder(ids: List<String>): List<String> {
        val seen = linkedSetOf<String>()
        ids.forEach { id ->
            if (packsById.containsKey(id)) {
                seen += id
            }
        }
        return seen.toList()
    }

    fun activePacks(activeIds: List<String>): List<WordPack> = existingIdsInOrder(activeIds).map(::requirePack)

    fun inactivePacks(activeIds: List<String>): List<WordPack> {
        val active = activeIds.toSet()
        return allPacks().filterNot { it.id in active }
    }

    companion object {
        fun merge(
            builtin: List<WordPack>,
            global: List<WordPack>,
            family: List<WordPack>,
        ): PackLibrary {
            val builtinScenes = builtin.associate { it.id to it.scene }
            val merged = linkedMapOf<String, WordPack>()
            builtin.forEach { merged[it.id] = it }
            global.forEach { pack ->
                merged[pack.id] = pack.copy(scene = mergeSceneWithFallback(pack.id, pack.scene, builtinScenes[pack.id]))
            }
            family.forEach { pack ->
                merged[pack.id] = pack.copy(scene = mergeSceneWithFallback(pack.id, pack.scene, builtinScenes[pack.id]))
            }
            return PackLibrary(merged)
        }

        private fun mergeSceneWithFallback(packId: String, own: SceneMetadata, fallback: SceneMetadata?): SceneMetadata {
            val sceneFallback = fallback ?: fallbackSceneFor(packId)
            if (!needsSceneFallback(own) && fallback == null) return own
            return SceneMetadata(
                bgPrimary = own.bgPrimary.takeUnless { it == "#FFFFFF" } ?: sceneFallback.bgPrimary,
                bgAccent = own.bgAccent.takeUnless { it == "#FFFFFF" } ?: sceneFallback.bgAccent,
                bossName = own.bossName.takeIf { it.isNotBlank() } ?: sceneFallback.bossName,
                monsterPlan = own.monsterPlan.takeIf { it.isNotEmpty() } ?: sceneFallback.monsterPlan,
                bossCandidates = own.bossCandidates.takeIf { it.isNotEmpty() } ?: sceneFallback.bossCandidates,
                storyZh = own.storyZh.takeIf { it.isNotBlank() } ?: sceneFallback.storyZh,
                storyEn = own.storyEn.takeIf { it.isNotBlank() } ?: sceneFallback.storyEn,
                spellbookCoverUrl = own.spellbookCoverUrl.takeIf { it.isNotBlank() } ?: sceneFallback.spellbookCoverUrl,
            )
        }

        private fun needsSceneFallback(scene: SceneMetadata): Boolean =
            scene.bgPrimary == "#FFFFFF" ||
                scene.bgAccent == "#FFFFFF" ||
                scene.bossName.isBlank() ||
                scene.monsterPlan.isEmpty() ||
                scene.bossCandidates.isEmpty()

        private fun fallbackSceneFor(seed: String): SceneMetadata {
            val palette = FALLBACK_PALETTE[stableHash(seed).mod(FALLBACK_PALETTE.size)]
            return SceneMetadata(
                bgPrimary = palette.bgPrimary,
                bgAccent = palette.bgAccent,
                bossName = palette.bossName,
                monsterPlan = listOf("slime", "zombie", "dragon"),
                bossCandidates = listOf("dragon"),
                storyZh = "",
                storyEn = "",
            )
        }

        private fun stableHash(value: String): Int {
            var hash = 5381
            value.forEach { ch ->
                hash = ((hash shl 5) - hash) + ch.code
            }
            return hash and Int.MAX_VALUE
        }

        private data class FallbackPalette(
            val bgPrimary: String,
            val bgAccent: String,
            val bossName: String,
        )

        private val FALLBACK_PALETTE = listOf(
            FallbackPalette("#FFF6E0", "#FFD49A", "Orchard Sentinel"),
            FallbackPalette("#E8F0FE", "#AECBFA", "Clock Wizard"),
            FallbackPalette("#FFF1E6", "#F4B98A", "Toy Knight"),
            FallbackPalette("#F0F8E8", "#A4D274", "Meadow Beast"),
            FallbackPalette("#E8F4F8", "#6EB7CC", "Sea Sovereign"),
        )
    }
}
