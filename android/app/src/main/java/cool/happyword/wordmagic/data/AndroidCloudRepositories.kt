package cool.happyword.wordmagic.data

import android.content.Context
import cool.happyword.wordmagic.core.CloudCredentials
import cool.happyword.wordmagic.core.CloudCredentialsStore
import cool.happyword.wordmagic.core.DeviceIdProvider
import cool.happyword.wordmagic.core.PackSource
import cool.happyword.wordmagic.core.StringKeyValueStore
import cool.happyword.wordmagic.core.WordPack
import java.io.File

class AndroidCloudRepositories(context: Context) {
    private val appContext = context.applicationContext
    private val prefs = appContext.getSharedPreferences("wordmagic-cloud", Context.MODE_PRIVATE)
    private val prefsStore = SharedPrefsStringStore(prefs)
    private val tokenStore = FileStringStore(File(appContext.filesDir, "cloud_device_token.secure"))

    val deviceIdProvider: DeviceIdProvider = DeviceIdProvider(prefsStore)
    val credentialsStore: CloudCredentialsStore = CloudCredentialsStore(prefsStore, tokenStore)

    fun loadCredentials(): CloudCredentials? = credentialsStore.load()

    fun saveCredentials(credentials: CloudCredentials) {
        credentialsStore.save(credentials)
    }

    fun clearCredentials() {
        credentialsStore.clear()
    }

    fun loadGlobalPacks(): List<WordPack> = PackCacheCodec.decode(prefs.getString("globalPacks", "").orEmpty(), PackSource.Global)

    fun loadFamilyPacks(): List<WordPack> = PackCacheCodec.decode(prefs.getString("familyPacks", "").orEmpty(), PackSource.Family)

    fun saveGlobalPacks(packs: List<WordPack>) {
        prefs.edit().putString("globalPacks", PackCacheCodec.encode(packs)).apply()
    }

    fun saveFamilyPacks(packs: List<WordPack>) {
        prefs.edit().putString("familyPacks", PackCacheCodec.encode(packs)).apply()
    }

    fun loadSyncStatus(): String = prefs.getString("syncStatus", "尚未同步").orEmpty()

    fun saveSyncStatus(value: String) {
        prefs.edit().putString("syncStatus", value).apply()
    }

    fun loadLearningSyncStatus(): String = prefs.getString("learningSyncStatus", "").orEmpty()

    fun saveLearningSyncStatus(value: String) {
        prefs.edit().putString("learningSyncStatus", value).apply()
    }

    fun loadLearningSyncCheckpointMs(): Long =
        prefs.getString("learningSyncCheckpointMs", "0").orEmpty().toLongOrNull() ?: 0L

    fun saveLearningSyncCheckpointMs(value: Long) {
        prefs.edit().putString("learningSyncCheckpointMs", value.coerceAtLeast(0L).toString()).apply()
    }

    fun resetForBackendSwitch() {
        clearCredentials()
        prefs.edit()
            .remove("globalPacks")
            .remove("familyPacks")
            .remove("learningSyncStatus")
            .putString("learningSyncCheckpointMs", "0")
            .putString("syncStatus", "尚未同步")
            .apply()
    }

}

private class SharedPrefsStringStore(
    private val prefs: android.content.SharedPreferences,
) : StringKeyValueStore {
    override fun getString(key: String): String? = prefs.getString(key, null)

    override fun putString(key: String, value: String) {
        prefs.edit().putString(key, value).apply()
    }

    override fun remove(key: String) {
        prefs.edit().remove(key).apply()
    }
}

private class FileStringStore(
    private val file: File,
) : StringKeyValueStore {
    override fun getString(key: String): String? {
        if (key != "device_token" || !file.exists()) return null
        return file.readText()
    }

    override fun putString(key: String, value: String) {
        if (key != "device_token") return
        file.parentFile?.mkdirs()
        file.writeText(value)
    }

    override fun remove(key: String) {
        if (key == "device_token" && file.exists()) file.delete()
    }
}
