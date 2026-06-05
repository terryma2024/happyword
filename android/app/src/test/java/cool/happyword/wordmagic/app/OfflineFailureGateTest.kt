package cool.happyword.wordmagic.app

import cool.happyword.wordmagic.core.BuiltinPacks
import cool.happyword.wordmagic.core.CloudSyncCoordinator
import cool.happyword.wordmagic.core.FixtureFamilyPackClient
import cool.happyword.wordmagic.core.FixtureGlobalPackClient
import cool.happyword.wordmagic.core.PackLibrary
import cool.happyword.wordmagic.core.WordLearningStat
import cool.happyword.wordmagic.core.WordStatsSyncClient
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class OfflineFailureGateTest {
    @Test
    fun failedPackSyncPreservesBuiltinPlayablePacks() = runBlocking {
        val syncResult = CloudSyncCoordinator(
            globalClient = FixtureGlobalPackClient(fail = true),
            familyClient = FixtureFamilyPackClient(fail = true),
            clockMs = { 1_000L },
        ).syncPacks(credentials = null)
        val library = PackLibrary.merge(BuiltinPacks.all, syncResult.globalPacks, syncResult.familyPacks)

        assertEquals("离线模式：保留本地词包", syncResult.statusMessage)
        assertTrue(library.allPacks().any { it.id == "fruit-forest" })
        assertTrue(library.findPack("fruit-forest")?.words.orEmpty().isNotEmpty())
    }

    @Test
    fun failedWordStatsSyncFallsBackToEmptyPayload() {
        val coordinator = CloudSyncCoordinator(
            statsClient = object : WordStatsSyncClient() {
                override fun buildPayload(stats: List<WordLearningStat>, syncedThroughMs: Long): String {
                    error("network unavailable")
                }
            },
        )

        val payload = coordinator.syncStats(
            stats = listOf(WordLearningStat("fruit-forest", "fruit-apple", 1, 1, 0, 123L)),
            syncedThroughMs = 456L,
        )

        assertEquals("""{"items":[],"synced_through_ms":456}""", payload)
    }

}
