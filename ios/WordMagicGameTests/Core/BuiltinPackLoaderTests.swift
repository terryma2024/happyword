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
        XCTAssertEqual(packs.map(\.words.count), [15, 15, 15, 15, 15])

        let fruit = try XCTUnwrap(packs.first)
        XCTAssertEqual(fruit.words.first?.id, "fruit-apple")
        XCTAssertEqual(fruit.words.first?.word, "apple")
        XCTAssertEqual(fruit.words.first?.meaningZh, "苹果")
        XCTAssertEqual(fruit.words.last?.id, "fruit-blueberry")
        XCTAssertEqual(fruit.words.last?.word, "blueberry")
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
        XCTAssertEqual(try XCTUnwrap(packs.first { $0.id == "ocean-realm" }).words.last?.word, "seaweed")
    }

    func testIOSBuiltinPacksMatchHarmonyRawfileOrderAndWordCounts() {
        XCTAssertEqual(Pack.builtin.map(\.id), ["fruit-forest", "school-castle", "home-cottage", "animal-safari", "ocean-realm"])
        XCTAssertEqual(Pack.builtin.map(\.words.count), [15, 15, 15, 15, 15])
    }

    func testIOSBuiltinPacksCarryBilingualLittleStories() throws {
        let expectedStoryEnByPack = [
            "fruit-forest": "Tiny lanterns glow as fruit friends guide each new word.",
            "school-castle": "The school castle rings its bell and opens a word quest.",
            "home-cottage": "A cozy cottage hums softly while home words wake up.",
            "animal-safari": "Friendly animals leave paw prints toward today's word trail.",
            "ocean-realm": "Blue waves sparkle as sea friends whisper new words.",
        ]
        let expectedStoryZhByPack = [
            "fruit-forest": "果林里的小灯亮起，水果朋友带孩子认识新的单词。",
            "school-castle": "校园城堡敲响铃声，打开一场单词小冒险。",
            "home-cottage": "温暖小屋轻轻哼唱，家里的单词一个个醒来。",
            "animal-safari": "友好的动物留下脚印，带孩子走上今天的单词小路。",
            "ocean-realm": "蓝色海浪闪闪发光，海洋朋友悄悄送来新的单词。",
        ]

        for pack in Pack.builtin {
            XCTAssertEqual(pack.scene.storyEn, expectedStoryEnByPack[pack.id], pack.id)
            XCTAssertEqual(pack.scene.storyZh, expectedStoryZhByPack[pack.id], pack.id)
        }
    }

    func testIOSBuiltinPacksIncludeV092AddedSentenceReadyWords() throws {
        let expectedIdsByPack = [
            "fruit-forest": ["fruit-strawberry", "fruit-pineapple", "fruit-watermelon", "fruit-kiwi", "fruit-blueberry"],
            "school-castle": ["place-restaurant", "place-cinema", "place-airport", "place-playground", "place-bookstore"],
            "home-cottage": ["home-kitchen", "home-bathroom", "home-clock", "home-phone", "home-fridge"],
            "animal-safari": ["animal-bird", "animal-elephant", "animal-monkey", "animal-rabbit", "animal-panda"],
            "ocean-realm": ["ocean-shell", "ocean-coral", "ocean-beach", "ocean-wave", "ocean-seaweed"],
        ]

        for (packId, ids) in expectedIdsByPack {
            let pack = try XCTUnwrap(Pack.builtin.first { $0.id == packId })
            let wordIds = Set(pack.words.map(\.id))
            XCTAssertTrue(ids.allSatisfy { wordIds.contains($0) }, "\(packId) missing V0.9.2 words")
            for id in ids {
                let word = try XCTUnwrap(pack.words.first { $0.id == id })
                XCTAssertTrue(
                    BattleQuestionTypePolicy.wordSupportsQuestionType(word, typeId: QuestionKind.sentenceCloze.rawValue),
                    "\(packId) \(id) cannot generate sentence cloze"
                )
            }
        }
    }

    func testIOSBuiltinPacksHaveSentenceClozeExamplesForEveryWord() {
        for pack in Pack.builtin {
            for word in pack.words {
                XCTAssertNotNil(word.example, "\(pack.id) \(word.id) missing example")
                XCTAssertTrue(BattleQuestionTypePolicy.wordSupportsQuestionType(word, typeId: QuestionKind.sentenceCloze.rawValue), "\(pack.id) \(word.id) cannot generate sentence cloze")
            }
        }
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
