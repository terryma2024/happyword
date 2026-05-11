package cool.happyword.wordmagic.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class DebugRoutingTest {
    @Test
    fun urlProviderUsesOverrideThenPreviewThenEnvironment() {
        val provider = BackendURLProvider()
        val preview = PreviewTarget("p1", "P1", "https://preview.example.com")

        assertEquals("http://127.0.0.1:8123", provider.resolve(BackendRouteState(instrumentationOverrideUrl = "http://127.0.0.1:8123")))
        assertEquals("https://preview.example.com", provider.resolve(BackendRouteState(env = BackendEnv.Preview, selectedPreview = preview)))
        assertEquals(BackendEnv.Staging.defaultUrl, provider.resolve(BackendRouteState(env = BackendEnv.Staging)))
    }

    @Test
    fun bypassHeaderOnlyAppliesToPreview() {
        val provider = BackendHeaderProvider()

        assertTrue(provider.headers(BackendRouteState(env = BackendEnv.Staging), "secret").isEmpty())
        assertEquals("secret", provider.headers(BackendRouteState(env = BackendEnv.Preview), " secret ")["x-vercel-protection-bypass"])
    }

    @Test
    fun previewManifestRejectsInvalidUrls() {
        val parsed = PreviewManifestClient().parse("""{"previews":[{"id":"ok","url":"https://ok.example.com"},{"id":"bad","url":"ftp://bad"}]}""")

        assertEquals(listOf("ok"), parsed.map { it.id })
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
    fun devMenuViewModelRefreshesAndSummarizesPreview() {
        val vm = DevMenuViewModel()
        val preview = vm.refreshManifest(emptyList()).first()
        val state = vm.selectPreview(BackendRouteState(), preview)

        assertEquals(BackendEnv.Preview, state.env)
        assertTrue(vm.routingSummary(state).contains(preview.url))
        assertTrue(vm.probe(state).startsWith("OK"))
    }
}
