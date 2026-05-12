@testable import WordMagicGame
import XCTest

final class BuiltinPackLoaderTests: XCTestCase {
    func testHarmonyRawfilesParseInCanonicalOrderAndPreserveMetadata() throws {
        let packs = try Self.harmonyBuiltinFileNames.map { fileName in
            let url = Self.repoRoot
                .appendingPathComponent("harmonyos/entry/src/main/resources/rawfile/data/builtin")
                .appendingPathComponent(fileName)
            let data = try Data(contentsOf: url)
            return try BuiltinPackLoader.parsePack(data: data)
        }

        XCTAssertEqual(packs.map(\.id), ["fruit-forest", "school-castle", "home-cottage", "animal-safari", "ocean-realm"])
        XCTAssertEqual(packs.map(\.title), ["Fruit Forest", "School Castle", "Home Cottage", "Animal Safari", "Ocean Realm"])
        XCTAssertEqual(packs.map(\.labelZh), ["水果森林", "校园城堡", "温馨小屋", "动物大冒险", "深海王国"])
        XCTAssertEqual(packs.map(\.words.count), [10, 10, 10, 10, 10])

        let fruit = try XCTUnwrap(packs.first)
        XCTAssertEqual(fruit.words.first?.id, "fruit-apple")
        XCTAssertEqual(fruit.words.first?.word, "apple")
        XCTAssertEqual(fruit.words.first?.meaningZh, "苹果")
        XCTAssertEqual(fruit.words.last?.id, "fruit-cherry")
        XCTAssertEqual(fruit.words.last?.word, "cherry")
        XCTAssertEqual(fruit.scene.bgPrimary, "#FFF6E0")
        XCTAssertEqual(fruit.scene.bgAccent, "#FFD49A")
        XCTAssertEqual(fruit.scene.bossName, "Orchard Sentinel")
        XCTAssertEqual(Array(fruit.scene.bossCandidates.prefix(3)), [4, 5, 6])
        XCTAssertEqual(fruit.scene.bossCandidates.count, 19)
        XCTAssertEqual(fruit.scene.monsterPlan.count, 5)
        XCTAssertEqual(fruit.scene.monsterPlan.first, MonsterPlanSlot(kind: .normal, catalogIndex: 1))
        XCTAssertEqual(fruit.scene.monsterPlan.last, MonsterPlanSlot(kind: .boss, catalogIndex: 4))

        XCTAssertTrue(try XCTUnwrap(packs.first { $0.id == "school-castle" }).words.contains { $0.id == "place-supermarket" })
        XCTAssertEqual(try XCTUnwrap(packs.first { $0.id == "home-cottage" }).words.first?.word, "TV")
        XCTAssertEqual(try XCTUnwrap(packs.first { $0.id == "animal-safari" }).words.first?.word, "cat")
        XCTAssertEqual(try XCTUnwrap(packs.first { $0.id == "ocean-realm" }).words.last?.word, "jellyfish")
    }

    func testIOSBuiltinPacksMatchHarmonyRawfileOrderAndWordCounts() {
        XCTAssertEqual(Pack.builtin.map(\.id), ["fruit-forest", "school-castle", "home-cottage", "animal-safari", "ocean-realm"])
        XCTAssertEqual(Pack.builtin.map(\.words.count), [10, 10, 10, 10, 10])
    }

    private static let harmonyBuiltinFileNames = [
        "fruit-forest.json",
        "school-castle.json",
        "home-cottage.json",
        "animal-safari.json",
        "ocean-realm.json",
    ]

    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
