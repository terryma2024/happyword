package cool.happyword.wordmagic.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class BattleTtsVoiceSelectorTest {
    @Test
    fun choosesLocalVoiceBeforeNetworkVoiceForProductionDefault() {
        val selected = BattleTtsVoiceSelector.choose(
            listOf(
                BattleTtsVoiceCandidate(
                    name = "en-us-x-iog-seanet-embedded",
                    language = "en",
                    country = "US",
                    networkConnectionRequired = false,
                ),
                BattleTtsVoiceCandidate(
                    name = "en-us-x-iog-server",
                    language = "en",
                    country = "US",
                    networkConnectionRequired = true,
                ),
            ),
        )

        assertEquals("en-us-x-iog-seanet-embedded", selected?.name)
    }

    @Test
    fun fallsBackToNetworkVoiceWhenLocalVoiceIsUnavailable() {
        val selected = BattleTtsVoiceSelector.choose(
            listOf(
                BattleTtsVoiceCandidate(
                    name = "en-us-x-iog-seanet-embedded",
                    language = "en",
                    country = "US",
                    networkConnectionRequired = false,
                ),
                BattleTtsVoiceCandidate(
                    name = "en-us-x-iob-local",
                    language = "en",
                    country = "US",
                    networkConnectionRequired = false,
                ),
                BattleTtsVoiceCandidate(
                    name = "en-us-x-iog-network",
                    language = "en",
                    country = "US",
                    networkConnectionRequired = true,
                ),
            ),
            unavailableVoiceNames = setOf("en-us-x-iog-seanet-embedded"),
        )

        assertEquals("en-us-x-iog-network", selected?.name)
    }

    @Test
    fun returnsNullWhenAllEnglishVoicesAreUnavailable() {
        val selected = BattleTtsVoiceSelector.choose(
            listOf(
                BattleTtsVoiceCandidate(
                    name = "en-us-x-iog-seanet-embedded",
                    language = "en",
                    country = "US",
                    networkConnectionRequired = false,
                ),
            ),
            unavailableVoiceNames = setOf("en-us-x-iog-seanet-embedded"),
        )

        assertNull(selected)
    }
}
