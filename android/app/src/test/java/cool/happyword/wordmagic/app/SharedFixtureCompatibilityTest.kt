package cool.happyword.wordmagic.app

import cool.happyword.wordmagic.core.SharedFixtureDecoder
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SharedFixtureCompatibilityTest {
    @Test
    fun decodesGlobalAndFamilyPackFixtures() {
        val global = SharedFixtureDecoder.decodePackFixture(readFixture("packs/global-packs-latest.sample.json"))
        val family = SharedFixtureDecoder.decodePackFixture(readFixture("packs/family-packs-latest.sample.json"))

        assertEquals("space-station", global.packs.single().packId)
        assertEquals("Space Station", global.packs.single().name)
        assertEquals("space-star", global.packs.single().words.single().id)
        assertEquals("family-demo", family.familyId)
        assertEquals("family-snacks", family.packs.single().packId)
    }

    @Test
    fun decodesPairingAndWordStatsFixtures() {
        val pairing = SharedFixtureDecoder.decodePairRedeemFixture(readFixture("pairing/pair-redeem.sample.json"))
        val stats = SharedFixtureDecoder.decodeWordStatsSyncFixture(readFixture("child/word-stats-sync.sample.json"))

        assertEquals("binding-demo", pairing.bindingId)
        assertEquals("device-token-demo-not-a-secret", pairing.deviceToken)
        assertEquals(listOf("space-star"), stats.accepted)
        assertEquals(1, stats.serverPulls.size)
        assertEquals("learning", stats.serverPulls.single().memoryState)
    }

    @Test
    fun decodesPreviewUrlsFixture() {
        val previews = SharedFixtureDecoder.decodePreviewUrlsFixture(readFixture("public/preview-urls.sample.json"))

        assertEquals(1, previews.size)
        assertEquals(55, previews.single().number)
        assertEquals("codex/polish_docs", previews.single().branch)
        assertTrue(previews.single().url.startsWith("https://"))
    }

    private fun readFixture(relativePath: String): String {
        val candidates = listOf(
            File("shared/fixtures/$relativePath"),
            File("../shared/fixtures/$relativePath"),
            File("../../shared/fixtures/$relativePath"),
        )
        val file = candidates.firstOrNull { it.isFile }
            ?: error("Missing shared fixture $relativePath from ${File(".").absolutePath}")
        return file.readText()
    }
}
