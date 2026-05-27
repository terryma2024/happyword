import Foundation

struct PerfectAdventureRotationResult: Equatable {
    var rotated = false
    var swappedOutId = ""
    var swappedInId = ""
}

enum PackActivationResult: Equatable {
    case activated
    case deactivated
    case activatedAutoClosed
    case refusedAllPinned
}

struct PackActivationChange: Equatable {
    var result: PackActivationResult
    var activatedId = ""
    var deactivatedId = ""
    var autoClosedId = ""
}

private struct PackSelectionSnapshot: Codable, Equatable {
    var activePackIds: [String]
    var pinnedPackIds: [String]
    var selectedPackId: String
    var perfectScoresByPack: [String: Int]
}

final class PackSelectionStore: ObservableObject {
    static let maxActivePacks = 10
    static let perfectThreshold = 3
    private static let storageKey = "wordmagic_pack_selection_v1"

    @Published private(set) var activePackIds: [String]
    @Published private(set) var pinnedPackIds: Set<String>
    @Published private(set) var selectedPackId: String

    private var perfectScoresByPack: [String: Int]
    private let defaults: UserDefaults?

    init(defaultIds: [String] = Pack.builtin.map(\.id), defaults: UserDefaults? = nil) {
        self.defaults = defaults
        if ProcessInfo.processInfo.arguments.contains("-UITestResetState") {
            defaults?.removeObject(forKey: Self.storageKey)
        }
        let fallbackIds = Array(Self.unique(defaultIds).prefix(Self.maxActivePacks))
        if let data = defaults?.data(forKey: Self.storageKey),
           let snapshot = try? JSONDecoder().decode(PackSelectionSnapshot.self, from: data) {
            let restoredActiveIds = Array(Self.unique(snapshot.activePackIds).prefix(Self.maxActivePacks))
            activePackIds = restoredActiveIds
            pinnedPackIds = Set(snapshot.pinnedPackIds).intersection(Set(restoredActiveIds))
            selectedPackId = snapshot.selectedPackId.isEmpty ? (restoredActiveIds.first ?? fallbackIds.first ?? "") : snapshot.selectedPackId
            perfectScoresByPack = snapshot.perfectScoresByPack.filter { $0.value > 0 }
        } else {
            activePackIds = fallbackIds
            pinnedPackIds = []
            selectedPackId = fallbackIds.first ?? ""
            perfectScoresByPack = [:]
        }
    }

    @discardableResult
    func setActive(_ ids: [String]) -> Bool {
        guard ids.count <= Self.maxActivePacks else { return false }
        guard Set(ids).count == ids.count else { return false }
        activePackIds = ids
        pinnedPackIds = pinnedPackIds.intersection(Set(ids))
        save()
        return true
    }

    @discardableResult
    func toggleActive(_ id: String) -> PackActivationChange {
        if activePackIds.contains(id) {
            activePackIds.removeAll { $0 == id }
            pinnedPackIds.remove(id)
            save()
            return PackActivationChange(result: .deactivated, deactivatedId: id)
        }
        guard activePackIds.count < Self.maxActivePacks else {
            guard let victim = activePackIds.first(where: { !pinnedPackIds.contains($0) }) else {
                return PackActivationChange(result: .refusedAllPinned, activatedId: id)
            }
            activePackIds.removeAll { $0 == victim }
            pinnedPackIds.remove(victim)
            activePackIds.append(id)
            save()
            return PackActivationChange(result: .activatedAutoClosed, activatedId: id, autoClosedId: victim)
        }
        activePackIds.append(id)
        save()
        return PackActivationChange(result: .activated, activatedId: id)
    }

    @discardableResult
    func togglePin(_ id: String) -> Bool {
        guard activePackIds.contains(id) else { return false }
        if pinnedPackIds.contains(id) {
            pinnedPackIds.remove(id)
        } else {
            pinnedPackIds.insert(id)
        }
        save()
        return true
    }

    func setSelectedPackId(_ id: String) {
        guard selectedPackId != id else { return }
        selectedPackId = id
        save()
    }

    func perfectScore(for id: String) -> Int {
        perfectScoresByPack[id, default: 0]
    }

    @discardableResult
    func recordPerfectAdventure(on packId: String, candidates: [String]) -> PerfectAdventureRotationResult {
        perfectScoresByPack[packId, default: 0] += 1
        var result = PerfectAdventureRotationResult()
        guard activePackIds.contains(packId),
              !pinnedPackIds.contains(packId),
              perfectScoresByPack[packId, default: 0] >= Self.perfectThreshold,
              let candidate = candidates.first(where: { !activePackIds.contains($0) })
        else {
            save()
            return result
        }

        activePackIds.removeAll { $0 == packId }
        activePackIds.append(candidate)
        perfectScoresByPack[packId] = 0
        save()
        result.rotated = true
        result.swappedOutId = packId
        result.swappedInId = candidate
        return result
    }

    func prune(availableIds: Set<String>) {
        let oldActive = activePackIds
        let oldPinned = pinnedPackIds
        let oldScores = perfectScoresByPack
        activePackIds = activePackIds.filter { availableIds.contains($0) }
        pinnedPackIds = pinnedPackIds.intersection(availableIds)
        perfectScoresByPack = perfectScoresByPack.filter { availableIds.contains($0.key) }
        if oldActive != activePackIds || oldPinned != pinnedPackIds || oldScores != perfectScoresByPack {
            save()
        }
    }

    private func save() {
        guard let defaults else { return }
        let snapshot = PackSelectionSnapshot(
            activePackIds: activePackIds,
            pinnedPackIds: Array(pinnedPackIds).sorted(),
            selectedPackId: selectedPackId,
            perfectScoresByPack: perfectScoresByPack
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    private static func unique(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }
}
