# iOS Replica Phase 3 Parent Cloud Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the iOS Phase 3 parent-cloud slice: child device binding, secure device credentials, bound-device info, global/family pack sync, and word-stats sync payload support.

**Architecture:** Keep gameplay offline-first and put all cloud-facing state behind Swift service boundaries. Use Keychain for `device_id` and `device_token`, UserDefaults only for non-secret binding metadata, and merge remote pack layers as `family > global > builtin`. Build the short-code binding path first because it is deterministic in XCTest/XCUITest; QR camera/gallery decoding remains a later parity slice.

**Tech Stack:** Swift 6, SwiftUI, XCTest, XCUITest, Security/Keychain, XcodeGen-backed iOS project (`ios/project.yml`), iPhone 17 Pro simulator.

---

## Source Documents

- Design spec: `docs/superpowers/specs/2026-05-10-ios-replica-phase3-parent-cloud-design.md`
- iOS replica overview: `docs/ios-replica/00-index.md`
- Later phase summary: `docs/ios-replica/04-pack-sync-and-parent-cloud.md`
- Validation matrix: `docs/ios-replica/05-validation-plan.md`
- Contracts:
  - `shared/contracts/protocols/device-binding.md`
  - `shared/contracts/protocols/pack-sync.md`
  - `shared/contracts/protocols/word-stats-sync.md`
- Fixtures:
  - `shared/fixtures/pairing/pair-redeem.sample.json`
  - `shared/fixtures/packs/global-packs-latest.sample.json`
  - `shared/fixtures/packs/family-packs-latest.sample.json`
  - `shared/fixtures/child/word-stats-sync.sample.json`

## File Map

- Create: `ios/WordMagicGame/Services/CloudSyncServices.swift`
  - JSON snake-case helpers.
  - `SecureStore`, `MemorySecureStore`, `KeychainSecureStore`.
  - `DeviceIdProvider`, `PairRedeemResponse`, `CloudCredentialsStore`.
  - Pack sync DTOs and `PackSyncClient`.
  - `WordStatsSyncPayload`.
- Create: `ios/WordMagicGame/Features/Settings/CloudBindingViews.swift`
  - `ScanBindingView`.
  - `BoundDeviceInfoView`.
- Create: `ios/WordMagicGameTests/Core/CloudSyncTests.swift`
  - DTO, secure store, pack-sync status, merge, and word-stats payload tests.
- Modify: `ios/WordMagicGame/App/AppCoordinator.swift`
  - Add Phase 3 routes, stores, binding actions, sync action, and UI-test launch seeds.
- Modify: `ios/WordMagicGame/App/ContentView.swift`
  - Route to binding views.
- Modify: `ios/WordMagicGame/Features/Settings/ConfigView.swift`
  - Add parent cloud binding row.
- Modify: `ios/WordMagicGame/Features/CoreLoop/GrowthLoopViews.swift`
  - Wire PackManager sync button to Phase 3 sync and keep Chinese UI labels.
- Modify: `ios/WordMagicGameUITests/WordMagicGameUITests.swift`
  - Add binding/unbind and global/family pack sync UI coverage.
- Verify: `ios/project.yml`
  - It already includes directory-level sources, so no per-file source entries are needed. If XcodeGen is available, regenerate and compare `ios/WordMagicGame.xcodeproj` before committing.

## Task 1: Add Phase 3 Service Tests First

**Files:**
- Create: `ios/WordMagicGameTests/Core/CloudSyncTests.swift`
- Verify project generation source: `ios/project.yml`

- [ ] **Step 1: Add failing XCTest coverage for binding, secure storage, pack sync, and word stats**

Create `ios/WordMagicGameTests/Core/CloudSyncTests.swift`:

```swift
@testable import WordMagicGame
import XCTest

final class CloudSyncTests: XCTestCase {
    func testPairRedeemFixtureDecodesAndCredentialsStorePersistsTokenInKeychain() throws {
        let response = try JSONDecoder.snakeCase.decode(PairRedeemResponse.self, from: Self.pairRedeemFixture)
        XCTAssertEqual(response.bindingId, "binding-demo")
        XCTAssertEqual(response.familyId, "family-demo")
        XCTAssertEqual(response.childProfileId, "child-demo")
        XCTAssertEqual(response.nickname, "Little Magician")
        XCTAssertEqual(response.avatarEmoji, "🧙")
        XCTAssertEqual(response.deviceToken, "device-token-demo-not-a-secret")

        let keychain = MemorySecureStore()
        let defaults = UserDefaults(suiteName: "CloudSyncTests-\(UUID().uuidString)")!
        let store = CloudCredentialsStore(secureStore: keychain, defaults: defaults)

        store.save(response)

        XCTAssertEqual(keychain.string(forKey: CloudCredentialsStore.deviceTokenKey), "device-token-demo-not-a-secret")
        XCTAssertEqual(store.credentials?.nickname, "Little Magician")
        XCTAssertEqual(store.credentials?.familyId, "family-demo")

        store.clear()

        XCTAssertNil(keychain.string(forKey: CloudCredentialsStore.deviceTokenKey))
        XCTAssertNil(store.credentials)
    }

    func testDeviceIdProviderReturnsStableKeychainBackedId() {
        let keychain = MemorySecureStore()
        let provider = DeviceIdProvider(secureStore: keychain)

        let first = provider.deviceId()
        let second = provider.deviceId()

        XCTAssertEqual(first, second)
        XCTAssertGreaterThanOrEqual(first.count, 8)
        XCTAssertEqual(keychain.string(forKey: DeviceIdProvider.deviceIdKey), first)
    }

    func testPackSyncResponsesHandle200204304AndFamilyOverridesGlobal() throws {
        let globalResponse = try JSONDecoder.snakeCase.decode(PackLayerFixture.self, from: Self.globalPackFixture)
        let familyResponse = try JSONDecoder.snakeCase.decode(PackLayerFixture.self, from: Self.familyPackFixture)
        let client = PackSyncClient()

        let globalCache = try client.apply(
            status: globalResponse.status,
            etag: globalResponse.headers.eTag,
            body: globalResponse.body,
            source: .global,
            cached: nil
        )

        XCTAssertEqual(globalCache?.etag, "\"global-v1\"")
        XCTAssertEqual(globalCache?.packs.map(\.id), ["space-station"])
        XCTAssertEqual(globalCache?.packs.first?.source, .global)

        let preserved = try client.apply(status: 304, etag: nil, body: nil, source: .global, cached: globalCache)
        XCTAssertEqual(preserved, globalCache)

        let cleared = try client.apply(status: 204, etag: nil, body: nil, source: .global, cached: globalCache)
        XCTAssertNil(cleared)

        let familyCache = try client.apply(
            status: familyResponse.status,
            etag: familyResponse.headers.eTag,
            body: familyResponse.body,
            source: .family,
            cached: nil
        )

        let overridingFamily = Pack(
            id: "space-station",
            title: "Family Space",
            subtitle: "Family",
            story: "family",
            source: .family,
            words: [DemoWords.words[0]]
        )
        let library = PackLibrary(
            builtin: [],
            global: globalCache?.packs ?? [],
            family: (familyCache?.packs ?? []) + [overridingFamily]
        )

        XCTAssertEqual(library.pack(id: "space-station")?.title, "Family Space")
        XCTAssertEqual(library.pack(id: "space-station")?.source, .family)
        XCTAssertEqual(library.pack(id: "family-snacks")?.title, "Family Snacks")
    }

    func testFamilyPackClientKeepsCacheForAuthProblemsAndMarksGoneBinding() throws {
        let cached = PackLayerCache(etag: "\"family-v1\"", packs: [
            Pack(id: "family-snacks", title: "Family Snacks", subtitle: "", story: "", source: .family, words: DemoWords.words)
        ])
        let client = PackSyncClient()

        XCTAssertEqual(try client.apply(status: 401, etag: nil, body: nil, source: .family, cached: cached), cached)
        XCTAssertEqual(try client.apply(status: 403, etag: nil, body: nil, source: .family, cached: cached), cached)

        do {
            _ = try client.apply(status: 410, etag: nil, body: nil, source: .family, cached: cached)
            XCTFail("Expected bindingGone")
        } catch PackSyncError.bindingGone {
            // Expected.
        }
    }

    func testWordStatsSyncPayloadMatchesContractShape() throws {
        let recorder = LearningRecorder()
        let answeredAt = Date(timeIntervalSince1970: 1_778_399_999)
        recorder.record(wordId: "space-star", correct: true, at: answeredAt)
        recorder.record(wordId: "space-star", correct: false, at: answeredAt)
        let payload = WordStatsSyncPayload.from(recorder: recorder, syncedThroughMs: 1_778_300_000_000)

        XCTAssertEqual(payload.syncedThroughMs, 1_778_300_000_000)
        XCTAssertEqual(payload.items.count, 1)
        XCTAssertEqual(payload.items[0].wordId, "space-star")
        XCTAssertEqual(payload.items[0].seenCount, 2)
        XCTAssertEqual(payload.items[0].correctCount, 1)
        XCTAssertEqual(payload.items[0].wrongCount, 1)
        XCTAssertEqual(payload.items[0].lastAnsweredMs, 1_778_399_999_000)

        let encoded = try JSONEncoder.snakeCase.encode(payload)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNotNil(object["synced_through_ms"])
        let items = try XCTUnwrap(object["items"] as? [[String: Any]])
        XCTAssertNotNil(items[0]["word_id"])
        XCTAssertNotNil(items[0]["seen_count"])
    }
}
```

- [ ] **Step 2: Add inline fixtures to the same test file**

Append these private fixtures inside `CloudSyncTests`:

```swift
private static let pairRedeemFixture = Data("""
{
  "binding_id": "binding-demo",
  "family_id": "family-demo",
  "child_profile_id": "child-demo",
  "nickname": "Little Magician",
  "avatar_emoji": "🧙",
  "device_token": "device-token-demo-not-a-secret"
}
""".utf8)

private static let globalPackFixture = Data("""
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
          { "id": "space-star", "word": "star", "meaningZh": "星星", "category": "space", "difficulty": 1 }
        ]
      }
    ]
  }
}
""".utf8)

private static let familyPackFixture = Data("""
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
        "version": 1,
        "schema_version": 1,
        "words": [
          { "id": "snack-cookie", "word": "snack", "meaningZh": "点心", "category": "snacks", "difficulty": 1 }
        ]
      }
    ]
  }
}
""".utf8)
```

- [ ] **Step 3: Run the focused test and confirm it is red**

Run:

```bash
xcodebuild test \
  -project ios/WordMagicGame.xcodeproj \
  -scheme WordMagicGame \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:WordMagicGameTests/CloudSyncTests \
  -derivedDataPath /private/tmp/wordmagic-phase3-red
```

Expected: build fails with missing symbols such as `PairRedeemResponse`, `CloudCredentialsStore`, `DeviceIdProvider`, `PackSyncClient`, and `WordStatsSyncPayload`.

- [ ] **Step 4: Commit the red test if your workflow permits red commits**

```bash
git add ios/WordMagicGameTests/Core/CloudSyncTests.swift
git commit -m "test: add phase3 cloud sync coverage"
```

If the branch policy requires green commits only, keep the test unstaged until Task 2 passes.

## Task 2: Implement Cloud Sync Services

**Files:**
- Create: `ios/WordMagicGame/Services/CloudSyncServices.swift`
- Verify: `ios/project.yml`

- [ ] **Step 1: Add JSON helpers and secure storage abstractions**

Create `ios/WordMagicGame/Services/CloudSyncServices.swift` with:

```swift
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
```

- [ ] **Step 2: Add Keychain store and credential models**

Append:

```swift
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
        guard status == errSecSuccess, let data = result as? Data else {
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

struct CloudCredentials: Codable, Equatable {
    var bindingId: String
    var familyId: String
    var childProfileId: String
    var nickname: String
    var avatarEmoji: String
    var deviceToken: String
}
```

- [ ] **Step 3: Add credential store and stable device id provider**

Append:

```swift
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
```

- [ ] **Step 4: Add short-code binding mock for deterministic UI tests**

Append:

```swift
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
```

- [ ] **Step 5: Add pack sync DTOs and status semantics**

Append:

```swift
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
            return PackLayerCache(etag: etag, packs: body.packs.map { $0.pack(source: source) })
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
```

- [ ] **Step 6: Add demo global/family pack fixtures**

Append:

```swift
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
```

- [ ] **Step 7: Add word-stats sync payload**

Append:

```swift
struct WordStatsSyncPayload: Codable, Equatable {
    var items: [WordStatSyncItem]
    var syncedThroughMs: Int

    static func from(recorder: LearningRecorder, syncedThroughMs: Int) -> WordStatsSyncPayload {
        let items = recorder.statsByWordId.values
            .sorted { $0.wordId < $1.wordId }
            .map { stat in
                WordStatSyncItem(
                    wordId: stat.wordId,
                    seenCount: stat.seenCount,
                    correctCount: stat.correctCount,
                    wrongCount: stat.wrongCount,
                    lastAnsweredMs: Int(stat.lastAnsweredAt.timeIntervalSince1970 * 1000)
                )
            }
        return WordStatsSyncPayload(items: items, syncedThroughMs: syncedThroughMs)
    }
}

struct WordStatSyncItem: Codable, Equatable {
    var wordId: String
    var seenCount: Int
    var correctCount: Int
    var wrongCount: Int
    var lastAnsweredMs: Int
}
```

- [ ] **Step 8: Run Phase 3 service tests and confirm green**

Run:

```bash
xcodebuild test \
  -project ios/WordMagicGame.xcodeproj \
  -scheme WordMagicGame \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:WordMagicGameTests/CloudSyncTests \
  -derivedDataPath /private/tmp/wordmagic-phase3-services
```

Expected: `Executed 5 tests, with 0 failures` and `TEST SUCCEEDED`.

- [ ] **Step 9: Commit service layer**

```bash
git add ios/WordMagicGame/Services/CloudSyncServices.swift ios/WordMagicGameTests/Core/CloudSyncTests.swift
git commit -m "feat: add ios phase3 cloud sync services"
```

## Task 3: Wire Coordinator Routes, Binding State, And Pack Sync

**Files:**
- Modify: `ios/WordMagicGame/App/AppCoordinator.swift`
- Modify: `ios/WordMagicGame/App/ContentView.swift`

- [ ] **Step 1: Add Phase 3 routes**

In `AppCoordinator.swift`, extend `AppRoute`:

```swift
enum AppRoute {
    case home
    case battle
    case result
    case config
    case pinSetup
    case pinGate
    case parentAdmin
    case lessonReview
    case monsterCodex
    case packManager
    case wishlist
    case redemptionHistory
    case todayPlan
    case learningReport
    case scanBinding
    case boundDeviceInfo
}
```

- [ ] **Step 2: Add Phase 3 coordinator properties**

Inside `AppCoordinator`:

```swift
@Published var bindingMessage = ""
@Published var packLibrary = PackLibrary()

let cloudCredentialsStore: CloudCredentialsStore
let deviceIdProvider: DeviceIdProvider

private let bindingClient: DeviceBindingClienting
private var globalPackCache: PackLayerCache?
private var familyPackCache: PackLayerCache?
```

In the initializer, inject defaults:

```swift
init(
    configStore: GameConfigStore = GameConfigStore(),
    bindingClient: DeviceBindingClienting = MockDeviceBindingClient(),
    cloudCredentialsStore: CloudCredentialsStore = CloudCredentialsStore(),
    deviceIdProvider: DeviceIdProvider = DeviceIdProvider()
) {
    self.configStore = configStore
    self.bindingClient = bindingClient
    self.cloudCredentialsStore = cloudCredentialsStore
    self.deviceIdProvider = deviceIdProvider
    self.packLibrary = PackLibrary()
    applyLaunchSeeds()
    applyLaunchRoute()
}
```

Keep existing initializer parameters and stores intact if they already exist; add only the Phase 3 dependencies.

- [ ] **Step 3: Add binding and unbind actions**

Add:

```swift
func openBinding() {
    bindingMessage = ""
    route = .scanBinding
}

func openBoundDeviceInfo() {
    bindingMessage = ""
    route = .boundDeviceInfo
}

@MainActor
func bind(shortCode: String) async {
    do {
        let response = try await bindingClient.redeem(shortCode: shortCode, deviceId: deviceIdProvider.deviceId())
        cloudCredentialsStore.save(response)
        bindingMessage = "绑定成功：\(response.nickname)"
    } catch DeviceBindingError.invalidShortCode {
        bindingMessage = "短码无效，请重新输入"
    } catch {
        bindingMessage = "绑定失败，请稍后再试"
    }
}

func finishBinding() {
    route = .config
}

func unbind(pin: String) {
    guard configStore.config.parentPin == pin else {
        bindingMessage = "家长 PIN 不正确"
        return
    }
    cloudCredentialsStore.clear()
    bindingMessage = ""
    route = .config
}
```

- [ ] **Step 4: Add demo-backed pack sync**

Add or update:

```swift
func syncPacks() {
    guard cloudCredentialsStore.credentials != nil else {
        packSyncMessage = "请先绑定家长账号"
        return
    }

    let client = PackSyncClient()
    do {
        let globalFixture = try JSONDecoder.snakeCase.decode(PackLayerFixture.self, from: DemoPackLayerFixtures.global)
        globalPackCache = try client.apply(
            status: globalFixture.status,
            etag: globalFixture.headers.eTag,
            body: globalFixture.body,
            source: .global,
            cached: globalPackCache
        )

        let familyFixture = try JSONDecoder.snakeCase.decode(PackLayerFixture.self, from: DemoPackLayerFixtures.family)
        familyPackCache = try client.apply(
            status: familyFixture.status,
            etag: familyFixture.headers.eTag,
            body: familyFixture.body,
            source: .family,
            cached: familyPackCache
        )

        packLibrary = PackLibrary(
            builtin: Pack.builtin,
            global: globalPackCache?.packs ?? [],
            family: familyPackCache?.packs ?? []
        )
        packSyncMessage = "已同步官方/家庭词包"
    } catch PackSyncError.bindingGone {
        cloudCredentialsStore.clear()
        packSyncMessage = "绑定已失效，请重新绑定"
    } catch {
        packSyncMessage = "同步失败，已保留本地词包"
    }
}
```

Use the existing `packSyncMessage` property name if the Phase 2 implementation already created it.

- [ ] **Step 5: Add UI-test launch routes and seed**

In `applyLaunchRoute()`:

```swift
if arguments.contains("-UITestRouteScanBinding") {
    route = .scanBinding
} else if arguments.contains("-UITestRouteBoundDeviceInfo") {
    route = .boundDeviceInfo
}
```

In `applyLaunchSeeds()`:

```swift
if arguments.contains("-UITestSeedBoundDevice") {
    cloudCredentialsStore.save(.demoBinding)
}
```

- [ ] **Step 6: Route the new views in `ContentView`**

Add cases:

```swift
case .scanBinding:
    ScanBindingView(coordinator: coordinator)
case .boundDeviceInfo:
    BoundDeviceInfoView(coordinator: coordinator)
```

- [ ] **Step 7: Run build/test for coordinator compilation**

Run:

```bash
xcodebuild test \
  -project ios/WordMagicGame.xcodeproj \
  -scheme WordMagicGame \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:WordMagicGameTests/CloudSyncTests \
  -derivedDataPath /private/tmp/wordmagic-phase3-coordinator
```

Expected: `TEST SUCCEEDED`.

- [ ] **Step 8: Commit coordinator wiring**

```bash
git add ios/WordMagicGame/App/AppCoordinator.swift ios/WordMagicGame/App/ContentView.swift
git commit -m "feat: wire ios phase3 cloud routes"
```

## Task 4: Add Binding UI And Settings Entry

**Files:**
- Create: `ios/WordMagicGame/Features/Settings/CloudBindingViews.swift`
- Modify: `ios/WordMagicGame/Features/Settings/ConfigView.swift`

- [ ] **Step 1: Add ScanBindingView**

Create `CloudBindingViews.swift` with:

```swift
import SwiftUI

struct ScanBindingView: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var shortCode = ""

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button("返回") { coordinator.route = .config }
                    .font(.headline.weight(.bold))
                Spacer()
                Text("绑定家长账号")
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppTheme.navy)
                Spacer()
                Color.clear.frame(width: 48, height: 1)
            }

            HStack(spacing: 28) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("家长端短码")
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppTheme.navy)
                    Text("输入家长端生成的 6 位短码")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(coordinator.bindingMessage.isEmpty ? "绑定后会同步家庭词包和学习报告" : coordinator.bindingMessage)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(coordinator.bindingMessage.hasPrefix("绑定成功") ? AppTheme.mint : .secondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .frame(height: 46, alignment: .topLeading)
                        .accessibilityIdentifier("BindingMessage")
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                TextField("6 位短码", text: $shortCode)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
                    .multilineTextAlignment(.center)
                    .frame(width: 220)
                    .accessibilityIdentifier("6 位短码")
                    .onChange(of: shortCode) { _, value in
                        shortCode = String(value.filter(\.isNumber).prefix(6))
                    }

                VStack(spacing: 12) {
                    Button("绑定") {
                        Task { await coordinator.bind(shortCode: shortCode) }
                    }
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(.white)
                    .frame(width: 128, height: 48)
                    .background(AppTheme.red, in: Capsule())
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("绑定")

                    if coordinator.bindingMessage.hasPrefix("绑定成功") {
                        Button("完成") { coordinator.finishBinding() }
                            .font(.title3.weight(.heavy))
                            .foregroundStyle(AppTheme.navy)
                            .frame(width: 128, height: 48)
                            .background(AppTheme.cream, in: Capsule())
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("完成")
                    }
                }
                .frame(width: 142)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 150)
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18).stroke(Color.gray.opacity(0.16), lineWidth: 1.2)
            }
        }
        .padding(.horizontal, 42)
        .padding(.vertical, 20)
        .background(AppTheme.page)
    }
}
```

- [ ] **Step 2: Add BoundDeviceInfoView**

Append:

```swift
struct BoundDeviceInfoView: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var pin = ""

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button("返回") { coordinator.route = .config }
                    .font(.headline.weight(.bold))
                Spacer()
                Text("绑定设备")
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppTheme.navy)
                Spacer()
                Color.clear.frame(width: 48, height: 1)
            }

            HStack(spacing: 18) {
                if let credentials = coordinator.cloudCredentialsStore.credentials {
                    VStack(spacing: 8) {
                        Text(credentials.avatarEmoji)
                            .font(.system(size: 46))
                        Text(credentials.nickname)
                            .font(.system(size: 26, weight: .heavy, design: .rounded))
                            .foregroundStyle(AppTheme.navy)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(width: 230)

                    VStack(spacing: 8) {
                        infoRow("家庭", credentials.familyId)
                        infoRow("档案", credentials.childProfileId)
                        infoRow("设备", coordinator.deviceIdProvider.deviceId())
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Text("尚未绑定")
                        .font(.title.weight(.heavy))
                        .foregroundStyle(AppTheme.navy)
                        .frame(maxWidth: .infinity)
                }

                VStack(spacing: 10) {
                    SecureField("家长 PIN", text: $pin)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                        .accessibilityIdentifier("家长 PIN")

                    Text(coordinator.bindingMessage.isEmpty ? "输入 PIN 后可解除当前设备绑定" : coordinator.bindingMessage)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(coordinator.bindingMessage.isEmpty ? .secondary : AppTheme.red)
                        .multilineTextAlignment(.center)
                        .frame(width: 260, height: 38)

                    Button("解除绑定") {
                        coordinator.unbind(pin: pin)
                    }
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(.white)
                    .frame(width: 150, height: 44)
                    .background(AppTheme.red, in: Capsule())
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("解除绑定")
                }
                .frame(width: 300)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 170)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18).stroke(Color.gray.opacity(0.16), lineWidth: 1.2)
            }
        }
        .padding(.horizontal, 42)
        .padding(.vertical, 14)
        .background(AppTheme.page)
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(AppTheme.navy)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: 430, alignment: .leading)
    }
}
```

- [ ] **Step 3: Add cloud binding row to ConfigView**

Insert `cloudBindingSection` into the main `VStack` below the local settings and parent buttons:

```swift
cloudBindingSection
```

Add:

```swift
private var cloudBindingSection: some View {
    HStack(spacing: 16) {
        Text("家长云同步")
            .font(.title2.weight(.bold))
            .frame(width: 130, alignment: .trailing)

        if let credentials = coordinator.cloudCredentialsStore.credentials {
            Text("已绑定 \(credentials.nickname)")
                .font(.headline.weight(.bold))
                .foregroundStyle(AppTheme.navy)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .accessibilityIdentifier("CloudBindingStatus")
            Button("账号信息") { coordinator.openBoundDeviceInfo() }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.mint)
                .accessibilityIdentifier("账号信息")
        } else {
            Button("绑定家长账号") { coordinator.openBinding() }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.mint)
                .accessibilityIdentifier("绑定家长账号")
        }
        Spacer()
    }
    .font(.headline.weight(.bold))
    .frame(maxWidth: 560)
}
```

- [ ] **Step 4: Build to catch SwiftUI errors**

Run:

```bash
xcodebuild test \
  -project ios/WordMagicGame.xcodeproj \
  -scheme WordMagicGame \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:WordMagicGameTests/CloudSyncTests \
  -derivedDataPath /private/tmp/wordmagic-phase3-binding-ui-build
```

Expected: `TEST SUCCEEDED`.

- [ ] **Step 5: Commit binding UI**

```bash
git add ios/WordMagicGame/Features/Settings/CloudBindingViews.swift ios/WordMagicGame/Features/Settings/ConfigView.swift
git commit -m "feat: add ios phase3 binding screens"
```

## Task 5: Expose Pack Sync In PackManager

**Files:**
- Modify: `ios/WordMagicGame/Features/CoreLoop/GrowthLoopViews.swift`

- [ ] **Step 1: Keep the sync button Chinese and icon-free**

In `PackManagerView`, make the sync button call `coordinator.syncPacks()` and display the plain Chinese label:

```swift
Button("同步词包") {
    coordinator.syncPacks()
}
.buttonStyle(.borderedProminent)
.tint(AppTheme.mint)
.accessibilityIdentifier("同步词包")
```

- [ ] **Step 2: Show sync status from coordinator**

Render the coordinator status near the PackManager header:

```swift
if !coordinator.packSyncMessage.isEmpty {
    Text(coordinator.packSyncMessage)
        .font(.subheadline.weight(.bold))
        .foregroundStyle(.secondary)
}
```

Expected status strings:

- Unbound manual sync: `请先绑定家长账号`
- Bound successful sync: `已同步官方/家庭词包`
- Binding gone: `绑定已失效，请重新绑定`
- Other sync failure: `同步失败，已保留本地词包`

- [ ] **Step 3: Run Phase 3 tests**

Run:

```bash
xcodebuild test \
  -project ios/WordMagicGame.xcodeproj \
  -scheme WordMagicGame \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:WordMagicGameTests/CloudSyncTests \
  -derivedDataPath /private/tmp/wordmagic-phase3-packmanager
```

Expected: `TEST SUCCEEDED`.

- [ ] **Step 4: Commit PackManager sync entry**

```bash
git add ios/WordMagicGame/Features/CoreLoop/GrowthLoopViews.swift
git commit -m "feat: expose ios phase3 pack sync"
```

## Task 6: Add Phase 3 UI Tests

**Files:**
- Modify: `ios/WordMagicGameUITests/WordMagicGameUITests.swift`

- [ ] **Step 1: Add binding and unbind UI test**

Append to `WordMagicGameUITests`:

```swift
@MainActor
func testShortCodeBindingAndUnbindFlow() {
    let app = XCUIApplication()
    app.launchArguments = ["-UITestResetState", "-UITestMockBinding", "-UITestSeedParentPin", "-UITestRouteConfig"]
    app.launch()

    XCTAssertTrue(app.staticTexts["游戏设置"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["绑定家长账号"].exists)
    app.buttons["绑定家长账号"].tap()

    XCTAssertTrue(app.staticTexts["绑定家长账号"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.textFields["6 位短码"].exists)
    app.textFields["6 位短码"].tap()
    app.textFields["6 位短码"].typeText("123456")
    app.buttons["绑定"].tap()

    XCTAssertTrue(app.staticTexts["绑定成功：小明测试46373"].waitForExistence(timeout: 5))
    app.buttons["完成"].tap()
    XCTAssertTrue(app.buttons["账号信息"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["已绑定 小明测试46373"].exists)

    app.buttons["账号信息"].tap()
    XCTAssertTrue(app.staticTexts["绑定设备"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["小明测试46373"].exists)
    app.secureTextFields["家长 PIN"].tap()
    app.secureTextFields["家长 PIN"].typeText("123456")
    app.buttons["解除绑定"].tap()

    XCTAssertTrue(app.buttons["绑定家长账号"].waitForExistence(timeout: 5))
}
```

- [ ] **Step 2: Add global/family pack sync UI test**

Append:

```swift
@MainActor
func testBoundDeviceCanSyncGlobalAndFamilyPacks() {
    let app = XCUIApplication()
    app.launchArguments = ["-UITestResetState", "-UITestSeedBoundDevice", "-UITestRoutePackManager"]
    app.launch()

    XCTAssertTrue(app.staticTexts["我的词包"].waitForExistence(timeout: 5))
    app.buttons["同步词包"].tap()
    XCTAssertTrue(app.staticTexts["已同步官方/家庭词包"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["官方"].exists)
    XCTAssertTrue(app.staticTexts["Space Station"].exists)
    XCTAssertTrue(app.staticTexts["家庭"].exists)
    XCTAssertTrue(app.staticTexts["Family Snacks"].exists)
}
```

- [ ] **Step 3: Run focused Phase 3 UI tests**

Run:

```bash
xcodebuild test \
  -project ios/WordMagicGame.xcodeproj \
  -scheme WordMagicGame \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:WordMagicGameUITests/WordMagicGameUITests/testShortCodeBindingAndUnbindFlow \
  -only-testing:WordMagicGameUITests/WordMagicGameUITests/testBoundDeviceCanSyncGlobalAndFamilyPacks \
  -derivedDataPath /private/tmp/wordmagic-phase3-ui
```

Expected: `Executed 2 tests, with 0 failures` and `TEST SUCCEEDED`.

- [ ] **Step 4: Commit UI tests**

```bash
git add ios/WordMagicGameUITests/WordMagicGameUITests.swift
git commit -m "test: cover ios phase3 binding and pack sync"
```

## Task 7: Screenshot Verification And Visual Polish

**Files:**
- Modify only the files from Tasks 3-5 if screenshot comparison shows layout drift.

- [ ] **Step 1: Capture short-code binding page**

Run:

```bash
xcrun simctl terminate booted com.terryma.wordmagicgame || true
xcrun simctl launch booted com.terryma.wordmagicgame -UITestRouteScanBinding
xcrun simctl io booted screenshot /private/tmp/wordmagic-phase3-scan-binding.png
sips -r -90 /private/tmp/wordmagic-phase3-scan-binding.png --out /private/tmp/wordmagic-phase3-scan-binding-readable.png
```

Expected visual checks:

- Page is landscape.
- Buttons and labels are Chinese.
- The red `绑定` button is single-line.
- The `6 位短码` field does not overlap the button or description.
- Card density matches existing iOS settings/pack surfaces.

- [ ] **Step 2: Capture bound-device page**

Run:

```bash
xcrun simctl terminate booted com.terryma.wordmagicgame || true
xcrun simctl launch booted com.terryma.wordmagicgame -UITestRouteBoundDeviceInfo -UITestSeedBoundDevice
xcrun simctl io booted screenshot /private/tmp/wordmagic-phase3-bound-device.png
sips -r -90 /private/tmp/wordmagic-phase3-bound-device.png --out /private/tmp/wordmagic-phase3-bound-device-readable.png
```

Expected visual checks:

- Page is landscape.
- Title is `绑定设备`.
- Nickname `小明测试46373` is visible and not clipped.
- `家庭` / `档案` / `设备` labels have visible values.
- `家长 PIN` input and `解除绑定` button are single-line and do not collide.

- [ ] **Step 3: If values are squeezed, change info rows to vertical label/value**

Use this `infoRow` implementation:

```swift
private func infoRow(_ title: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
        Text(title)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.secondary)
        Text(value)
            .font(.headline.weight(.bold))
            .foregroundStyle(AppTheme.navy)
            .lineLimit(1)
            .minimumScaleFactor(0.65)
    }
    .frame(maxWidth: 430, alignment: .leading)
}
```

- [ ] **Step 4: Re-run focused UI tests after every visual edit**

Run:

```bash
xcodebuild test \
  -project ios/WordMagicGame.xcodeproj \
  -scheme WordMagicGame \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:WordMagicGameUITests/WordMagicGameUITests/testShortCodeBindingAndUnbindFlow \
  -only-testing:WordMagicGameUITests/WordMagicGameUITests/testBoundDeviceCanSyncGlobalAndFamilyPacks \
  -derivedDataPath /private/tmp/wordmagic-phase3-ui-after-polish
```

Expected: `TEST SUCCEEDED`.

- [ ] **Step 5: Commit screenshot-driven polish**

```bash
git add ios/WordMagicGame/Features/Settings/CloudBindingViews.swift
git commit -m "style: polish ios phase3 binding layouts"
```

Skip this commit if no visual edits were needed.

## Task 8: Full Verification And Project Hygiene

**Files:**
- Verify: `ios/project.yml`
- Verify: `ios/WordMagicGame.xcodeproj/project.pbxproj`
- Verify: all modified Phase 3 files.

- [ ] **Step 1: Run full iOS tests**

Run:

```bash
xcodebuild test \
  -project ios/WordMagicGame.xcodeproj \
  -scheme WordMagicGame \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /private/tmp/wordmagic-phase3-full
```

Expected:

- `WordMagicGameTests`: all unit tests pass.
- `WordMagicGameUITests`: all UI tests pass.
- Final output contains `TEST SUCCEEDED`.

- [ ] **Step 2: Check XcodeGen source-of-truth drift**

If `xcodegen` is installed, run:

```bash
cd ios
xcodegen generate
cd ..
git diff -- ios/project.yml ios/WordMagicGame.xcodeproj/project.pbxproj
```

Expected:

- `ios/project.yml` remains the source of truth.
- Because `ios/project.yml` uses directory-level sources, new Swift files do not require explicit source entries.
- Any `.xcodeproj` diff is reviewed before commit.

If `xcodegen` is not installed, run:

```bash
git diff -- ios/project.yml ios/WordMagicGame.xcodeproj/project.pbxproj
```

Expected: no accidental `ios/project.yml` churn; `.xcodeproj` changes only reflect adding the Phase 3 source/test files.

- [ ] **Step 3: Check final diff scope**

Run:

```bash
git status --short
git diff --stat
```

Expected changed files are limited to:

- `ios/WordMagicGame/Services/CloudSyncServices.swift`
- `ios/WordMagicGame/Features/Settings/CloudBindingViews.swift`
- `ios/WordMagicGameTests/Core/CloudSyncTests.swift`
- `ios/WordMagicGame/App/AppCoordinator.swift`
- `ios/WordMagicGame/App/ContentView.swift`
- `ios/WordMagicGame/Features/Settings/ConfigView.swift`
- `ios/WordMagicGame/Features/CoreLoop/GrowthLoopViews.swift`
- `ios/WordMagicGameUITests/WordMagicGameUITests.swift`
- `ios/WordMagicGame.xcodeproj/project.pbxproj` if the project file is checked in.

- [ ] **Step 4: Commit final Phase 3 implementation**

If earlier tasks were not committed individually, create one focused commit:

```bash
git add \
  ios/WordMagicGame/Services/CloudSyncServices.swift \
  ios/WordMagicGame/Features/Settings/CloudBindingViews.swift \
  ios/WordMagicGameTests/Core/CloudSyncTests.swift \
  ios/WordMagicGame/App/AppCoordinator.swift \
  ios/WordMagicGame/App/ContentView.swift \
  ios/WordMagicGame/Features/Settings/ConfigView.swift \
  ios/WordMagicGame/Features/CoreLoop/GrowthLoopViews.swift \
  ios/WordMagicGameUITests/WordMagicGameUITests.swift \
  ios/WordMagicGame.xcodeproj/project.pbxproj
git commit -m "feat: implement ios phase3 parent cloud sync"
```

## Acceptance Checklist

- [ ] Config shows `绑定家长账号` when unbound.
- [ ] Short-code binding with `123456` stores credentials and shows `已绑定 小明测试46373`.
- [ ] Device token is stored only through `SecureStore` / Keychain.
- [ ] Bound-device page shows nickname, avatar, family id, child profile id, and device id.
- [ ] Parent PIN unbind clears local cloud credentials.
- [ ] Bound PackManager sync shows `已同步官方/家庭词包`.
- [ ] Synced library contains global `Space Station` and family `Family Snacks`.
- [ ] Pack merge priority remains `family > global > builtin`.
- [ ] Word-stats payload encodes snake-case keys compatible with the shared contract.
- [ ] Offline gameplay does not depend on Phase 3 network state.
- [ ] Focused Phase 3 unit tests pass.
- [ ] Focused Phase 3 UI tests pass.
- [ ] Full iOS test suite passes.
- [ ] iPhone simulator screenshots were captured and checked after layout changes.

