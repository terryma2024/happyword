package cool.happyword.wordmagic.core

data class BattleTtsVoiceCandidate(
    val name: String,
    val language: String,
    val country: String,
    val networkConnectionRequired: Boolean,
)

object BattleTtsVoiceSelector {
    private val preferredNameParts = listOf("server", "network")

    fun choose(
        candidates: Collection<BattleTtsVoiceCandidate>,
        unavailableVoiceNames: Set<String> = emptySet(),
    ): BattleTtsVoiceCandidate? {
        val englishCandidates = candidates
            .filter { it.language.equals("en", ignoreCase = true) }
            .filterNot { it.name in unavailableVoiceNames }
        val localVoiceFailed = candidates.any {
            it.name in unavailableVoiceNames && !it.networkConnectionRequired
        }
        val fallbackCandidates = if (localVoiceFailed) {
            englishCandidates.filter { it.networkConnectionRequired }
        } else {
            englishCandidates
        }

        return fallbackCandidates
            .sortedWith(
                compareBy<BattleTtsVoiceCandidate> { it.networkConnectionRequired }
                    .thenByDescending { it.country.equals("US", ignoreCase = true) }
                    .thenByDescending { candidate ->
                        preferredNameParts.any { candidate.name.contains(it, ignoreCase = true) }
                    }
                    .thenBy { it.name },
            )
            .firstOrNull()
    }
}
