@testable import WordMagicGame
import XCTest

final class SpellbookTests: XCTestCase {
    func testCardStateUsesSeenCountBeforeMemoryState() {
        let word = Self.word("word-1")

        XCTAssertEqual(SpellbookService.cardState(for: word, stat: nil), .locked)
        XCTAssertEqual(SpellbookService.cardState(for: word, stat: Self.stat(wordId: word.id, seenCount: 0, memoryState: .mastered)), .locked)
        XCTAssertEqual(SpellbookService.cardState(for: word, stat: Self.stat(wordId: word.id, seenCount: 1, memoryState: .learning)), .seen)
        XCTAssertEqual(SpellbookService.cardState(for: word, stat: Self.stat(wordId: word.id, seenCount: 1, memoryState: .mastered)), .mastered)
    }

    func testPackProgressRequiresEveryWordMasteredAndRejectsEmptyPacks() {
        let words = [Self.word("one"), Self.word("two")]
        let partial = [
            "one": Self.stat(wordId: "one", seenCount: 3, memoryState: .mastered),
            "two": Self.stat(wordId: "two", seenCount: 1, memoryState: .familiar),
        ]
        let complete = [
            "one": Self.stat(wordId: "one", seenCount: 3, memoryState: .mastered),
            "two": Self.stat(wordId: "two", seenCount: 3, memoryState: .mastered),
        ]

        XCTAssertEqual(SpellbookService.progress(words: words, statsByWordId: partial).masteredCount, 1)
        XCTAssertFalse(SpellbookService.progress(words: words, statsByWordId: partial).isComplete)
        XCTAssertTrue(SpellbookService.progress(words: words, statsByWordId: complete).isComplete)
        XCTAssertFalse(SpellbookService.progress(words: [], statsByWordId: [:]).isComplete)
    }

    @MainActor
    func testSpellbookRewardIsUncappedAndClaimedOncePerPack() {
        let suiteName = "SpellbookTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SpellbookRewardStore(defaults: defaults)
        let account = CoinAccount(balance: 0, defaults: defaults)

        XCTAssertTrue(store.canClaim(packId: "fruit-forest", isComplete: true))
        let first = store.claim(packId: "fruit-forest", account: account, now: Date(timeIntervalSince1970: 1))
        let second = store.claim(packId: "fruit-forest", account: account, now: Date(timeIntervalSince1970: 2))

        XCTAssertTrue(first)
        XCTAssertFalse(second)
        XCTAssertEqual(account.balance, SpellbookService.rewardCoins)
        XCTAssertTrue(store.isClaimed(packId: "fruit-forest"))
    }

    func testSceneMetadataDecodesSpellbookCoverUrlFromServerKeys() throws {
        let camel = try JSONDecoder().decode(SceneMetadata.self, from: #"{"spellbookCoverUrl":"https://cdn.example/camel.png"}"#.data(using: .utf8)!)
        let snake = try JSONDecoder().decode(SceneMetadata.self, from: #"{"spellbook_cover_url":"https://cdn.example/snake.png"}"#.data(using: .utf8)!)

        XCTAssertEqual(camel.spellbookCoverUrl, "https://cdn.example/camel.png")
        XCTAssertEqual(snake.spellbookCoverUrl, "https://cdn.example/snake.png")
    }

    func testCoverCacheSourcePrefersDiskFileThenFallsBackToRemoteURL() async throws {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let remoteURL = URL(string: "https://cdn.example.test/covers/space.png")!
        let pack = Self.pack(id: "space-station", coverURL: remoteURL.absoluteString)
        let cache = SpellbookCoverCache(directory: directory) { url in
            XCTAssertEqual(url, remoteURL)
            return Data([0x89, 0x50, 0x4E, 0x47])
        }

        XCTAssertEqual(cache.source(for: pack), .remoteURL(remoteURL))

        await cache.prewarm(packs: [pack])

        guard case let .cachedFile(fileURL) = cache.source(for: pack) else {
            return XCTFail("Expected cached file source after prewarm")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertEqual(fileURL.scheme, "file")
    }

    func testCoverCachePrewarmDeduplicatesURLsAndIgnoresBundledCovers() async {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let remoteURL = URL(string: "https://cdn.example.test/covers/shared.png")!
        let calls = LockedCounter()
        let cache = SpellbookCoverCache(directory: directory) { _ in
            calls.increment()
            return Data([1, 2, 3])
        }

        await cache.prewarm(packs: [
            Self.pack(id: "a", coverURL: remoteURL.absoluteString),
            Self.pack(id: "b", coverURL: remoteURL.absoluteString),
            Self.pack(id: "builtin-without-remote", coverURL: nil),
        ])

        XCTAssertEqual(calls.value, 1)
    }

    private static func word(_ id: String) -> WordEntry {
        WordEntry(id: id, word: id, meaningZh: "meaning", category: "test", difficulty: 1)
    }

    private static func pack(id: String, coverURL: String?) -> Pack {
        Pack(
            id: id,
            title: id,
            subtitle: "Test",
            story: "Test",
            scene: SceneMetadata(spellbookCoverUrl: coverURL),
            words: [Self.word("\(id)-word")]
        )
    }

    private static func temporaryDirectory() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("SpellbookCoverCacheTests-\(UUID().uuidString)", isDirectory: true)
    }

    private static func stat(wordId: String, seenCount: Int, memoryState: WordMemoryState) -> WordLearningStat {
        WordLearningStat(
            wordId: wordId,
            seenCount: seenCount,
            correctCount: memoryState == .mastered ? seenCount : 0,
            wrongCount: 0,
            lastAnsweredAt: Date(timeIntervalSince1970: 0),
            memoryState: memoryState
        )
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}
