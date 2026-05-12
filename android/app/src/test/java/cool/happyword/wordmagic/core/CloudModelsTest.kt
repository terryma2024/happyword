package cool.happyword.wordmagic.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlinx.coroutines.runBlocking

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
    fun deviceBindingClientPostsShortCodeToPairRedeemEndpoint() = runBlocking {
        var capturedMethod = ""
        var capturedUrl = ""
        var capturedBody = ""
        val client = DeviceBindingClient(
            baseUrlProvider = { "https://happyword.cool/" },
            extraHeadersProvider = { mapOf("x-vercel-protection-bypass" to "secret") },
            transport = BindingHttpTransport { method, url, headers, body ->
                capturedMethod = method
                capturedUrl = url
                capturedBody = body
                assertEquals("application/json", headers["Content-Type"])
                assertEquals("application/json", headers["Accept"])
                assertEquals("secret", headers["x-vercel-protection-bypass"])
                BindingHttpResponse(
                    200,
                    """{"binding_id":"bind-1","family_id":"fam-1","child_profile_id":"child-1","nickname":"宝贝","avatar_emoji":"🦁","device_token":"jwt.token.value"}""",
                )
            },
        )

        val result = client.redeemShortCode("123456", "device-aaaa")

        assertTrue(result is BindingResult.Success)
        assertEquals("POST", capturedMethod)
        assertEquals("https://happyword.cool/api/v1/pair/redeem", capturedUrl)
        assertEquals("""{"short_code":"123456","device_id":"device-aaaa"}""", capturedBody)
        assertEquals("bind-1", (result as BindingResult.Success).credentials.bindingId)
        assertEquals("jwt.token.value", result.credentials.deviceToken)
    }

    @Test
    fun deviceBindingClientMapsServerErrorCodesToUserMessages() = runBlocking {
        val client = DeviceBindingClient(
            baseUrlProvider = { "http://10.0.2.2:8000" },
            transport = BindingHttpTransport { _, _, _, _ ->
                BindingHttpResponse(
                    410,
                    """{"detail":{"error":{"code":"TOKEN_EXPIRED","message":"Pair token has expired"}}}""",
                )
            },
        )

        val result = client.redeemShortCode("123456", "device-aaaa")

        assertTrue(result is BindingResult.Failure)
        assertEquals("绑定码已过期", (result as BindingResult.Failure).message)
    }

    @Test
    fun childProfileClientPutsNicknameWithDeviceToken() = runBlocking {
        var capturedMethod = ""
        var capturedUrl = ""
        var capturedBody = ""
        val client = ChildProfileClient(
            baseUrlProvider = { "https://happyword.cool/" },
            extraHeadersProvider = { mapOf("x-vercel-protection-bypass" to "secret") },
            transport = BindingHttpTransport { method, url, headers, body ->
                capturedMethod = method
                capturedUrl = url
                capturedBody = body
                assertEquals("Bearer device.jwt.token", headers["Authorization"])
                assertEquals("secret", headers["x-vercel-protection-bypass"])
                BindingHttpResponse(
                    200,
                    """{"profile_id":"child-1","family_id":"fam-1","nickname":"星星","avatar_emoji":"🦄","updated_at":"2026-05-12T00:00:00Z"}""",
                )
            },
        )

        val updated = client.updateProfile("device.jwt.token", "星星", "🦄")

        assertEquals("PUT", capturedMethod)
        assertEquals("https://happyword.cool/api/v1/child/profile", capturedUrl)
        assertEquals("""{"nickname":"星星","avatar_emoji":"🦄"}""", capturedBody)
        assertEquals("星星", updated.nickname)
        assertEquals("🦄", updated.avatarEmoji)
    }

    @Test
    fun wordStatsSyncClientPostsLearningStatsWithDeviceToken() = runBlocking {
        var capturedMethod = ""
        var capturedUrl = ""
        var capturedBody = ""
        val client = WordStatsSyncClient(
            baseUrlProvider = { "https://happyword.cool/" },
            extraHeadersProvider = { mapOf("x-vercel-protection-bypass" to "secret") },
            transport = BindingHttpTransport { method, url, headers, body ->
                capturedMethod = method
                capturedUrl = url
                capturedBody = body
                assertEquals("application/json", headers["Content-Type"])
                assertEquals("application/json", headers["Accept"])
                assertEquals("Bearer device.jwt.token", headers["Authorization"])
                assertEquals("secret", headers["x-vercel-protection-bypass"])
                BindingHttpResponse(
                    200,
                    """{"accepted":["fruit-apple"],"rejected":[],"server_pulls":[],"server_now_ms":2600}""",
                )
            },
        )

        val result = client.sync(
            deviceToken = "device.jwt.token",
            stats = listOf(WordLearningStat("fruit-forest", "fruit-apple", 2, 1, 1, 2000L)),
            syncedThroughMs = 1000L,
        )

        assertEquals("POST", capturedMethod)
        assertEquals("https://happyword.cool/api/v1/child/word-stats/sync", capturedUrl)
        assertEquals(
            """{"items":[{"word_id":"fruit-apple","seen_count":2,"correct_count":1,"wrong_count":1,"last_answered_ms":2000,"last_correct_ms":2000,"next_review_ms":0,"memory_state":"new","consecutive_correct":0,"consecutive_wrong":0,"mastery":0.5}],"synced_through_ms":1000}""",
            capturedBody,
        )
        assertEquals(WordStatsSyncStatus.Pushed, result.status)
        assertEquals(1, result.pushed)
        assertEquals(2600L, result.serverNowMs)
    }

    @Test
    fun wordStatsSyncClientOnlyUploadsDirtyStats() = runBlocking {
        var capturedBody = ""
        val client = WordStatsSyncClient(
            baseUrlProvider = { "https://happyword.cool" },
            transport = BindingHttpTransport { _, _, _, body ->
                capturedBody = body
                BindingHttpResponse(
                    200,
                    """{"accepted":[],"rejected":[],"server_pulls":[],"server_now_ms":2600}""",
                )
            },
        )

        val result = client.sync(
            deviceToken = "device.jwt.token",
            stats = listOf(
                WordLearningStat("fruit-forest", "fruit-old", 3, 3, 0, 999L),
                WordLearningStat("fruit-forest", "fruit-new", 1, 0, 1, 1200L),
            ),
            syncedThroughMs = 1000L,
        )

        assertFalse(capturedBody.contains("fruit-old"))
        assertTrue(capturedBody.contains("fruit-new"))
        assertEquals(WordStatsSyncStatus.NoChanges, result.status)
        assertEquals(2600L, result.serverNowMs)
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

        assertFalse(payload.contains("fruit-forest"))
        assertTrue(payload.contains("items"))
        assertTrue(payload.contains("fruit-apple"))
        assertTrue(payload.contains("synced_through_ms"))
        assertNotNull(payload)
    }
}
