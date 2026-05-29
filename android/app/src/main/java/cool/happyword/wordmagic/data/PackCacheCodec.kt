package cool.happyword.wordmagic.data

import cool.happyword.wordmagic.core.PackSource
import cool.happyword.wordmagic.core.SceneMetadata
import cool.happyword.wordmagic.core.WordEntry
import cool.happyword.wordmagic.core.WordPack

internal object PackCacheCodec {
    fun encode(packs: List<WordPack>): String {
        return packs.joinToString("\n") { pack ->
            val words = pack.words.joinToString(";") { word ->
                listOf(word.id, word.word, word.meaning, word.difficulty.toString()).joinToString(",")
            }
            listOf(
                pack.id,
                pack.nameEn,
                pack.nameZh,
                pack.source.name,
                pack.version.toString(),
                (pack.publishedAtMs ?: 0L).toString(),
                pack.scene.storyZh,
                pack.scene.storyEn,
                words,
            ).joinToString("\t")
        }
    }

    fun decode(raw: String, fallbackSource: PackSource): List<WordPack> {
        return raw.lineSequence().mapNotNull { line ->
            val parts = line.split('\t')
            if (parts.size != 8 && parts.size != 9) return@mapNotNull null
            val legacyRow = parts.size == 8
            val wordsPart = if (legacyRow) parts[7] else parts[8]
            val words = wordsPart.split(';').mapNotNull(::decodeWord)
            if (words.isEmpty()) return@mapNotNull null
            WordPack(
                id = parts[0],
                nameEn = parts[1],
                nameZh = parts[2],
                source = runCatching { PackSource.valueOf(parts[3]) }.getOrDefault(fallbackSource),
                version = parts[4].toIntOrNull() ?: 1,
                publishedAtMs = parts[5].toLongOrNull()?.takeIf { it > 0L },
                scene = SceneMetadata(
                    bgPrimary = "#FFF7E6",
                    bgAccent = "#FFD2A6",
                    bossName = "${parts[1]} Boss",
                    monsterPlan = listOf("slime", "zombie", "dragon"),
                    bossCandidates = listOf("dragon"),
                    storyZh = parts[6],
                    storyEn = if (legacyRow) "" else parts[7],
                ),
                words = words,
            )
        }.toList()
    }

    private fun decodeWord(token: String): WordEntry? {
        val parts = token.split(',')
        if (parts.size != 3 && parts.size != 4) return null
        return WordEntry(
            id = parts[0],
            word = parts[1],
            meaning = parts[2],
            difficulty = parts.getOrNull(3)?.toIntOrNull() ?: 1,
        )
    }
}
