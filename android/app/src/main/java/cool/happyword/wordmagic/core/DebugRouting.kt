package cool.happyword.wordmagic.core

import android.util.Log
import java.net.HttpURLConnection
import java.net.URL

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
    val deploymentUrl: String? = null,
    val deploymentId: String? = null,
    val headSha: String? = null,
)

data class BackendRouteState(
    val env: BackendEnv = BackendEnv.Staging,
    val selectedPreview: PreviewTarget? = null,
    val instrumentationOverrideUrl: String? = null,
    val debugSessionId: String = "",
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
    fun headers(state: BackendRouteState, bypassSecret: String, debugSessionId: String = state.debugSessionId): Map<String, String> {
        if (state.env != BackendEnv.Preview) return emptyMap()
        val out = mutableMapOf<String, String>()
        val trimmed = bypassSecret.trim()
        if (trimmed.isNotBlank()) out["x-vercel-protection-bypass"] = trimmed
        val session = debugSessionId.trim()
        if (session.isNotBlank()) out["x-hw-debug-session"] = session
        return out
    }
}

class PreviewManifestClient {
    fun parse(json: String): List<PreviewTarget> {
        val objectRegex = Regex("""\{[^{}]*}""")
        return objectRegex.findAll(json).mapNotNull { match ->
            val row = match.value
            val branch = field(row, "branch")
            val url = field(row, "branch_url").ifBlank { field(row, "url") }
            val label = field(row, "title").ifBlank { branch }
            if (branch.isBlank() || !url.startsWith("https://")) {
                null
            } else {
                PreviewTarget(
                    id = branch,
                    label = label,
                    url = url,
                    deploymentUrl = field(row, "deployment_url").ifBlank { null },
                    deploymentId = field(row, "deployment_id").ifBlank { null },
                    headSha = field(row, "head_sha").ifBlank { null },
                )
            }
        }.toList()
    }

    private fun field(row: String, name: String): String {
        val regex = Regex(""""$name"\s*:\s*"([^"]*)"""")
        return regex.find(row)?.groupValues?.getOrNull(1).orEmpty()
    }

    fun fetch(url: String = "https://happyword.cool/api/v1/preview-urls.json"): List<PreviewTarget> {
        val conn = URL(url).openConnection() as HttpURLConnection
        conn.requestMethod = "GET"
        conn.connectTimeout = 10_000
        conn.readTimeout = 10_000
        return try {
            if (conn.responseCode != 200) emptyList() else parse(conn.inputStream.bufferedReader().readText())
        } catch (_: Exception) {
            emptyList()
        } finally {
            conn.disconnect()
        }
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
        return manifestClient.fetch().ifEmpty { previous.ifEmpty { manifestClient.fixture() } }
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

class DebugNetworkClient(
    private val urlProvider: BackendURLProvider = BackendURLProvider(),
    private val headerProvider: BackendHeaderProvider = BackendHeaderProvider(),
) {
    fun headers(state: BackendRouteState, bypassSecret: String): Map<String, String> =
        headerProvider.headers(state, bypassSecret)

    fun logRequest(method: String, state: BackendRouteState, path: String, bypassSecret: String): String {
        val url = "${urlProvider.resolve(state).trimEnd('/')}/$path".replace("//api", "/api")
        val headers = headerProvider.headers(state, bypassSecret)
        if (headers.containsKey("x-hw-debug-session")) {
            Log.i("HW_NET_DEBUG", "$method $url")
        }
        return url
    }
}
