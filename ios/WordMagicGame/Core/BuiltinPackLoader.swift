import Foundation

enum BuiltinPackLoader {
    static let fileNames = [
        "fruit-forest",
        "school-castle",
        "home-cottage",
        "animal-safari",
        "ocean-realm",
    ]

    static func loadBundled(bundle: Bundle = .main) -> [Pack] {
        fileNames.compactMap { fileName in
            guard let url = bundle.url(forResource: fileName, withExtension: "json", subdirectory: "BuiltinPacks")
                    ?? bundle.url(forResource: fileName, withExtension: "json"),
                  let data = try? Data(contentsOf: url)
            else {
                return nil
            }
            return try? parsePack(data: data)
        }
    }

    static func parsePack(data: Data) throws -> Pack {
        let raw = try JSONDecoder().decode(RawBuiltinPack.self, from: data)
        return Pack(
            id: raw.packId,
            title: raw.name,
            labelZh: raw.labelZh,
            subtitle: raw.labelZh,
            story: raw.scene.storyZh ?? raw.labelZh,
            source: .builtin,
            version: raw.schemaVersion,
            scene: raw.scene,
            words: raw.words
        )
    }

    private struct RawBuiltinPack: Codable {
        var schemaVersion: Int
        var packId: String
        var name: String
        var labelZh: String
        var scene: SceneMetadata
        var words: [WordEntry]

        private enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case packId = "pack_id"
            case name
            case labelZh
            case scene
            case words
        }
    }
}
