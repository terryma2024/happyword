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
            SceneMetadata(bgPrimary: "#EAF7FF", bgAccent: "#FFE3C2", bossName: "Dragon"),
            SceneMetadata(bgPrimary: "#F3F8E7", bgAccent: "#FFD8E0", bossName: "Phoenix"),
            SceneMetadata(bgPrimary: "#F4ECFF", bgAccent: "#DDEFFF", bossName: "Witch"),
        ]
        return palette[abs(djb2(id)) % palette.count]
    }

    private static func djb2(_ text: String) -> Int {
        text.unicodeScalars.reduce(5381) { hash, scalar in
            ((hash << 5) &+ hash) &+ Int(scalar.value)
        }
    }
}

private extension Pack {
    func withSceneFallback(builtinById: [String: Pack]) -> Pack {
        guard scene.isEmpty else { return self }
        var copy = self
        if let siblingScene = builtinById[id]?.scene, !siblingScene.isEmpty {
            copy.scene = siblingScene
        } else {
            copy.scene = PackLibrary.fallbackScene(for: id)
        }
        return copy
    }
}
