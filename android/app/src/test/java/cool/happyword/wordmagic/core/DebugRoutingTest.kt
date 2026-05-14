package cool.happyword.wordmagic.core

import cool.happyword.wordmagic.app.BuildInfo
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlinx.coroutines.runBlocking

class DebugRoutingTest {
    @Test
    fun urlProviderUsesOverrideThenPreviewThenEnvironment() {
        val provider = BackendURLProvider()
        val preview = PreviewTarget("p1", "P1", "https://preview.example.com")

        assertEquals("http://127.0.0.1:8123", provider.resolve(BackendRouteState(instrumentationOverrideUrl = "http://127.0.0.1:8123")))
        assertEquals("http://10.0.2.2:8000", provider.resolve(BackendRouteState(env = BackendEnv.Local)))
        assertEquals("https://preview.example.com", provider.resolve(BackendRouteState(env = BackendEnv.Preview, selectedPreview = preview)))
        assertEquals("https://happyword.cool", provider.resolve(BackendRouteState(env = BackendEnv.Staging)))
    }

    @Test
    fun bypassHeaderOnlyAppliesToPreview() {
        val provider = BackendHeaderProvider()

        assertTrue(provider.headers(BackendRouteState(env = BackendEnv.Staging), "secret").isEmpty())
        assertEquals("secret", provider.headers(BackendRouteState(env = BackendEnv.Preview), " secret ")["x-vercel-protection-bypass"])
    }

    @Test
    fun previewManifestRejectsInvalidUrls() {
        val parsed = PreviewManifestClient().parse(
            """{"schema_version":1,"previews":[{"id":"ok","url":"https://ok.example.com"},{"id":"bad","url":"ftp://bad"}]}""",
        )

        assertTrue(parsed.isEmpty())
    }

    @Test
    fun previewManifestParsesHarmonyManifestRows() {
        val parsed = PreviewManifestClient().parse(
            """{"schema_version":1,"previews":[{"pr":65,"title":"fix(harmony): stabilize UI suite","branch":"codex/dev","url":"https://happyword-git-dev.vercel.app","author":"codex","head_sha":"24cd43abcdef","updated_at":"2026-05-12T00:00:00Z"}]}""",
        )

        assertEquals("pr-65", parsed.single().id)
        assertEquals("fix(harmony): stabilize UI suite", parsed.single().label)
        assertEquals("#65(24cd43a)", parsed.single().footer)
    }

    @Test
    fun refreshManifestUsesHarmonyStableUrlAndForceBypassesCache() = runBlocking {
        var now = 1_000L
        val requests = mutableListOf<String>()
        val responses = mutableListOf(
            """{"schema_version":1,"previews":[{"pr":65,"title":"First","branch":"codex/first","url":"https://happyword-git-first.vercel.app","author":"codex","head_sha":"1111111aaaa","updated_at":"2026-05-12T00:00:00Z"}]}""",
            """{"schema_version":1,"previews":[{"pr":66,"title":"Second","branch":"codex/second","url":"https://happyword-git-second.vercel.app","author":"codex","head_sha":"2222222bbbb","updated_at":"2026-05-12T00:01:00Z"}]}""",
        )
        val vm = DevMenuViewModel(
            PreviewManifestClient(
                fetcher = { url ->
                    requests += url
                    responses.removeAt(0)
                },
                nowMillis = { now },
            ),
        )

        val first = vm.refreshManifest(emptyList(), force = false)
        now += 1_000L
        val cached = vm.refreshManifest(first, force = false)
        val forced = vm.refreshManifest(cached, force = true)

        assertEquals(listOf(PreviewManifestClient.PREVIEW_MANIFEST_JSON_URL, PreviewManifestClient.PREVIEW_MANIFEST_JSON_URL), requests)
        assertEquals("#65(1111111)", first.single().footer)
        assertEquals("#65(1111111)", cached.single().footer)
        assertEquals("#66(2222222)", forced.single().footer)
    }

    @Test
    fun devMenuDefaultManifestDoesNotIncludeHistoricalPreviews() = runBlocking {
        val vm = DevMenuViewModel(PreviewManifestClient(fetcher = { null }))

        assertTrue(vm.fallbackManifest().isEmpty())
        assertTrue(vm.refreshManifest(emptyList(), force = false).isEmpty())
    }

    @Test
    fun bypassSecretStoreSavesTrimsAndClears() {
        val store = BypassSecretStore(MemoryStringKeyValueStore())

        store.save(" token ")
        assertEquals("token", store.load())
        store.clear()
        assertEquals("", store.load())
    }

    @Test
    fun versionTripleTapFiresOnThirdTapWithinWindow() {
        val t = VersionTripleTap(1000L)
        assertFalse(t.onTap(1000L))
        assertFalse(t.onTap(1100L))
        assertTrue(t.onTap(1200L))
        assertFalse(t.onTap(1300L))
    }

    @Test
    fun versionTripleTapResetsAfterWindow() {
        val t = VersionTripleTap(500L)
        assertFalse(t.onTap(0L))
        assertFalse(t.onTap(100L))
        assertTrue(t.onTap(200L))
        // After fire, lastTapMs is 0; 900-0 > window → new sequence starts at 900.
        assertFalse(t.onTap(900L))
        assertFalse(t.onTap(1000L))
        assertTrue(t.onTap(1100L))
        assertFalse(t.onTap(1200L))
    }

    @Test
    fun formatBuildTimestampMatchesMinutePrecision() {
        val cal = java.util.Calendar.getInstance(java.util.Locale.US)
        cal.set(2026, java.util.Calendar.MAY, 13, 14, 7, 0)
        cal.set(java.util.Calendar.MILLISECOND, 0)
        assertEquals("2605131407", BuildInfo.formatBuildTimestamp(cal.timeInMillis))
    }

    @Test
    fun devMenuViewModelRefreshesAndSummarizesPreview() {
        val vm = DevMenuViewModel(
            PreviewManifestClient(
                fetcher = {
                    """{"schema_version":1,"previews":[{"pr":65,"title":"Preview","branch":"codex/dev","url":"https://happyword-git-dev.vercel.app","head_sha":"24cd43abcdef"}]}"""
                },
            ),
        )
        val preview = runBlocking { vm.refreshManifest(emptyList(), force = false) }.first()
        val state = vm.selectPreview(BackendRouteState(), preview)

        assertEquals(BackendEnv.Preview, state.env)
        assertTrue(vm.routingSummary(state).contains(preview.url))
        assertTrue(vm.probe(state).startsWith("OK"))
    }
}
