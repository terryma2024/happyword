package cool.happyword.wordmagic.data

import android.content.Context
import cool.happyword.wordmagic.core.BackendEnv
import cool.happyword.wordmagic.core.BackendRouteState
import cool.happyword.wordmagic.core.PreviewTarget
import cool.happyword.wordmagic.core.StringKeyValueStore

class AndroidDebugRoutingRepository(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences("wordmagic-debug-routing", Context.MODE_PRIVATE)
    private val store = object : StringKeyValueStore {
        override fun getString(key: String): String? = prefs.getString(key, null)
        override fun putString(key: String, value: String) {
            prefs.edit().putString(key, value).apply()
        }
        override fun remove(key: String) {
            prefs.edit().remove(key).apply()
        }
    }
    fun loadRouteState(): BackendRouteState {
        val env = runCatching { BackendEnv.valueOf(prefs.getString("env", BackendEnv.Staging.name).orEmpty()) }.getOrDefault(BackendEnv.Staging)
        val previewId = prefs.getString("previewId", null)
        val previewLabel = prefs.getString("previewLabel", null)
        val previewUrl = prefs.getString("previewUrl", null)
        val preview = if (!previewId.isNullOrBlank() && !previewUrl.isNullOrBlank()) {
            PreviewTarget(previewId, previewLabel ?: previewId, previewUrl)
        } else {
            null
        }
        return BackendRouteState(
            env = env,
            selectedPreview = preview,
            instrumentationOverrideUrl = prefs.getString("instrumentationOverrideUrl", null),
        )
    }

    fun saveRouteState(state: BackendRouteState) {
        prefs.edit()
            .putString("env", state.env.name)
            .putString("previewId", state.selectedPreview?.id)
            .putString("previewLabel", state.selectedPreview?.label)
            .putString("previewUrl", state.selectedPreview?.url)
            .putString("instrumentationOverrideUrl", state.instrumentationOverrideUrl)
            .apply()
    }

    fun clearRouteState() {
        prefs.edit().clear().apply()
    }
}
