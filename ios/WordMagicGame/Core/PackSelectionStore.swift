import Foundation

struct PerfectAdventureRotationResult: Equatable {
    var rotated = false
    var swappedOutId = ""
    var swappedInId = ""
}

final class PackSelectionStore: ObservableObject {
    static let maxActivePacks = 5
    static let perfectThreshold = 3

    @Published private(set) var activePackIds: [String]
    @Published private(set) var pinnedPackIds: Set<String>

    private var perfectScoresByPack: [String: Int]

    init(defaultIds: [String] = Pack.builtin.map(\.id)) {
        activePackIds = Array(defaultIds.prefix(Self.maxActivePacks))
        pinnedPackIds = []
        perfectScoresByPack = [:]
    }

    @discardableResult
    func setActive(_ ids: [String]) -> Bool {
        guard ids.count <= Self.maxActivePacks else { return false }
        guard Set(ids).count == ids.count else { return false }
        activePackIds = ids
        pinnedPackIds = pinnedPackIds.intersection(Set(ids))
        return true
    }

    @discardableResult
    func toggleActive(_ id: String) -> Bool {
        if activePackIds.contains(id) {
            activePackIds.removeAll { $0 == id }
            pinnedPackIds.remove(id)
            return true
        }
        guard activePackIds.count < Self.maxActivePacks else { return false }
        activePackIds.append(id)
        return true
    }

    @discardableResult
    func togglePin(_ id: String) -> Bool {
        guard activePackIds.contains(id) else { return false }
        if pinnedPackIds.contains(id) {
            pinnedPackIds.remove(id)
        } else {
            pinnedPackIds.insert(id)
        }
        return true
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
            return result
        }

        activePackIds.removeAll { $0 == packId }
        activePackIds.append(candidate)
        perfectScoresByPack[packId] = 0
        result.rotated = true
        result.swappedOutId = packId
        result.swappedInId = candidate
        return result
    }

    func prune(availableIds: Set<String>) {
        activePackIds = activePackIds.filter { availableIds.contains($0) }
        pinnedPackIds = pinnedPackIds.intersection(availableIds)
    }
}
