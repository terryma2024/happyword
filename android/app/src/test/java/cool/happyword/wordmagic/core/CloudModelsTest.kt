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
            baseUrlProvider = { "https://happyword.com.cn/" },
            extraHeadersProvider = { mapOf("X-Test-Header" to "secret") },
            transport = BindingHttpTransport { method, url, headers, body ->
                capturedMethod = method
                capturedUrl = url
                capturedBody = body
                assertEquals("application/json", headers["Content-Type"])
                assertEquals("application/json", headers["Accept"])
                assertEquals("secret", headers["X-Test-Header"])
                BindingHttpResponse(
                    200,
                    """{"binding_id":"bind-1","family_id":"fam-1","child_profile_id":"child-1","nickname":"宝贝","avatar_emoji":"🦁","device_token":"jwt.token.value"}""",
                )
            },
        )

        val result = client.redeemShortCode("123456", "device-aaaa")

        assertTrue(result is BindingResult.Success)
        assertEquals("POST", capturedMethod)
        assertEquals("https://happyword.com.cn/api/v1/public/pair/redeem", capturedUrl)
        assertEquals("""{"device_id":"device-aaaa","short_code":"123456"}""", capturedBody)
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
            baseUrlProvider = { "https://happyword.com.cn/" },
            extraHeadersProvider = { mapOf("X-Test-Header" to "secret") },
            transport = BindingHttpTransport { method, url, headers, body ->
                capturedMethod = method
                capturedUrl = url
                capturedBody = body
                assertEquals("Bearer device.jwt.token", headers["Authorization"])
                assertEquals("secret", headers["X-Test-Header"])
                BindingHttpResponse(
                    200,
                    """{"profile_id":"child-1","family_id":"fam-1","nickname":"星星","avatar_emoji":"🦄","updated_at":"2026-05-12T00:00:00Z"}""",
                )
            },
        )

        val updated = client.updateProfile("device.jwt.token", "fam-1", "星星", "🦄")

        assertEquals("PUT", capturedMethod)
        assertEquals("https://happyword.com.cn/api/v1/family/fam-1/profile", capturedUrl)
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
            baseUrlProvider = { "https://happyword.com.cn/" },
            extraHeadersProvider = { mapOf("X-Test-Header" to "secret") },
            transport = BindingHttpTransport { method, url, headers, body ->
                capturedMethod = method
                capturedUrl = url
                capturedBody = body
                assertEquals("application/json", headers["Content-Type"])
                assertEquals("application/json", headers["Accept"])
                assertEquals("Bearer device.jwt.token", headers["Authorization"])
                assertEquals("secret", headers["X-Test-Header"])
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
            familyId = "fam-sync-test",
        )

        assertEquals("POST", capturedMethod)
        assertEquals("https://happyword.com.cn/api/v1/family/fam-sync-test/word-stats/sync", capturedUrl)
        assertEquals(
            """{"items":[{"word_id":"fruit-apple","seen_count":2,"correct_count":1,"wrong_count":1,"last_answered_ms":2000,"last_correct_ms":2000,"next_review_ms":0,"memory_state":"new","consecutive_correct":0,"consecutive_wrong":0,"mastery":0.5}],"synced_through_ms":1000}""",
            capturedBody,
        )
        assertEquals(WordStatsSyncStatus.Pushed, result.status)
        assertEquals(1, result.pushed)
        assertEquals(2600L, result.serverNowMs)
    }

    @Test
    fun checkInSyncClientPostsCheckInsAndBonusTransactionsWithDeviceToken() = runBlocking {
        var capturedMethod = ""
        var capturedUrl = ""
        var capturedBody = ""
        val client = CheckInSyncClient(
            baseUrlProvider = { "https://happyword.com.cn/" },
            extraHeadersProvider = { mapOf("X-Test-Header" to "secret") },
            transport = BindingHttpTransport { method, url, headers, body ->
                capturedMethod = method
                capturedUrl = url
                capturedBody = body
                assertEquals("application/json", headers["Content-Type"])
                assertEquals("application/json", headers["Accept"])
                assertEquals("Bearer device.jwt.token", headers["Authorization"])
                assertEquals("secret", headers["X-Test-Header"])
                BindingHttpResponse(
                    200,
                    """{"checked_day_keys":["2026-05-01","2026-05-07"],"weekly_bonus_day_keys":["2026-05-07"],"coin_txns":[],"server_now_ms":2600}""",
                )
            },
        )

        val result = client.sync(
            deviceToken = "device.jwt.token",
            snapshot = CheckInSnapshot(
                checkedDayKeys = listOf("2026-05-01", "2026-05-07"),
                weeklyBonusDayKeys = listOf("2026-05-07"),
                lastSyncedAtMs = 1000L,
            ),
            familyId = "fam-sync-test",
        )

        assertEquals("POST", capturedMethod)
        assertEquals("https://happyword.com.cn/api/v1/family/fam-sync-test/checkins/sync", capturedUrl)
        assertEquals(
            """{"checked_day_keys":["2026-05-01","2026-05-07"],"weekly_bonus_day_keys":["2026-05-07"],"coin_txns":[{"txn_id":"checkin-weekly-bonus:2026-05-07","delta":50,"reason":"checkin-weekly-bonus:2026-05-07","created_at_ms":0}],"synced_through_ms":1000}""",
            capturedBody,
        )
        assertTrue(result.ok)
        assertEquals(listOf("2026-05-01", "2026-05-07"), result.checkedDayKeys)
        assertEquals(listOf("2026-05-07"), result.weeklyBonusDayKeys)
        assertEquals(2600L, result.serverNowMs)
    }

    @Test
    fun remoteGlobalPackClientFetchesPublicEndpointAndDecodesServerPayload() = runBlocking {
        var capturedMethod = ""
        var capturedUrl = ""
        val client = RemoteGlobalPackClient(
            baseUrlProvider = { "https://happyword.com.cn/" },
            extraHeadersProvider = { mapOf("X-Test-Header" to "secret") },
            transport = BindingHttpTransport { method, url, headers, body ->
                capturedMethod = method
                capturedUrl = url
                assertEquals("", body)
                assertEquals("application/json", headers["Accept"])
                assertEquals("secret", headers["X-Test-Header"])
                assertFalse(headers.containsKey("Authorization"))
                BindingHttpResponse(
                    200,
                    """
                    {
                      "schema_version": 5,
                      "merged_at": "2026-06-04T12:07:40.169556Z",
                      "packs": [
                        {
                          "pack_id": "gpk-demo",
                          "name": "二年级英语下册词汇-3",
                          "description": null,
                          "scene": {
                            "storyEn": "A robot shares a birthday in the forest.",
                            "storyZh": "机器人在森林里分享生日。",
                            "spellbookCoverUrl": "https://cdn.example/gpk-demo.png"
                          },
                          "version": 2,
                          "schema_version": 5,
                          "published_at": "2026-06-04T09:07:15.177000",
                          "words": [
                            {
                              "id": "word-party",
                              "word": "party",
                              "meaningZh": "聚会",
                              "difficulty": 2,
                              "exampleEn": "We have a party.",
                              "exampleZh": "我们举办聚会。"
                            }
                          ]
                        }
                      ]
                    }
                    """.trimIndent(),
                )
            },
        )

        val packs = client.sync()

        assertEquals("GET", capturedMethod)
        assertEquals("https://happyword.com.cn/api/v1/public/global-packs/latest.json", capturedUrl)
        assertEquals(1, packs.size)
        assertEquals("gpk-demo", packs.single().id)
        assertEquals(PackSource.Global, packs.single().source)
        assertEquals("二年级英语下册词汇-3", packs.single().nameEn)
        assertEquals("A robot shares a birthday in the forest.", packs.single().scene.storyEn)
        assertEquals("https://cdn.example/gpk-demo.png", packs.single().scene.spellbookCoverUrl)
        assertEquals("#FFFFFF", packs.single().scene.bgPrimary)
        assertEquals(2, packs.single().words.single().difficulty)
        assertEquals("We have a party.", packs.single().words.single().example?.en)
        assertNotNull(packs.single().publishedAtMs)
    }

    @Test
    fun remoteFamilyPackClientFetchesFamilyEndpointWithDeviceToken() = runBlocking {
        var capturedMethod = ""
        var capturedUrl = ""
        val credentials = CloudCredentials(
            deviceId = "device-1",
            deviceToken = "device.jwt.token",
            bindingId = "binding-1",
            childNickname = "宝贝",
            avatarEmoji = "🦁",
            familyLabel = "fam-sync-test",
        )
        val client = RemoteFamilyPackClient(
            baseUrlProvider = { "https://happyword.com.cn/" },
            transport = BindingHttpTransport { method, url, headers, body ->
                capturedMethod = method
                capturedUrl = url
                assertEquals("", body)
                assertEquals("application/json", headers["Accept"])
                assertEquals("Bearer device.jwt.token", headers["Authorization"])
                BindingHttpResponse(
                    200,
                    """
                    {
                      "schema_version": 5,
                      "family_id": "fam-sync-test",
                      "merged_at": "2026-06-04T12:07:40.169556Z",
                      "packs": [
                        {
                          "pack_id": "family-snacks",
                          "name": "Family Snacks",
                          "version": 1,
                          "schema_version": 5,
                          "published_at": "2026-06-04T09:07:15.177000",
                          "words": [
                            {
                              "id": "snack-cookie",
                              "word": "cookie",
                              "meaning_zh": "饼干",
                              "difficulty": 1
                            }
                          ]
                        }
                      ]
                    }
                    """.trimIndent(),
                )
            },
        )

        val packs = client.sync(credentials)

        assertEquals("GET", capturedMethod)
        assertEquals("https://happyword.com.cn/api/v1/family/fam-sync-test/family-packs/latest.json", capturedUrl)
        assertEquals(1, packs.size)
        assertEquals("family-snacks", packs.single().id)
        assertEquals(PackSource.Family, packs.single().source)
        assertEquals("饼干", packs.single().words.single().meaning)
    }

    @Test
    fun wordStatsSyncClientOnlyUploadsDirtyStats() = runBlocking {
        var capturedBody = ""
        val client = WordStatsSyncClient(
            baseUrlProvider = { "https://happyword.com.cn" },
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
    fun syncCoordinatorKeepsOfflineResultWhenClientsFail() = runBlocking {
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
