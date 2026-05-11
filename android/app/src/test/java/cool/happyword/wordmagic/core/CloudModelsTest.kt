package cool.happyword.wordmagic.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CloudModelsTest {
    @Test
    fun deviceIdProviderIsStableAcrossReloads() {
        val store = MemoryStringKeyValueStore()
        val provider = DeviceIdProvider(store) { "device-1" }

        assertEquals("device-1", provider.getOrCreate())
        assertEquals("device-1", DeviceIdProvider(store) { "device-2" }.getOrCreate())
    }

    @Test
    fun credentialsStoreKeepsTokenOutOfLabelStore() {
        val labels = MemoryStringKeyValueStore()
        val tokens = MemoryStringKeyValueStore()
        val store = CloudCredentialsStore(labels, tokens)

        store.save(CloudCredentials("device-1", "secret-token", "binding-1", "小明", "🦁", "Family"))

        assertEquals("secret-token", store.load()?.deviceToken)
        assertFalse(labels.snapshot().values.contains("secret-token"))
    }

    @Test
    fun fixtureBindingCreatesCredentialsForManualCode() {
        val result = FixtureDeviceBindingClient().redeemShortCode("abc123", "device-1")

        assertTrue(result is BindingResult.Success)
        assertEquals("binding-ABC123", (result as BindingResult.Success).credentials.bindingId)
    }

    @Test
    fun syncCoordinatorKeepsOfflineResultWhenClientsFail() {
        val result = CloudSyncCoordinator(
            globalClient = FixtureGlobalPackClient(fail = true),
            familyClient = FixtureFamilyPackClient(fail = true),
            clockMs = { 100L },
        ).syncPacks(null)

        assertEquals(emptyList<WordPack>(), result.globalPacks)
        assertEquals(emptyList<WordPack>(), result.familyPacks)
        assertEquals("离线模式：保留本地词包", result.statusMessage)
    }

    @Test
    fun statsPayloadContainsPackAndWordIds() {
        val payload = WordStatsSyncClient().buildPayload(
            listOf(WordLearningStat("fruit-forest", "fruit-apple", 2, 1, 1, 200L)),
            syncedThroughMs = 50L,
        )

        assertTrue(payload.contains("fruit-forest"))
        assertTrue(payload.contains("fruit-apple"))
        assertTrue(payload.contains("synced_through_ms"))
        assertNotNull(payload)
    }
}
