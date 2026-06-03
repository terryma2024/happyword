package cool.happyword.wordmagic.core

import java.net.HttpURLConnection
import java.net.URL
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

enum class BackendEnv(val label: String, val defaultUrl: String) {
    Local("Local", "http://10.0.2.2:8000"),
    Staging("Staging", "https://happyword.com.cn"),
    Prod("Production", ""),
    Preview("Preview", ""),
}

data class PreviewTarget(
    val id: String,
    val label: String,
    val url: String,
    val footer: String = id,
)

data class BackendRouteState(
    val env: BackendEnv = BackendEnv.Staging,
    val selectedPreview: PreviewTarget? = null,
    val instrumentationOverrideUrl: String? = null,
)

data class ProbeResult(
    val ok: Boolean,
    val message: String,
)

class BackendURLProvider {
    fun resolve(state: BackendRouteState): String {
        state.instrumentationOverrideUrl?.takeIf { it.isNotBlank() }?.let { return it }
        if (state.env == BackendEnv.Preview) {
            state.selectedPreview?.url?.takeIf { it.startsWith("http") }?.let { return it }
            return BackendEnv.Staging.defaultUrl
        }
        return state.env.defaultUrl.ifBlank { BackendEnv.Staging.defaultUrl }
    }

    fun parentFamilyLoginPageUrl(state: BackendRouteState): String {
        val base = resolve(state).trim().trimEnd('/')
        return "$base/family/login"
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

class PreviewManifestClient(
    private val fetcher: suspend (String) -> String? = ::fetchUrl,
    private val nowMillis: () -> Long = System::currentTimeMillis,
) {
    private var cache: CacheEntry? = null

    fun parse(json: String): List<PreviewTarget> {
        return runCatching {
            val schemaVersion = Regex(""""schema_version"\s*:\s*(\d+)""").find(json)?.groupValues?.get(1)?.toIntOrNull()
            if (schemaVersion != SCHEMA_VERSION) return emptyList()
            Regex("""\{[^\{\}]*\}""").findAll(json).mapNotNull { match ->
                val row = match.value
                val url = row.stringField("url") ?: return@mapNotNull null
                if (!isValidPreviewUrl(url)) return@mapNotNull null
                val pr = row.intField("pr") ?: row.intField("number")
                val id = row.stringField("id") ?: pr?.let { "pr-$it" } ?: return@mapNotNull null
                val label = row.stringField("label") ?: row.stringField("title") ?: row.stringField("branch") ?: id
                val sha = row.stringField("head_sha").orEmpty().take(7)
                val footer = when {
                    pr != null && sha.isNotBlank() -> "#$pr($sha)"
                    pr != null -> "#$pr"
                    else -> id
                }
                PreviewTarget(id = id, label = label.replace(Regex("""[\r\n]+"""), " ").take(80), url = url, footer = footer)
            }.toList()
        }.getOrDefault(emptyList())
    }

    suspend fun fetch(force: Boolean): List<PreviewTarget>? = withContext(Dispatchers.IO) {
        val cached = cache
        val now = nowMillis()
        if (!force && cached != null && now - cached.fetchedAtMillis < CACHE_TTL_MS) {
            return@withContext cached.previews
        }
        val json = fetcher(PREVIEW_MANIFEST_JSON_URL) ?: return@withContext cached?.previews
        val parsed = parse(json).takeIf { it.isNotEmpty() } ?: return@withContext cached?.previews
        cache = CacheEntry(fetchedAtMillis = now, previews = parsed)
        parsed
    }

    fun cached(): List<PreviewTarget>? = cache?.previews

    private data class CacheEntry(
        val fetchedAtMillis: Long,
        val previews: List<PreviewTarget>,
    )

    companion object {
        const val PREVIEW_MANIFEST_JSON_URL = "https://happyword.com.cn/api/v1/public/preview-urls.json"
        private const val SCHEMA_VERSION = 1
        private const val CACHE_TTL_MS = 5 * 60 * 1000L

        private fun isValidPreviewUrl(url: String): Boolean =
            url.startsWith("https://") && url.endsWith(".vercel.app")

        private suspend fun fetchUrl(url: String): String? {
            val connection = (URL(url).openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"
                connectTimeout = 5_000
                readTimeout = 5_000
                setRequestProperty("Accept", "application/json")
            }
            return try {
                if (connection.responseCode != 200) return null
                connection.inputStream.bufferedReader().use { reader -> reader.readText() }
            } catch (_: Exception) {
                null
            } finally {
                connection.disconnect()
            }
        }
    }

    fun fixture(): List<PreviewTarget> = listOf(
        PreviewTarget(
            "preview-main",
            "fix(harmony): stabilize UI suite with question type controls",
            "https://happyword-preview-main.vercel.app",
            "#65(24cd43a)",
        ),
        PreviewTarget(
            "preview-e2e",
            "feat(server): V0.8.2 system admin console",
            "https://happyword-preview-e2e.vercel.app",
            "#61(a1211b8)",
        ),
    )

    private fun String.stringField(name: String): String? =
        Regex(""""$name"\s*:\s*"([^"]*)"""").find(this)?.groupValues?.get(1)?.takeIf { it.isNotBlank() }

    private fun String.intField(name: String): Int? =
        Regex(""""$name"\s*:\s*(\d+)""").find(this)?.groupValues?.get(1)?.toIntOrNull()
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
    fun cachedManifest(): List<PreviewTarget>? = manifestClient.cached()

    fun fallbackManifest(): List<PreviewTarget> = emptyList()

    suspend fun refreshManifest(previous: List<PreviewTarget>, force: Boolean, fail: Boolean = false): List<PreviewTarget> {
        if (fail) return previous
        return manifestClient.fetch(force) ?: previous
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

    suspend fun probeHealth(state: BackendRouteState, bypassSecret: String): ProbeResult = withContext(Dispatchers.IO) {
        val baseUrl = urlProvider.resolve(state)
        val fullUrl = "${baseUrl.trimEnd('/')}/api/v1/public/health"
        val connection = (URL(fullUrl).openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = 10_000
            readTimeout = 10_000
            BackendHeaderProvider().headers(state, bypassSecret).forEach { (key, value) ->
                setRequestProperty(key, value)
            }
        }
        try {
            val code = connection.responseCode
            ProbeResult(ok = code == 200, message = "$fullUrl -> HTTP $code")
        } catch (err: Exception) {
            ProbeResult(ok = false, message = "$fullUrl -> unreachable (${err.message ?: err.javaClass.simpleName})")
        } finally {
            connection.disconnect()
        }
    }
}
