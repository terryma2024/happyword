package cool.happyword.wordmagic.core

data class SharedPackFixture(
    val familyId: String,
    val packs: List<SharedPackSummary>,
)

data class SharedPackSummary(
    val packId: String,
    val name: String,
    val words: List<SharedWordSummary>,
)

data class SharedWordSummary(
    val id: String,
    val word: String,
    val meaningZh: String,
)

data class PairRedeemFixture(
    val bindingId: String,
    val familyId: String,
    val childProfileId: String,
    val nickname: String,
    val avatarEmoji: String,
    val deviceToken: String,
)

data class WordStatsSyncFixture(
    val accepted: List<String>,
    val serverPulls: List<ServerWordStatFixture>,
)

data class ServerWordStatFixture(
    val wordId: String,
    val seenCount: Int,
    val correctCount: Int,
    val wrongCount: Int,
    val memoryState: String,
)

data class PreviewUrlFixture(
    val number: Int,
    val branch: String,
    val url: String,
)

object SharedFixtureDecoder {
    fun decodePackFixture(json: String): SharedPackFixture {
        val familyId = stringValue(json, "family_id")
        val packBlocks = Regex(""""pack_id"\s*:\s*"([^"]+)"([\s\S]*?)"words"\s*:\s*\[([\s\S]*?)]""")
            .findAll(json)
            .map { match ->
                val block = match.groupValues[2]
                val wordsBlock = match.groupValues[3]
                SharedPackSummary(
                    packId = match.groupValues[1],
                    name = stringValue(block, "name"),
                    words = decodeWords(wordsBlock),
                )
            }
            .toList()
        return SharedPackFixture(familyId = familyId, packs = packBlocks)
    }

    fun decodePairRedeemFixture(json: String): PairRedeemFixture {
        return PairRedeemFixture(
            bindingId = stringValue(json, "binding_id"),
            familyId = stringValue(json, "family_id"),
            childProfileId = stringValue(json, "child_profile_id"),
            nickname = stringValue(json, "nickname"),
            avatarEmoji = stringValue(json, "avatar_emoji"),
            deviceToken = stringValue(json, "device_token"),
        )
    }

    fun decodeWordStatsSyncFixture(json: String): WordStatsSyncFixture {
        val accepted = stringArray(json, "accepted")
        val pullsBlock = arrayBlock(json, "server_pulls")
        val pulls = Regex("""\{([\s\S]*?)}""")
            .findAll(pullsBlock)
            .map { match ->
                val block = match.groupValues[1]
                ServerWordStatFixture(
                    wordId = stringValue(block, "word_id"),
                    seenCount = intValue(block, "seen_count"),
                    correctCount = intValue(block, "correct_count"),
                    wrongCount = intValue(block, "wrong_count"),
                    memoryState = stringValue(block, "memory_state"),
                )
            }
            .toList()
        return WordStatsSyncFixture(accepted = accepted, serverPulls = pulls)
    }

    fun decodePreviewUrlsFixture(json: String): List<PreviewUrlFixture> {
        return Regex("""\{([\s\S]*?)}""")
            .findAll(arrayBlock(json, "pulls"))
            .map { match ->
                val block = match.groupValues[1]
                PreviewUrlFixture(
                    number = intValue(block, "number"),
                    branch = stringValue(block, "branch"),
                    url = stringValue(block, "url"),
                )
            }
            .filter { it.url.startsWith("http") }
            .toList()
    }

    private fun decodeWords(wordsBlock: String): List<SharedWordSummary> {
        return Regex("""\{([\s\S]*?)}""")
            .findAll(wordsBlock)
            .map { match ->
                val block = match.groupValues[1]
                SharedWordSummary(
                    id = stringValue(block, "id"),
                    word = stringValue(block, "word"),
                    meaningZh = stringValue(block, "meaningZh"),
                )
            }
            .toList()
    }

    private fun stringValue(json: String, key: String): String {
        return Regex(""""$key"\s*:\s*"([^"]*)"""")
            .find(json)
            ?.groupValues
            ?.get(1)
            .orEmpty()
    }

    private fun intValue(json: String, key: String): Int {
        return Regex(""""$key"\s*:\s*(\d+)""")
            .find(json)
            ?.groupValues
            ?.get(1)
            ?.toIntOrNull()
            ?: 0
    }

    private fun stringArray(json: String, key: String): List<String> {
        val block = arrayBlock(json, key)
        return Regex(""""([^"]+)"""").findAll(block).map { it.groupValues[1] }.toList()
    }

    private fun arrayBlock(json: String, key: String): String {
        return Regex(""""$key"\s*:\s*\[([\s\S]*?)]""")
            .find(json)
            ?.groupValues
            ?.get(1)
            .orEmpty()
    }
}
