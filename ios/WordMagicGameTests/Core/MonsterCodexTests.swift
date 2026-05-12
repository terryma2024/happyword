@testable import WordMagicGame
import XCTest

final class MonsterCodexTests: XCTestCase {
    func testMonsterCodexMatchesHarmonyRosterOrderAndCount() {
        XCTAssertEqual(MonsterCodex.entries.count, 10)
        XCTAssertEqual(MonsterCodex.entries.prefix(3).map(\.nameEn), ["Slime", "Zombie", "Dragon"])
        XCTAssertEqual(
            MonsterCodex.entries.suffix(7).map(\.nameEn),
            ["Pumpkin King", "Imp King", "Phoenix", "Witch", "Snow Queen", "Unicorn", "Kraken"]
        )
    }

    func testMonsterCodexEntriesExposeKindCopyAndAssetNames() {
        let first = MonsterCodex.entries[0]
        let zombie = MonsterCodex.entries[1]
        let last = MonsterCodex.entries[9]

        XCTAssertEqual(first.kindLabelZh, "普通怪物")
        XCTAssertTrue(first.descriptionZh.contains("Slime 是一只软软的小精灵"))
        XCTAssertEqual(first.assetName, "CharacterSlime")

        XCTAssertEqual(zombie.kindLabelZh, "拼写专家")
        XCTAssertEqual(zombie.assetName, "CharacterZombie")

        XCTAssertEqual(last.nameEn, "Kraken")
        XCTAssertEqual(last.kindLabelZh, "深海歌唱家")
        XCTAssertEqual(last.assetName, "CharacterKraken")
    }
}
