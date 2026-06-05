import Foundation
import SwiftUI

enum SpellbookCardState: String, Equatable {
    case locked
    case seen
    case mastered
}

struct SpellbookProgress: Equatable {
    var totalCount: Int
    var seenCount: Int
    var masteredCount: Int

    var isComplete: Bool {
        totalCount > 0 && masteredCount == totalCount
    }
}

enum SpellbookService {
    static let rewardCoins = 50

    static func cardState(for word: WordEntry, stat: WordLearningStat?) -> SpellbookCardState {
        guard word.isValid, let stat, stat.seenCount > 0 else { return .locked }
        return stat.memoryState == .mastered ? .mastered : .seen
    }

    static func progress(words: [WordEntry], statsByWordId: [String: WordLearningStat]) -> SpellbookProgress {
        var seenCount = 0
        var masteredCount = 0
        for word in words {
            switch cardState(for: word, stat: statsByWordId[word.id]) {
            case .locked:
                break
            case .seen:
                seenCount += 1
            case .mastered:
                seenCount += 1
                masteredCount += 1
            }
        }
        return SpellbookProgress(totalCount: words.count, seenCount: seenCount, masteredCount: masteredCount)
    }
}

enum SpellbookCoverSource: Equatable {
    case bundledAsset(String)
    case cachedFile(URL)
    case remoteURL(URL)
}

final class SpellbookCoverCache: @unchecked Sendable {
    typealias Fetcher = @Sendable (URL) async throws -> Data

    private let directory: URL
    private let fetcher: Fetcher

    init(
        directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WordMagicGame/SpellbookCovers", isDirectory: true),
        fetcher: @escaping Fetcher = SpellbookCoverCache.defaultFetcher
    ) {
        self.directory = directory
        self.fetcher = fetcher
    }

    func source(for pack: Pack) -> SpellbookCoverSource {
        guard let remoteURL = Self.remoteURL(for: pack) else {
            return .bundledAsset(SpellbookCoverAsset.assetName(for: pack.id))
        }
        let cachedURL = fileURL(for: remoteURL)
        if FileManager.default.fileExists(atPath: cachedURL.path) {
            return .cachedFile(cachedURL)
        }
        return .remoteURL(remoteURL)
    }

    func prewarm(packs: [Pack]) async {
        var seen = Set<URL>()
        for pack in packs {
            guard let remoteURL = Self.remoteURL(for: pack), seen.insert(remoteURL).inserted else {
                continue
            }
            await cache(remoteURL)
        }
    }

    private func cache(_ remoteURL: URL) async {
        let destination = fileURL(for: remoteURL)
        if FileManager.default.fileExists(atPath: destination.path) {
            return
        }
        do {
            let data = try await fetcher(remoteURL)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: destination, options: [.atomic])
        } catch {
            return
        }
    }

    private func fileURL(for remoteURL: URL) -> URL {
        let extensionPart = remoteURL.pathExtension.isEmpty ? "img" : remoteURL.pathExtension
        return directory.appendingPathComponent("cover-\(Self.djb2(remoteURL.absoluteString)).\(extensionPart)")
    }

    private static func remoteURL(for pack: Pack) -> URL? {
        guard let raw = pack.scene.spellbookCoverUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else {
            return nil
        }
        return url
    }

    private static func defaultFetcher(_ url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw CloudHTTPError.unexpectedStatus(http.statusCode)
        }
        return data
    }

    private static func djb2(_ text: String) -> String {
        let hash = text.unicodeScalars.reduce(UInt64(5381)) { value, scalar in
            ((value << 5) &+ value) &+ UInt64(scalar.value)
        }
        return String(hash, radix: 16)
    }
}

private struct SpellbookCoverCacheEnvironmentKey: EnvironmentKey {
    static let defaultValue = SpellbookCoverCache()
}

private struct SpellbookCoverCacheVersionEnvironmentKey: EnvironmentKey {
    static let defaultValue = 0
}

extension EnvironmentValues {
    var spellbookCoverCache: SpellbookCoverCache {
        get { self[SpellbookCoverCacheEnvironmentKey.self] }
        set { self[SpellbookCoverCacheEnvironmentKey.self] = newValue }
    }

    var spellbookCoverCacheVersion: Int {
        get { self[SpellbookCoverCacheVersionEnvironmentKey.self] }
        set { self[SpellbookCoverCacheVersionEnvironmentKey.self] = newValue }
    }
}

@MainActor
final class SpellbookRewardStore: ObservableObject {
    private static let key = "wordmagic_spellbook_rewards/snapshot_v1"

    private struct Snapshot: Codable, Equatable {
        var version: Int = 1
        var claimedPackIds: [String] = []
    }

    @Published private(set) var claimedPackIds: Set<String>
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if ProcessInfo.processInfo.arguments.contains("-UITestResetState") {
            defaults.removeObject(forKey: Self.key)
        }
        if let data = defaults.data(forKey: Self.key),
           let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            claimedPackIds = Set(snapshot.claimedPackIds.map(Self.normalizePackId).filter { !$0.isEmpty })
        } else {
            claimedPackIds = []
        }
    }

    func isClaimed(packId: String) -> Bool {
        claimedPackIds.contains(Self.normalizePackId(packId))
    }

    func canClaim(packId: String, isComplete: Bool) -> Bool {
        let id = Self.normalizePackId(packId)
        return isComplete && !id.isEmpty && !claimedPackIds.contains(id)
    }

    @discardableResult
    func claim(packId: String, account: CoinAccount, now: Date = Date()) -> Bool {
        guard canClaim(packId: packId, isComplete: true) else { return false }
        let id = Self.normalizePackId(packId)
        account.creditSpellbookPackReward(packId: id, now: now)
        claimedPackIds.insert(id)
        save()
        return true
    }

    private func save() {
        let snapshot = Snapshot(claimedPackIds: claimedPackIds.sorted())
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: Self.key)
        }
    }

    private static func normalizePackId(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
