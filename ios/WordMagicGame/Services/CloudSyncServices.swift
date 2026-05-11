import Foundation
import Security

extension JSONDecoder {
    static var snakeCase: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

extension JSONEncoder {
    static var snakeCase: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

protocol SecureStore {
    func string(forKey key: String) -> String?
    func set(_ value: String, forKey key: String)
    func remove(forKey key: String)
}

final class MemorySecureStore: SecureStore {
    private var values: [String: String] = [:]

    func string(forKey key: String) -> String? {
        values[key]
    }

    func set(_ value: String, forKey key: String) {
        values[key] = value
    }

    func remove(forKey key: String) {
        values.removeValue(forKey: key)
    }
}

final class KeychainSecureStore: SecureStore {
    private let service: String

    init(service: String = "com.terryma.wordmagicgame.cloud") {
        self.service = service
    }

    func string(forKey key: String) -> String? {
        var query = baseQuery(forKey: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data
        else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func set(_ value: String, forKey key: String) {
        guard let data = value.data(using: .utf8) else { return }
        var query = baseQuery(forKey: key)
        let attributes: [String: Any] = [kSecValueData as String: data]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            query[kSecValueData as String] = data
            SecItemAdd(query as CFDictionary, nil)
        }
    }

    func remove(forKey key: String) {
        SecItemDelete(baseQuery(forKey: key) as CFDictionary)
    }

    private func baseQuery(forKey key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }
}

struct PairRedeemResponse: Codable, Equatable, Sendable {
    var bindingId: String
    var familyId: String
    var childProfileId: String
    var nickname: String
    var avatarEmoji: String
    var deviceToken: String
}

enum DeviceBindingError: Error, Equatable, Sendable {
    case invalidShortCode
}

protocol DeviceBindingClienting: Sendable {
    func redeem(shortCode: String, deviceId: String) async throws -> PairRedeemResponse
}

struct MockDeviceBindingClient: DeviceBindingClienting, Sendable {
    func redeem(shortCode: String, deviceId: String) async throws -> PairRedeemResponse {
        let trimmed = shortCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed == "123456" || trimmed == "654321" else {
            throw DeviceBindingError.invalidShortCode
        }
        return PairRedeemResponse.demoBinding
    }
}

extension PairRedeemResponse {
    static let demoBinding = PairRedeemResponse(
        bindingId: "binding-demo",
        familyId: "family-demo",
        childProfileId: "child-demo",
        nickname: "小明测试46373",
        avatarEmoji: "🦁",
        deviceToken: "device-token-demo-not-a-secret"
    )
}

struct CloudCredentials: Codable, Equatable {
    var bindingId: String
    var familyId: String
    var childProfileId: String
    var nickname: String
    var avatarEmoji: String
    var deviceToken: String
}

final class CloudCredentialsStore {
    static let deviceTokenKey = "wordMagicCloudDeviceToken"

    private let metadataKey = "wordMagicCloudCredentialsMetadata"
    private let secureStore: SecureStore
    private let defaults: UserDefaults

    init(secureStore: SecureStore = KeychainSecureStore(), defaults: UserDefaults = .standard) {
        self.secureStore = secureStore
        self.defaults = defaults
        if ProcessInfo.processInfo.arguments.contains("-UITestResetState") {
            clear()
        }
    }

    var credentials: CloudCredentials? {
        guard let token = secureStore.string(forKey: Self.deviceTokenKey),
              let data = defaults.data(forKey: metadataKey),
              let metadata = try? JSONDecoder().decode(Metadata.self, from: data)
        else {
            return nil
        }
        return CloudCredentials(
            bindingId: metadata.bindingId,
            familyId: metadata.familyId,
            childProfileId: metadata.childProfileId,
            nickname: metadata.nickname,
            avatarEmoji: metadata.avatarEmoji,
            deviceToken: token
        )
    }

    func save(_ response: PairRedeemResponse) {
        secureStore.set(response.deviceToken, forKey: Self.deviceTokenKey)
        let metadata = Metadata(
            bindingId: response.bindingId,
            familyId: response.familyId,
            childProfileId: response.childProfileId,
            nickname: response.nickname,
            avatarEmoji: response.avatarEmoji
        )
        if let data = try? JSONEncoder().encode(metadata) {
            defaults.set(data, forKey: metadataKey)
        }
    }

    func clear() {
        secureStore.remove(forKey: Self.deviceTokenKey)
        defaults.removeObject(forKey: metadataKey)
    }

    private struct Metadata: Codable, Equatable {
        var bindingId: String
        var familyId: String
        var childProfileId: String
        var nickname: String
        var avatarEmoji: String
    }
}

final class DeviceIdProvider {
    static let deviceIdKey = "wordMagicCloudDeviceId"

    private let secureStore: SecureStore

    init(secureStore: SecureStore = KeychainSecureStore()) {
        self.secureStore = secureStore
    }

    func deviceId() -> String {
        if let existing = secureStore.string(forKey: Self.deviceIdKey) {
            return existing
        }
        let created = UUID().uuidString.lowercased()
        secureStore.set(created, forKey: Self.deviceIdKey)
        return created
    }
}

struct PackLayerFixture: Codable, Equatable {
    var status: Int
    var headers: PackLayerHeaders
    var body: RemotePackPayload?
}

struct PackLayerHeaders: Codable, Equatable {
    var eTag: String?

    enum CodingKeys: String, CodingKey {
        case eTag = "ETag"
    }
}

struct RemotePackPayload: Codable, Equatable {
    var packs: [RemotePack]
}

struct RemotePack: Codable, Equatable {
    var packId: String
    var name: String
    var description: String?
    var version: Int?
    var publishedAt: Date?
    var scene: SceneMetadata?
    var words: [WordEntry]

    func pack(source: PackSource) -> Pack {
        Pack(
            id: packId,
            title: name,
            subtitle: description ?? "\(words.count) words",
            story: description ?? name,
            source: source,
            version: version ?? 1,
            publishedAt: publishedAt,
            scene: scene ?? .empty,
            words: words
        )
    }
}

struct PackLayerCache: Equatable {
    var etag: String?
    var packs: [Pack]
}

enum PackSyncError: Error, Equatable {
    case bindingGone
    case missingBody
    case unsupportedStatus(Int)
}

struct PackSyncClient {
    func apply(
        status: Int,
        etag: String?,
        body: RemotePackPayload?,
        source: PackSource,
        cached: PackLayerCache?
    ) throws -> PackLayerCache? {
        switch status {
        case 200:
            guard let body else { throw PackSyncError.missingBody }
            return PackLayerCache(
                etag: etag,
                packs: body.packs.map { $0.pack(source: source) }
            )
        case 204:
            return nil
        case 304, 401, 403:
            return cached
        case 410:
            throw PackSyncError.bindingGone
        default:
            throw PackSyncError.unsupportedStatus(status)
        }
    }
}

enum DemoPackLayerFixtures {
    static let global = Data("""
    {
      "status": 200,
      "headers": { "ETag": "\\"global-v1\\"" },
      "body": {
        "schema_version": 1,
        "merged_at": "2026-05-10T12:03:34Z",
        "packs": [
          {
            "pack_id": "space-station",
            "name": "Space Station",
            "description": "Space themed practice pack",
            "scene": {
              "bgPrimary": "#102A43",
              "bgAccent": "#F0B429",
              "bossName": "Star Wizard"
            },
            "version": 1,
            "schema_version": 1,
            "published_at": "2026-05-10T12:03:34Z",
            "words": [
              { "id": "space-star", "word": "star", "meaningZh": "星星", "category": "space", "difficulty": 1 },
              { "id": "space-moon", "word": "moon", "meaningZh": "月亮", "category": "space", "difficulty": 1 }
            ]
          }
        ]
      }
    }
    """.utf8)

    static let family = Data("""
    {
      "status": 200,
      "headers": { "ETag": "\\"family-v1\\"" },
      "body": {
        "schema_version": 1,
        "family_id": "family-demo",
        "merged_at": "2026-05-10T12:03:34Z",
        "packs": [
          {
            "pack_id": "family-snacks",
            "name": "Family Snacks",
            "description": "家庭自定义点心单词",
            "version": 1,
            "schema_version": 1,
            "words": [
              { "id": "snack-cookie", "word": "cookie", "meaningZh": "饼干", "category": "snacks", "difficulty": 1 },
              { "id": "snack-juice", "word": "juice", "meaningZh": "果汁", "category": "snacks", "difficulty": 1 }
            ]
          }
        ]
      }
    }
    """.utf8)
}

struct WordStatsSyncPayload: Codable, Equatable {
    var items: [WordStatSyncItem]
    var syncedThroughMs: Int

    static func from(recorder: LearningRecorder, syncedThroughMs: Int) -> WordStatsSyncPayload {
        let items = recorder.statsByWordId.values
            .sorted { $0.wordId < $1.wordId }
            .map(WordStatSyncItem.init(stat:))
        return WordStatsSyncPayload(items: items, syncedThroughMs: syncedThroughMs)
    }
}

struct WordStatSyncItem: Codable, Equatable {
    var wordId: String
    var seenCount: Int
    var correctCount: Int
    var wrongCount: Int
    var lastAnsweredMs: Int
    var lastCorrectMs: Int?
    var nextReviewMs: Int?
    var memoryState: String
    var consecutiveCorrect: Int
    var consecutiveWrong: Int
    var mastery: Double

    init(stat: WordLearningStat) {
        wordId = stat.wordId
        seenCount = stat.attempts
        correctCount = stat.correct
        wrongCount = max(stat.attempts - stat.correct, 0)
        lastAnsweredMs = Self.ms(stat.lastSeenAt)
        lastCorrectMs = stat.correct > 0 ? lastAnsweredMs : nil
        nextReviewMs = lastAnsweredMs + 86_400_000
        consecutiveCorrect = stat.correct == stat.attempts ? stat.correct : 0
        consecutiveWrong = stat.correct == 0 ? wrongCount : 0
        mastery = min(max(stat.accuracy, 0), 1)
        if stat.attempts >= 3 && stat.accuracy >= 0.9 {
            memoryState = "mastered"
        } else if stat.attempts > 0 {
            memoryState = "learning"
        } else {
            memoryState = "new"
        }
    }

    private static func ms(_ date: Date) -> Int {
        Int((date.timeIntervalSince1970 * 1000).rounded())
    }
}
