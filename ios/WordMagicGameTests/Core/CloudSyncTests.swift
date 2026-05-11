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
}
