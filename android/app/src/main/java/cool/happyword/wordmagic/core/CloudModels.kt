package cool.happyword.wordmagic.core

import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

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
    val childProfileId: String = "",
    val pairedAtMs: Long = 0L,
    val deviceIdSource: String = "preferences_fallback",
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
            childProfileId = labelStore.getString("child_profile_id").orEmpty(),
            pairedAtMs = labelStore.getString("paired_at_ms").orEmpty().toLongOrNull() ?: 0L,
            deviceIdSource = labelStore.getString("device_id_source").orEmpty().ifBlank { "preferences_fallback" },
        )
    }

    fun save(credentials: CloudCredentials) {
        labelStore.putString("device_id", credentials.deviceId)
        labelStore.putString("binding_id", credentials.bindingId)
        labelStore.putString("child_nickname", credentials.childNickname)
        labelStore.putString("avatar_emoji", credentials.avatarEmoji)
        labelStore.putString("family_label", credentials.familyLabel)
        labelStore.putString("child_profile_id", credentials.childProfileId)
        labelStore.putString("paired_at_ms", credentials.pairedAtMs.toString())
        labelStore.putString("device_id_source", credentials.deviceIdSource)
        tokenStore.putString(TOKEN_KEY, credentials.deviceToken)
    }

    fun clear() {
        listOf(
            "device_id",
            "binding_id",
            "child_nickname",
            "avatar_emoji",
            "family_label",
            "child_profile_id",
            "paired_at_ms",
            "device_id_source",
        ).forEach(labelStore::remove)
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
        if (normalized == "EXPIRED" || normalized == "000001") {
            return BindingResult.Failure(
                if (normalized == "EXPIRED") "绑定码已过期" else "绑定码无效",
            )
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

    fun redeemToken(token: String, deviceId: String): BindingResult {
        val normalized = token.trim()
        if (normalized.length < 4) {
            return BindingResult.Failure("二维码或短码无效")
        }
        if (normalized == "expired-token") {
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

data class BindingHttpResponse(val status: Int, val body: String)

fun interface BindingHttpTransport {
    suspend fun requestJson(method: String, url: String, headers: Map<String, String>, body: String): BindingHttpResponse

    suspend fun getJson(url: String, headers: Map<String, String>): BindingHttpResponse =
        requestJson("GET", url, headers, "")

    suspend fun postJson(url: String, headers: Map<String, String>, body: String): BindingHttpResponse =
        requestJson("POST", url, headers, body)

    suspend fun putJson(url: String, headers: Map<String, String>, body: String): BindingHttpResponse =
        requestJson("PUT", url, headers, body)
}

class UrlConnectionBindingHttpTransport : BindingHttpTransport {
    override suspend fun requestJson(method: String, url: String, headers: Map<String, String>, body: String): BindingHttpResponse =
        withContext(Dispatchers.IO) {
            val connection = (URL(url).openConnection() as HttpURLConnection).apply {
                requestMethod = method
                connectTimeout = 10_000
                readTimeout = 10_000
                doOutput = body.isNotEmpty()
                headers.forEach { (key, value) -> setRequestProperty(key, value) }
            }
            try {
                if (body.isNotEmpty()) {
                    connection.outputStream.use { stream ->
                        stream.write(body.toByteArray(Charsets.UTF_8))
                    }
                }
                val status = connection.responseCode
                val responseBody = runCatching {
                    val stream = if (status in 200..299) connection.inputStream else connection.errorStream
                    stream?.bufferedReader(Charsets.UTF_8)?.use { it.readText() }.orEmpty()
                }.getOrDefault("")
                BindingHttpResponse(status, responseBody)
            } finally {
                connection.disconnect()
            }
        }
}

class DeviceBindingClient(
    private val baseUrlProvider: () -> String,
    private val extraHeadersProvider: () -> Map<String, String> = { emptyMap() },
    private val transport: BindingHttpTransport = UrlConnectionBindingHttpTransport(),
    private val clockMs: () -> Long = System::currentTimeMillis,
) {
    suspend fun redeemShortCode(shortCode: String, deviceId: String): BindingResult =
        redeemPair(deviceId = deviceId, token = "", shortCode = shortCode)

    suspend fun redeemToken(token: String, deviceId: String): BindingResult =
        redeemPair(deviceId = deviceId, token = token, shortCode = "")

    private suspend fun redeemPair(deviceId: String, token: String, shortCode: String): BindingResult {
        val normalizedCode = shortCode.trim()
        val normalizedToken = token.trim()
        if (normalizedCode.isNotEmpty()) {
            if (!Regex("""^\d{6}$""").matches(normalizedCode)) {
                return BindingResult.Failure(messageForErrorCode("TOKEN_INVALID"))
            }
        } else if (normalizedToken.length < 4 || normalizedToken.length > 64) {
            return BindingResult.Failure(messageForErrorCode("TOKEN_INVALID"))
        }
        if (deviceId.isBlank()) {
            return BindingResult.Failure("设备 ID 不可用，请重试")
        }
        val url = "${baseUrlProvider().trimEnd('/')}/api/v1/public/pair/redeem"
        val headers = linkedMapOf(
            "Content-Type" to "application/json",
            "Accept" to "application/json",
        ).apply {
            putAll(extraHeadersProvider().filterValues { it.isNotBlank() })
        }
        val body = buildString {
            append("""{"device_id":"${jsonEscape(deviceId)}"""")
            if (normalizedToken.isNotEmpty()) {
                append(""","token":"${jsonEscape(normalizedToken)}"""")
            }
            if (normalizedCode.isNotEmpty()) {
                append(""","short_code":"${jsonEscape(normalizedCode)}"""")
            }
            append("}")
        }
        val response = try {
            transport.postJson(url, headers, body)
        } catch (_: Exception) {
            return BindingResult.Failure(messageForErrorCode("NETWORK"))
        }
        if (response.status !in listOf(200, 201)) {
            return BindingResult.Failure(messageForErrorCode(parseErrorCode(response.body)))
        }
        val credentials = parseCredentials(response.body, deviceId)
            ?: return BindingResult.Failure(messageForErrorCode("UNKNOWN"))
        return BindingResult.Success(credentials)
    }

    private fun parseCredentials(body: String, deviceId: String): CloudCredentials? {
        val deviceToken = body.stringField("device_token").orEmpty()
        val bindingId = body.stringField("binding_id").orEmpty()
        if (deviceToken.isBlank() || bindingId.isBlank()) return null
        return CloudCredentials(
            deviceId = deviceId,
            deviceToken = deviceToken,
            bindingId = bindingId,
            childNickname = body.stringField("nickname").orEmpty().ifBlank { "宝贝" },
            avatarEmoji = body.stringField("avatar_emoji").orEmpty().ifBlank { "🦁" },
            familyLabel = body.stringField("family_id").orEmpty().ifBlank { "家庭账号" },
            childProfileId = body.stringField("child_profile_id").orEmpty(),
            pairedAtMs = body.stringField("paired_at_ms").orEmpty().toLongOrNull() ?: clockMs(),
            deviceIdSource = body.stringField("device_id_source").orEmpty().ifBlank { "preferences_fallback" },
        )
    }

    private fun parseErrorCode(body: String): String =
        body.stringField("code").orEmpty().ifBlank { "UNKNOWN" }

    private fun messageForErrorCode(code: String): String = when (code) {
        "TOKEN_EXPIRED" -> "绑定码已过期"
        "TOKEN_REDEEMED" -> "绑定码已被使用"
        "TOKEN_INVALID" -> "绑定码无效"
        "RATE_LIMITED" -> "请求过于频繁，请稍后再试"
        else -> "绑定失败，请稍后重试"
    }
}

data class UpdatedChildProfile(
    val profileId: String,
    val familyId: String,
    val nickname: String,
    val avatarEmoji: String,
    val updatedAt: String,
)

class ChildProfileClient(
    private val baseUrlProvider: () -> String,
    private val extraHeadersProvider: () -> Map<String, String> = { emptyMap() },
    private val transport: BindingHttpTransport = UrlConnectionBindingHttpTransport(),
) {
    suspend fun updateProfile(deviceToken: String, familyId: String, nickname: String, avatarEmoji: String): UpdatedChildProfile {
        if (deviceToken.isBlank()) {
            throw ChildProfileException("NOT_BOUND", "no device token", 0)
        }
        val fid = familyId.trim().ifBlank { "_" }
        val url = "${baseUrlProvider().trimEnd('/')}/api/v1/family/$fid/profile"
        val headers = linkedMapOf(
            "Content-Type" to "application/json",
            "Accept" to "application/json",
            "Authorization" to "Bearer $deviceToken",
        ).apply {
            putAll(extraHeadersProvider().filterValues { it.isNotBlank() })
        }
        val body = """{"nickname":"${jsonEscape(nickname)}","avatar_emoji":"${jsonEscape(avatarEmoji)}"}"""
        val response = try {
            transport.putJson(url, headers, body)
        } catch (err: Exception) {
            throw ChildProfileException("NETWORK", err.message.orEmpty(), 0)
        }
        if (response.status != 200) {
            throw ChildProfileException(parseErrorCode(response.body), "family/profile: HTTP ${response.status}", response.status)
        }
        return parseUpdatedProfile(response.body)
            ?: throw ChildProfileException("UNKNOWN", "family/profile: malformed response body", response.status)
    }

    private fun parseUpdatedProfile(body: String): UpdatedChildProfile? {
        val nickname = body.stringField("nickname").orEmpty()
        if (nickname.isBlank()) return null
        return UpdatedChildProfile(
            profileId = body.stringField("profile_id").orEmpty(),
            familyId = body.stringField("family_id").orEmpty(),
            nickname = nickname,
            avatarEmoji = body.stringField("avatar_emoji").orEmpty(),
            updatedAt = body.stringField("updated_at").orEmpty(),
        )
    }

    private fun parseErrorCode(body: String): String =
        body.stringField("code").orEmpty().ifBlank { "UNKNOWN" }
}

class ChildProfileException(
    val code: String,
    override val message: String,
    val status: Int,
) : Exception(message)

private fun String.stringField(name: String): String? =
    Regex(""""$name"\s*:\s*"([^"]*)"""").find(this)?.groupValues?.get(1)?.unescapeJson()

private fun String.unescapeJson(): String =
    replace("\\\"", "\"")
        .replace("\\\\", "\\")
        .replace("\\/", "/")
        .replace("\\n", "\n")
        .replace("\\r", "\r")
        .replace("\\t", "\t")

private fun jsonEscape(raw: String): String =
    buildString {
        raw.forEach { ch ->
            when (ch) {
                '\\' -> append("\\\\")
                '"' -> append("\\\"")
                '\n' -> append("\\n")
                '\r' -> append("\\r")
                '\t' -> append("\\t")
                else -> append(ch)
            }
        }
    }

data class CloudPackSyncResult(
    val globalPacks: List<WordPack>,
    val familyPacks: List<WordPack>,
    val statusMessage: String,
    val lastSyncAtMs: Long,
)

interface GlobalPackClient {
    suspend fun sync(): List<WordPack>
}

interface FamilyPackClient {
    suspend fun sync(credentials: CloudCredentials?): List<WordPack>
}

class RemoteGlobalPackClient(
    private val baseUrlProvider: () -> String,
    private val extraHeadersProvider: () -> Map<String, String> = { emptyMap() },
    private val transport: BindingHttpTransport = UrlConnectionBindingHttpTransport(),
) : GlobalPackClient {
    override suspend fun sync(): List<WordPack> {
        val baseUrl = baseUrlProvider().trimEnd('/')
        if (baseUrl.isBlank()) return emptyList()
        val headers = linkedMapOf("Accept" to "application/json").apply {
            putAll(extraHeadersProvider().filterValues { it.isNotBlank() })
        }
        val response = runCatching {
            transport.getJson("$baseUrl/api/v1/public/global-packs/latest.json", headers)
        }.getOrElse { return emptyList() }
        if (response.status == 204) return emptyList()
        if (response.status !in 200..299) return emptyList()
        return RemotePackPayloadParser.parse(response.body, PackSource.Global)
    }
}

class RemoteFamilyPackClient(
    private val baseUrlProvider: () -> String,
    private val extraHeadersProvider: () -> Map<String, String> = { emptyMap() },
    private val transport: BindingHttpTransport = UrlConnectionBindingHttpTransport(),
) : FamilyPackClient {
    override suspend fun sync(credentials: CloudCredentials?): List<WordPack> {
        val token = credentials?.deviceToken.orEmpty()
        if (token.isBlank()) return emptyList()
        val familyId = credentials?.familyLabel.orEmpty().ifBlank { "_" }
        val baseUrl = baseUrlProvider().trimEnd('/')
        if (baseUrl.isBlank()) return emptyList()
        val headers = linkedMapOf(
            "Accept" to "application/json",
            "Authorization" to "Bearer $token",
        ).apply {
            putAll(extraHeadersProvider().filterValues { it.isNotBlank() })
        }
        val encodedFamilyId = URLEncoder.encode(familyId, "UTF-8").replace("+", "%20")
        val response = runCatching {
            transport.getJson("$baseUrl/api/v1/family/$encodedFamilyId/family-packs/latest.json", headers)
        }.getOrElse { return emptyList() }
        if (response.status == 204) return emptyList()
        if (response.status !in 200..299) return emptyList()
        return RemotePackPayloadParser.parse(response.body, PackSource.Family)
    }
}

class FixtureGlobalPackClient(private val fail: Boolean = false) : GlobalPackClient {
    override suspend fun sync(): List<WordPack> {
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

class FixtureFamilyPackClient(private val fail: Boolean = false) : FamilyPackClient {
    override suspend fun sync(credentials: CloudCredentials?): List<WordPack> {
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

enum class WordStatsSyncStatus {
    Unbound,
    NoChanges,
    Pushed,
    Pulled,
    PushedAndPulled,
    NetworkError,
}

data class WordStatsSyncResult(
    val status: WordStatsSyncStatus,
    val pushed: Int = 0,
    val pulled: Int = 0,
    val rejected: Int = 0,
    val serverNowMs: Long = 0L,
)

data class CheckInSyncResult(
    val checkedDayKeys: List<String>,
    val weeklyBonusDayKeys: List<String>,
    val serverNowMs: Long,
    val ok: Boolean,
)

open class CheckInSyncClient(
    private val baseUrlProvider: () -> String = { "" },
    private val extraHeadersProvider: () -> Map<String, String> = { emptyMap() },
    private val transport: BindingHttpTransport = UrlConnectionBindingHttpTransport(),
) {
    open fun buildPayload(snapshot: CheckInSnapshot): String {
        val checked = snapshot.checkedDayKeys.joinToString(",") { "\"${jsonEscape(it)}\"" }
        val bonuses = snapshot.weeklyBonusDayKeys.joinToString(",") { "\"${jsonEscape(it)}\"" }
        val txns = snapshot.weeklyBonusDayKeys.joinToString(",") { day ->
            """{"txn_id":"checkin-weekly-bonus:${jsonEscape(day)}","delta":${CheckInSnapshot.WEEKLY_BONUS_COINS},"reason":"checkin-weekly-bonus:${jsonEscape(day)}","created_at_ms":0}"""
        }
        return """{"checked_day_keys":[$checked],"weekly_bonus_day_keys":[$bonuses],"coin_txns":[$txns],"synced_through_ms":${snapshot.lastSyncedAtMs}}"""
    }

    open suspend fun sync(deviceToken: String, snapshot: CheckInSnapshot, familyId: String = "_"): CheckInSyncResult {
        if (deviceToken.isBlank()) {
            return CheckInSyncResult(snapshot.checkedDayKeys, snapshot.weeklyBonusDayKeys, 0L, ok = false)
        }
        val baseUrl = baseUrlProvider().trimEnd('/')
        if (baseUrl.isBlank()) {
            return CheckInSyncResult(snapshot.checkedDayKeys, snapshot.weeklyBonusDayKeys, 0L, ok = false)
        }
        val fid = familyId.trim().ifBlank { "_" }
        val headers = linkedMapOf(
            "Content-Type" to "application/json",
            "Accept" to "application/json",
            "Authorization" to "Bearer $deviceToken",
        ).apply {
            putAll(extraHeadersProvider().filterValues { it.isNotBlank() })
        }
        val response = try {
            transport.postJson(
                url = "$baseUrl/api/v1/family/$fid/checkins/sync",
                headers = headers,
                body = buildPayload(snapshot),
            )
        } catch (_: Exception) {
            return CheckInSyncResult(snapshot.checkedDayKeys, snapshot.weeklyBonusDayKeys, 0L, ok = false)
        }
        if (response.status !in 200..299) {
            return CheckInSyncResult(snapshot.checkedDayKeys, snapshot.weeklyBonusDayKeys, 0L, ok = false)
        }
        return CheckInSyncResult(
            checkedDayKeys = response.body.stringArrayField("checked_day_keys"),
            weeklyBonusDayKeys = response.body.stringArrayField("weekly_bonus_day_keys"),
            serverNowMs = response.body.longField("server_now_ms") ?: 0L,
            ok = true,
        )
    }
}

open class WordStatsSyncClient(
    private val baseUrlProvider: () -> String = { "" },
    private val extraHeadersProvider: () -> Map<String, String> = { emptyMap() },
    private val transport: BindingHttpTransport = UrlConnectionBindingHttpTransport(),
) {
    open fun buildPayload(stats: List<WordLearningStat>, syncedThroughMs: Long): String {
        val dirtyStats = stats.filter { it.lastSeenAtMs > syncedThroughMs }
        val rows = dirtyStats.joinToString(",") { stat ->
            val mastery = if (stat.seenCount <= 0) 0.0 else stat.correctCount.toDouble() / stat.seenCount.toDouble()
            val lastCorrectMs = if (stat.correctCount > 0) stat.lastSeenAtMs else 0L
            """{"word_id":"${jsonEscape(stat.wordId)}","seen_count":${stat.seenCount},"correct_count":${stat.correctCount},"wrong_count":${stat.wrongCount},"last_answered_ms":${stat.lastSeenAtMs},"last_correct_ms":$lastCorrectMs,"next_review_ms":0,"memory_state":"new","consecutive_correct":0,"consecutive_wrong":0,"mastery":$mastery}"""
        }
        return """{"items":[$rows],"synced_through_ms":$syncedThroughMs}"""
    }

    open suspend fun sync(
        deviceToken: String,
        stats: List<WordLearningStat>,
        syncedThroughMs: Long,
        familyId: String = "_",
    ): WordStatsSyncResult {
        if (deviceToken.isBlank()) {
            return WordStatsSyncResult(status = WordStatsSyncStatus.Unbound)
        }
        val baseUrl = baseUrlProvider().trimEnd('/')
        if (baseUrl.isBlank()) {
            return WordStatsSyncResult(status = WordStatsSyncStatus.NetworkError)
        }
        val fid = familyId.trim().ifBlank { "_" }
        val headers = linkedMapOf(
            "Content-Type" to "application/json",
            "Accept" to "application/json",
            "Authorization" to "Bearer $deviceToken",
        ).apply {
            putAll(extraHeadersProvider().filterValues { it.isNotBlank() })
        }
        val response = try {
            transport.postJson(
                url = "$baseUrl/api/v1/family/$fid/word-stats/sync",
                headers = headers,
                body = buildPayload(stats, syncedThroughMs),
            )
        } catch (_: Exception) {
            return WordStatsSyncResult(status = WordStatsSyncStatus.NetworkError)
        }
        if (response.status !in 200..299) {
            return WordStatsSyncResult(status = WordStatsSyncStatus.NetworkError)
        }
        val pushed = response.body.arrayItemCount("accepted")
        val rejected = response.body.arrayItemCount("rejected")
        val pulled = response.body.objectArrayItemCount("server_pulls")
        val serverNowMs = response.body.longField("server_now_ms") ?: 0L
        val status = when {
            pushed > 0 && pulled > 0 -> WordStatsSyncStatus.PushedAndPulled
            pushed > 0 -> WordStatsSyncStatus.Pushed
            pulled > 0 -> WordStatsSyncStatus.Pulled
            else -> WordStatsSyncStatus.NoChanges
        }
        return WordStatsSyncResult(
            status = status,
            pushed = pushed,
            pulled = pulled,
            rejected = rejected,
            serverNowMs = serverNowMs,
        )
    }
}

private fun String.longField(name: String): Long? =
    Regex(""""$name"\s*:\s*(\d+)""").find(this)?.groupValues?.get(1)?.toLongOrNull()

private fun String.arrayItemCount(name: String): Int {
    val block = arrayBlock(name)
    if (block.isBlank()) return 0
    return Regex(""""([^"]*)"""").findAll(block).count()
}

private fun String.objectArrayItemCount(name: String): Int {
    val block = arrayBlock(name)
    if (block.isBlank()) return 0
    return Regex("""\{""").findAll(block).count()
}

private fun String.arrayBlock(name: String): String =
    Regex(""""$name"\s*:\s*\[(.*?)]""", RegexOption.DOT_MATCHES_ALL)
        .find(this)
        ?.groupValues
        ?.get(1)
        .orEmpty()

private fun String.stringArrayField(name: String): List<String> {
    val block = arrayBlock(name)
    if (block.isBlank()) return emptyList()
    return Regex(""""([^"]*)"""").findAll(block).map { it.groupValues[1].unescapeJson() }.toList()
}

class CloudSyncCoordinator(
    private val globalClient: GlobalPackClient = FixtureGlobalPackClient(),
    private val familyClient: FamilyPackClient = FixtureFamilyPackClient(),
    private val statsClient: WordStatsSyncClient = WordStatsSyncClient(),
    private val clockMs: () -> Long = { System.currentTimeMillis() },
) {
    suspend fun syncPacks(credentials: CloudCredentials?): CloudPackSyncResult {
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
            .getOrElse { """{"items":[],"synced_through_ms":$syncedThroughMs}""" }
    }
}

private object RemotePackPayloadParser {
    fun parse(body: String, source: PackSource): List<WordPack> {
        val root = SimpleJsonParser.parse(body) as? Map<*, *> ?: return emptyList()
        val mergedAtMs = stringValue(root, "merged_at")?.let(::parseIsoMs)
        val packs = root["packs"] as? List<*> ?: return emptyList()
        return packs.mapNotNull { raw ->
            parsePack(raw as? Map<*, *> ?: return@mapNotNull null, source, mergedAtMs)
        }
    }

    private fun parsePack(raw: Map<*, *>, source: PackSource, mergedAtMs: Long?): WordPack? {
        val id = stringValue(raw, "pack_id")?.takeIf { it.isNotBlank() } ?: return null
        val name = stringValue(raw, "name")?.takeIf { it.isNotBlank() } ?: id
        val words = listValue(raw, "words")
            .mapNotNull { parseWord(it as? Map<*, *> ?: return@mapNotNull null) }
        if (words.isEmpty()) return null
        return WordPack(
            id = id,
            nameEn = name,
            nameZh = name,
            source = source,
            version = intValue(raw, "version")?.takeIf { it > 0 } ?: 1,
            publishedAtMs = stringValue(raw, "published_at")?.let(::parseIsoMs) ?: mergedAtMs,
            scene = parseScene(raw["scene"] as? Map<*, *>),
            words = words,
        )
    }

    private fun parseScene(raw: Map<*, *>?): SceneMetadata {
        return SceneMetadata(
            bgPrimary = stringValue(raw, "bgPrimary") ?: stringValue(raw, "bg_primary") ?: "#FFFFFF",
            bgAccent = stringValue(raw, "bgAccent") ?: stringValue(raw, "bg_accent") ?: "#FFFFFF",
            bossName = stringValue(raw, "bossName") ?: stringValue(raw, "boss_name") ?: "",
            monsterPlan = listValue(raw, "monsterPlan").mapNotNull { slot ->
                when (slot) {
                    is String -> slot
                    is Map<*, *> -> stringValue(slot, "kind")
                    else -> null
                }
            },
            bossCandidates = listValue(raw, "bossCandidates").mapNotNull { it as? String },
            storyZh = stringValue(raw, "storyZh") ?: stringValue(raw, "story_zh") ?: "",
            storyEn = stringValue(raw, "storyEn") ?: stringValue(raw, "story_en") ?: "",
            spellbookCoverUrl = stringValue(raw, "spellbookCoverUrl") ?: stringValue(raw, "spellbook_cover_url") ?: "",
        )
    }

    private fun parseWord(raw: Map<*, *>): WordEntry? {
        if (raw["hidden"] == true) return null
        val id = stringValue(raw, "id")?.takeIf { it.isNotBlank() } ?: return null
        val word = stringValue(raw, "word")?.takeIf { it.isNotBlank() } ?: return null
        val meaning = stringValue(raw, "meaningZh")
            ?: stringValue(raw, "meaning_zh")
            ?: stringValue(raw, "meaning")
            ?: word
        val exampleMap = raw["example"] as? Map<*, *>
        val exampleEn = stringValue(exampleMap, "en") ?: stringValue(raw, "exampleEn") ?: stringValue(raw, "example_en")
        val exampleZh = stringValue(exampleMap, "zh") ?: stringValue(raw, "exampleZh") ?: stringValue(raw, "example_zh")
        return WordEntry(
            id = id,
            word = word,
            meaning = meaning,
            distractors = listValue(raw, "distractors").mapNotNull { it as? String },
            example = if (!exampleEn.isNullOrBlank() || !exampleZh.isNullOrBlank()) {
                ExampleSentence(exampleEn.orEmpty(), exampleZh.orEmpty())
            } else {
                null
            },
            difficulty = intValue(raw, "difficulty")?.takeIf { it > 0 } ?: 1,
        )
    }

    private fun stringValue(raw: Map<*, *>?, key: String): String? =
        raw?.get(key) as? String

    private fun intValue(raw: Map<*, *>?, key: String): Int? =
        when (val value = raw?.get(key)) {
            is Int -> value
            is Long -> value.toInt()
            is Double -> value.toInt()
            else -> null
        }

    private fun listValue(raw: Map<*, *>?, key: String): List<*> =
        raw?.get(key) as? List<*> ?: emptyList<Any>()

    private fun parseIsoMs(value: String): Long? {
        val trimmed = value.trim()
        if (trimmed.isBlank()) return null
        val hasZone = Regex("""(Z|z|[+-]\d{2}:?\d{2})$""").containsMatchIn(trimmed)
        val normalized = if (hasZone) trimmed else "${trimmed}Z"
        return runCatching { Instant.parse(normalized).toEpochMilli() }.getOrNull()
    }
}

private class SimpleJsonParser(private val input: String) {
    private var index = 0

    fun parseValue(): Any? {
        skipWhitespace()
        if (index >= input.length) return null
        return when (input[index]) {
            '{' -> parseObject()
            '[' -> parseArray()
            '"' -> parseString()
            't' -> parseLiteral("true", true)
            'f' -> parseLiteral("false", false)
            'n' -> parseLiteral("null", null)
            else -> parseNumber()
        }
    }

    private fun parseObject(): Map<String, Any?> {
        index++
        val out = linkedMapOf<String, Any?>()
        skipWhitespace()
        if (peek('}')) {
            index++
            return out
        }
        while (index < input.length) {
            skipWhitespace()
            val key = parseString()
            skipWhitespace()
            if (peek(':')) index++
            out[key] = parseValue()
            skipWhitespace()
            when {
                peek(',') -> index++
                peek('}') -> {
                    index++
                    return out
                }
                else -> return out
            }
        }
        return out
    }

    private fun parseArray(): List<Any?> {
        index++
        val out = mutableListOf<Any?>()
        skipWhitespace()
        if (peek(']')) {
            index++
            return out
        }
        while (index < input.length) {
            out += parseValue()
            skipWhitespace()
            when {
                peek(',') -> index++
                peek(']') -> {
                    index++
                    return out
                }
                else -> return out
            }
        }
        return out
    }

    private fun parseString(): String {
        if (!peek('"')) return ""
        index++
        val out = StringBuilder()
        while (index < input.length) {
            val ch = input[index++]
            when (ch) {
                '"' -> return out.toString()
                '\\' -> out.append(parseEscape())
                else -> out.append(ch)
            }
        }
        return out.toString()
    }

    private fun parseEscape(): Char {
        if (index >= input.length) return '\\'
        return when (val ch = input[index++]) {
            '"' -> '"'
            '\\' -> '\\'
            '/' -> '/'
            'b' -> '\b'
            'f' -> '\u000C'
            'n' -> '\n'
            'r' -> '\r'
            't' -> '\t'
            'u' -> {
                val hex = input.substring(index, (index + 4).coerceAtMost(input.length))
                index = (index + 4).coerceAtMost(input.length)
                hex.toIntOrNull(16)?.toChar() ?: '?'
            }
            else -> ch
        }
    }

    private fun parseLiteral(literal: String, value: Any?): Any? {
        if (input.regionMatches(index, literal, 0, literal.length)) {
            index += literal.length
        }
        return value
    }

    private fun parseNumber(): Any? {
        val start = index
        while (index < input.length && input[index] in "-+0123456789.eE") {
            index++
        }
        val token = input.substring(start, index)
        return if (token.contains('.') || token.contains('e', ignoreCase = true)) {
            token.toDoubleOrNull()
        } else {
            token.toLongOrNull()
        }
    }

    private fun skipWhitespace() {
        while (index < input.length && input[index].isWhitespace()) {
            index++
        }
    }

    private fun peek(ch: Char): Boolean = index < input.length && input[index] == ch

    companion object {
        fun parse(raw: String): Any? {
            val parser = SimpleJsonParser(raw)
            return parser.parseValue()
        }
    }
}
