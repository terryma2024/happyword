import Foundation

struct PackLibrary: Equatable {
    private var builtin: [Pack]
    private var global: [Pack]
    private var family: [Pack]

    init(builtin: [Pack] = Pack.builtin, global: [Pack] = [], family: [Pack] = []) {
        self.builtin = builtin
        self.global = global
        self.family = family
    }

    func builtinIds() -> [String] {
        builtin.map(\.id)
    }

    func builtinPacks() -> [Pack] {
        builtin
    }

    func allPacks() -> [Pack] {
        let builtinById = Dictionary(uniqueKeysWithValues: builtin.map { ($0.id, $0) })
        var orderedIds: [String] = []
        var merged: [String: Pack] = [:]

        func upsert(_ pack: Pack) {
            if merged[pack.id] == nil {
                orderedIds.append(pack.id)
            }
            merged[pack.id] = pack.withSceneFallback(builtinById: builtinById)
        }

        builtin.forEach(upsert)
        global.forEach(upsert)
        family.forEach(upsert)
        return orderedIds.compactMap { merged[$0] }
    }

    func pack(id: String) -> Pack? {
        allPacks().first { $0.id == id }
    }

    func activePacks(ids: [String]) -> [Pack] {
        ids.compactMap { pack(id: $0) }
    }

    static func fallbackScene(for id: String) -> SceneMetadata {
        let palette = [
            SceneMetadata(bgPrimary: "#EAF7FF", bgAccent: "#FFE3C2", bossName: "Dragon", bossCandidates: [3, 4, 5], monsterPlan: defaultMonsterPlan),
            SceneMetadata(bgPrimary: "#F3F8E7", bgAccent: "#FFD8E0", bossName: "Phoenix", bossCandidates: [6, 7, 8], monsterPlan: defaultMonsterPlan),
            SceneMetadata(bgPrimary: "#F4ECFF", bgAccent: "#DDEFFF", bossName: "Witch", bossCandidates: [7, 9, 10], monsterPlan: defaultMonsterPlan),
        ]
        return palette[abs(djb2(id)) % palette.count]
    }

    private static let defaultMonsterPlan = [
        MonsterPlanSlot(kind: .normal, catalogIndex: 1),
        MonsterPlanSlot(kind: .spelling, catalogIndex: 2),
        MonsterPlanSlot(kind: .review, catalogIndex: 3),
        MonsterPlanSlot(kind: .elite, catalogIndex: 4),
        MonsterPlanSlot(kind: .boss, catalogIndex: 5),
    ]

    private static func djb2(_ text: String) -> Int {
        text.unicodeScalars.reduce(5381) { hash, scalar in
            ((hash << 5) &+ hash) &+ Int(scalar.value)
        }
    }
}

private extension Pack {
    func withSceneFallback(builtinById: [String: Pack]) -> Pack {
        var copy = self
        let fallback: SceneMetadata
        if let siblingScene = builtinById[id]?.scene, !siblingScene.isEmpty {
            fallback = siblingScene
        } else {
            fallback = PackLibrary.fallbackScene(for: id)
        }
        copy.scene = scene.fillingMissingGameplayFields(from: fallback)
        return copy
    }
}

private extension SceneMetadata {
    func fillingMissingGameplayFields(from fallback: SceneMetadata) -> SceneMetadata {
        var copy = self
        if copy.bgPrimary.isEmpty || copy.bgPrimary == "#FFFFFF" {
            copy.bgPrimary = fallback.bgPrimary
        }
        if copy.bgAccent.isEmpty || copy.bgAccent == "#FFFFFF" {
            copy.bgAccent = fallback.bgAccent
        }
        if copy.bossName.isEmpty {
            copy.bossName = fallback.bossName
        }
        if copy.bossCandidates.isEmpty {
            copy.bossCandidates = fallback.bossCandidates
        }
        if copy.monsterPlan.isEmpty {
            copy.monsterPlan = fallback.monsterPlan
        }
        if copy.storyEn == nil {
            copy.storyEn = fallback.storyEn
        }
        if copy.storyZh == nil {
            copy.storyZh = fallback.storyZh
        }
        if copy.spellbookCoverUrl == nil {
            copy.spellbookCoverUrl = fallback.spellbookCoverUrl
        }
        return copy
    }
}
