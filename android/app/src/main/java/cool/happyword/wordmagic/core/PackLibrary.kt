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
                merged[pack.id] = pack.copy(scene = builtinScenes[pack.id] ?: pack.scene)
            }
            family.forEach { pack ->
                merged[pack.id] = pack.copy(scene = builtinScenes[pack.id] ?: pack.scene)
            }
            return PackLibrary(merged)
        }
    }
}
