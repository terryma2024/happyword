@testable import WordMagicGame
import XCTest

final class MonsterCodexTests: XCTestCase {
    func testMonsterCodexMatchesHarmonyRosterOrderAndCount() {
        XCTAssertEqual(MonsterCodex.entries.count, 100)
        XCTAssertEqual(MonsterCodex.entries.prefix(3).map(\.nameEn), ["Slime", "Zombie", "Dragon"])
        XCTAssertEqual(
            MonsterCodex.entries.suffix(7).map(\.nameEn),
            ["Toadstool Ogre", "Toy Soldier", "Porcelain Doll", "Button Golem", "Sock Dragon", "Kite Serpent", "Music Box Fairy"]
        )
    }

    func testMonsterCodexEntriesExposeKindCopyAndAssetNames() {
        let first = MonsterCodex.entries[0]
        let zombie = MonsterCodex.entries[1]
        let kraken = MonsterCodex.entries[9]
        let last = MonsterCodex.entries[99]

        XCTAssertEqual(first.kindLabelZh, "普通怪物")
        XCTAssertTrue(first.descriptionZh.contains("Slime 是一只软软的小精灵"))
        XCTAssertEqual(first.assetName, "CharacterSlime")

        XCTAssertEqual(zombie.kindLabelZh, "拼写专家")
        XCTAssertEqual(zombie.assetName, "CharacterZombie")

        XCTAssertEqual(kraken.nameEn, "Kraken")
        XCTAssertEqual(kraken.kindLabelZh, "深海歌唱家")
        XCTAssertEqual(kraken.assetName, "CharacterKraken")

        XCTAssertEqual(last.nameEn, "Music Box Fairy")
        XCTAssertEqual(last.kindLabelZh, "八音盒仙子")
        XCTAssertEqual(last.assetName, "CharacterMusicBoxFairy")
    }

    func testBattleCatalogLookupWrapsThroughExpandedRoster() {
        XCTAssertEqual(MonsterCodex.entry(catalogIndex1Based: 11).nameEn, "Jellyfish")
        XCTAssertEqual(MonsterCodex.entry(catalogIndex1Based: 101).nameEn, "Slime")
    }

    func testMonsterCodexExposesHarmonyLevelDistribution() {
        XCTAssertEqual(MonsterCodex.entry(catalogIndex1Based: 1).level, .beginner)
        XCTAssertEqual(MonsterCodex.entry(catalogIndex1Based: 2).level, .intermediate)
        XCTAssertEqual(MonsterCodex.entry(catalogIndex1Based: 8).level, .advanced)
        XCTAssertEqual(MonsterCodex.entry(catalogIndex1Based: 10).level, .super)
        XCTAssertEqual(MonsterCodex.entry(catalogIndex1Based: 110).level, .super)

        let counts = Dictionary(grouping: MonsterCodex.entries, by: \.level).mapValues(\.count)
        XCTAssertEqual(counts[.beginner], 10)
        XCTAssertEqual(counts[.intermediate], 60)
        XCTAssertEqual(counts[.advanced], 20)
        XCTAssertEqual(counts[.super], 10)
        XCTAssertEqual(MonsterCodex.entry(catalogIndex1Based: 10).levelBadgeZh, "Super")
    }
}
