package cool.happyword.wordmagic.core

enum class BackendEnv(val label: String, val defaultUrl: String) {
    Local("Local", "http://10.0.2.2:8123"),
    Staging("Staging", "https://happyword-staging.vercel.app"),
    Prod("Prod", "https://happyword.vercel.app"),
    Preview("Preview", ""),
}

data class PreviewTarget(
    val id: String,
    val label: String,
    val url: String,
)

data class BackendRouteState(
    val env: BackendEnv = BackendEnv.Staging,
    val selectedPreview: PreviewTarget? = null,
    val instrumentationOverrideUrl: String? = null,
)

class BackendURLProvider {
    fun resolve(state: BackendRouteState): String {
        state.instrumentationOverrideUrl?.takeIf { it.isNotBlank() }?.let { return it }
        if (state.env == BackendEnv.Preview) {
            state.selectedPreview?.url?.takeIf { it.startsWith("http") }?.let { return it }
            return BackendEnv.Staging.defaultUrl
        }
        return state.env.defaultUrl
    }
}

class BackendHeaderProvider {
    fun headers(state: BackendRouteState, bypassSecret: String): Map<String, String> {
        if (state.env != BackendEnv.Preview) return emptyMap()
        val trimmed = bypassSecret.trim()
        if (trimmed.isBlank()) return emptyMap()
        return mapOf("x-vercel-protection-bypass" to trimmed)
    }
}

class PreviewManifestClient {
    fun parse(json: String): List<PreviewTarget> {
        val regex = Regex("""\{[^}]*"id"\s*:\s*"([^"]+)"[^}]*"url"\s*:\s*"([^"]+)"[^}]*("label"\s*:\s*"([^"]+)")?[^}]*}""")
        return regex.findAll(json).mapNotNull { match ->
            val id = match.groupValues[1]
            val url = match.groupValues[2]
            val label = match.groupValues.getOrNull(4).orEmpty().ifBlank { id }
            if (id.isBlank() || !url.startsWith("http")) null else PreviewTarget(id, label, url)
        }.toList()
    }

    fun fixture(): List<PreviewTarget> = listOf(
        PreviewTarget("preview-main", "Preview Main", "https://happyword-preview-main.vercel.app"),
        PreviewTarget("preview-e2e", "Preview E2E", "https://happyword-preview-e2e.vercel.app"),
    )
}

class BypassSecretStore(private val store: StringKeyValueStore) {
    fun load(): String = store.getString(KEY).orEmpty()

    fun save(secret: String) {
        val trimmed = secret.trim()
        if (trimmed.isBlank()) store.remove(KEY) else store.putString(KEY, trimmed)
    }

    fun clear() {
        store.remove(KEY)
    }

    companion object {
        private const val KEY = "preview_bypass_secret"
    }
}

class DevMenuViewModel(
    private val manifestClient: PreviewManifestClient = PreviewManifestClient(),
    private val urlProvider: BackendURLProvider = BackendURLProvider(),
) {
    fun refreshManifest(previous: List<PreviewTarget>, fail: Boolean = false): List<PreviewTarget> {
        if (fail) return previous
        return manifestClient.fixture()
    }

    fun selectPreview(state: BackendRouteState, preview: PreviewTarget): BackendRouteState {
        return state.copy(env = BackendEnv.Preview, selectedPreview = preview)
    }

    fun routingSummary(state: BackendRouteState): String {
        return "${state.env.label}: ${urlProvider.resolve(state)}"
    }

    fun probe(state: BackendRouteState): String {
        return "OK ${urlProvider.resolve(state)}"
    }
}
