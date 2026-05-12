package cool.happyword.wordmagic.core

import java.util.UUID

interface StringKeyValueStore {
    fun getString(key: String): String?
    fun putString(key: String, value: String)
    fun remove(key: String)
}

class MemoryStringKeyValueStore : StringKeyValueStore {
    private val values = linkedMapOf<String, String>()

    override fun getString(key: String): String? = values[key]

    override fun putString(key: String, value: String) {
        values[key] = value
    }

    override fun remove(key: String) {
        values.remove(key)
    }

    fun snapshot(): Map<String, String> = values.toMap()
}

class DeviceIdProvider(
    private val store: StringKeyValueStore,
    private val uuidFactory: () -> String = { UUID.randomUUID().toString() },
) {
    fun getOrCreate(): String {
        val existing = store.getString(KEY)
        if (!existing.isNullOrBlank()) return existing
        val generated = uuidFactory()
        store.putString(KEY, generated)
        return generated
    }

    companion object {
        private const val KEY = "device_id"
    }
}

data class CloudCredentials(
    val deviceId: String,
    val deviceToken: String,
    val bindingId: String,
    val childNickname: String,
    val avatarEmoji: String,
    val familyLabel: String,
)

class CloudCredentialsStore(
    private val labelStore: StringKeyValueStore,
    private val tokenStore: StringKeyValueStore,
) {
    fun load(): CloudCredentials? {
        val token = tokenStore.getString(TOKEN_KEY).orEmpty()
        if (token.isBlank()) return null
        val deviceId = labelStore.getString("device_id").orEmpty()
        val bindingId = labelStore.getString("binding_id").orEmpty()
        if (deviceId.isBlank() || bindingId.isBlank()) return null
        return CloudCredentials(
            deviceId = deviceId,
            deviceToken = token,
            bindingId = bindingId,
            childNickname = labelStore.getString("child_nickname").orEmpty().ifBlank { "小明测试" },
            avatarEmoji = labelStore.getString("avatar_emoji").orEmpty().ifBlank { "🦁" },
            familyLabel = labelStore.getString("family_label").orEmpty().ifBlank { "家庭账号" },
        )
    }

    fun save(credentials: CloudCredentials) {
        labelStore.putString("device_id", credentials.deviceId)
        labelStore.putString("binding_id", credentials.bindingId)
        labelStore.putString("child_nickname", credentials.childNickname)
        labelStore.putString("avatar_emoji", credentials.avatarEmoji)
        labelStore.putString("family_label", credentials.familyLabel)
        tokenStore.putString(TOKEN_KEY, credentials.deviceToken)
    }

    fun clear() {
        listOf("device_id", "binding_id", "child_nickname", "avatar_emoji", "family_label").forEach(labelStore::remove)
        tokenStore.remove(TOKEN_KEY)
    }

    companion object {
        private const val TOKEN_KEY = "device_token"
    }
}

sealed class BindingResult {
    data class Success(val credentials: CloudCredentials) : BindingResult()
    data class Failure(val message: String) : BindingResult()
}

class FixtureDeviceBindingClient {
    fun redeemShortCode(shortCode: String, deviceId: String): BindingResult {
        val normalized = shortCode.trim().uppercase()
        if (normalized.length < 4) {
            return BindingResult.Failure("请输入有效绑定码")
        }
        if (normalized == "EXPIRED") {
            return BindingResult.Failure("绑定码已过期")
        }
        return BindingResult.Success(
            CloudCredentials(
                deviceId = deviceId,
                deviceToken = "fixture-device-token-$normalized",
                bindingId = "binding-$normalized",
                childNickname = "小明测试46373",
                avatarEmoji = "🦁",
                familyLabel = "HappyWord Family",
            ),
        )
    }
}

data class CloudPackSyncResult(
    val globalPacks: List<WordPack>,
    val familyPacks: List<WordPack>,
    val statusMessage: String,
    val lastSyncAtMs: Long,
)

class FixtureGlobalPackClient(private val fail: Boolean = false) {
    fun sync(): List<WordPack> {
        if (fail) error("global pack sync failed")
        return listOf(
            BuiltinPacks.all.first { it.id == "ocean-realm" }.copy(
                id = "global-colors",
                nameEn = "Color Harbor",
                nameZh = "颜色港湾",
                source = PackSource.Global,
                version = 1,
                publishedAtMs = 2_000L,
                words = listOf(
                    WordEntry("color-red", "red", "红色"),
                    WordEntry("color-blue", "blue", "蓝色"),
                    WordEntry("color-green", "green", "绿色"),
                ),
            ),
        )
    }
}

class FixtureFamilyPackClient(private val fail: Boolean = false) {
    fun sync(credentials: CloudCredentials?): List<WordPack> {
        if (fail) error("family pack sync failed")
        if (credentials == null) return emptyList()
        return listOf(
            BuiltinPacks.all.first { it.id == "home-cottage" }.copy(
                id = "family-space",
                nameEn = "Family Space",
                nameZh = "家庭太空",
                source = PackSource.Family,
                version = 1,
                publishedAtMs = 3_000L,
                words = listOf(
                    WordEntry("space-moon", "moon", "月亮"),
                    WordEntry("space-star", "star", "星星"),
                    WordEntry("space-sun", "sun", "太阳"),
                ),
            ),
        )
    }
}

open class WordStatsSyncClient {
    open fun buildPayload(stats: List<WordLearningStat>, syncedThroughMs: Long): String {
        val rows = stats.joinToString(",") { stat ->
            """{"pack_id":"${stat.packId}","word_id":"${stat.wordId}","seen":${stat.seenCount},"correct":${stat.correctCount},"wrong":${stat.wrongCount},"last_seen_at_ms":${stat.lastSeenAtMs}}"""
        }
        return """{"synced_through_ms":$syncedThroughMs,"stats":[$rows]}"""
    }
}

class CloudSyncCoordinator(
    private val globalClient: FixtureGlobalPackClient = FixtureGlobalPackClient(),
    private val familyClient: FixtureFamilyPackClient = FixtureFamilyPackClient(),
    private val statsClient: WordStatsSyncClient = WordStatsSyncClient(),
    private val clockMs: () -> Long = { System.currentTimeMillis() },
) {
    fun syncPacks(credentials: CloudCredentials?): CloudPackSyncResult {
        val global = runCatching { globalClient.sync() }.getOrElse { emptyList() }
        val family = runCatching { familyClient.sync(credentials) }.getOrElse { emptyList() }
        val status = when {
            global.isNotEmpty() && family.isNotEmpty() -> "云端词包同步成功"
            global.isNotEmpty() -> "官方词包同步成功"
            family.isNotEmpty() -> "家庭词包同步成功"
            else -> "离线模式：保留本地词包"
        }
        return CloudPackSyncResult(global, family, status, clockMs())
    }

    fun syncStats(stats: List<WordLearningStat>, syncedThroughMs: Long): String {
        return runCatching { statsClient.buildPayload(stats, syncedThroughMs) }
            .getOrElse { """{"synced_through_ms":$syncedThroughMs,"stats":[]}""" }
    }
}
