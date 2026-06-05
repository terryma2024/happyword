@testable import WordMagicGame
import XCTest

final class MonsterCodexTests: XCTestCase {
    func testMonsterCodexMatchesHarmonyRosterOrderAndCount() {
        XCTAssertEqual(MonsterCodex.entries.count, 100)
        XCTAssertEqual(MonsterCodex.entries.prefix(3).map(\.nameEn), ["软泥小灵", "书页僵僵", "云眠巨龙"])
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
        XCTAssertTrue(first.descriptionZh.contains("软泥小灵是一只软软的小精灵"))
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
        XCTAssertEqual(MonsterCodex.entry(catalogIndex1Based: 101).nameEn, "软泥小灵")
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

    func testBattleLevelLabelsUseLNotation() {
        XCTAssertEqual(MonsterLevel.beginner.battleLabel, "L1")
        XCTAssertEqual(MonsterLevel.intermediate.battleLabel, "L2")
        XCTAssertEqual(MonsterLevel.advanced.battleLabel, "L3")
        XCTAssertEqual(MonsterLevel.super.battleLabel, "L4")
    }

    @MainActor
    func testProgressParseDefaultsToEmptySnapshot() {
        let snapshot = MonsterProgressStore.parseSnapshot("")

        XCTAssertEqual(snapshot.version, 1)
        XCTAssertEqual(snapshot.records, [])
    }

    @MainActor
    func testProgressParseFiltersInvalidRecordsAndNormalizesMilestones() {
        let snapshot = MonsterProgressStore.parseSnapshot("""
        {"version":2,"records":[
          {"catalogIndex":1,"encountered":true,"defeatCount":51,"claimedMilestones":[50,50,25,100]},
          {"catalogIndex":0,"encountered":true,"defeatCount":9,"claimedMilestones":[50]},
          {"catalogIndex":2,"encountered":false,"defeatCount":-3,"claimedMilestones":[100]}
        ]}
        """)

        XCTAssertEqual(snapshot.version, 2)
        XCTAssertEqual(snapshot.records.count, 2)
        XCTAssertEqual(snapshot.record(catalogIndex: 1)?.claimedMilestones, [50, 100])
        XCTAssertEqual(snapshot.record(catalogIndex: 2)?.defeatCount, 0)
        XCTAssertEqual(snapshot.record(catalogIndex: 2)?.claimedMilestones, [100])
    }

    @MainActor
    func testProgressEncounterRevealsWithoutIncrementingDefeatCount() {
        let store = MonsterProgressStore(defaults: nil)

        store.recordEncounter(catalogIndex: 3)

        let record = store.record(for: 3)
        XCTAssertTrue(record.encountered)
        XCTAssertEqual(record.defeatCount, 0)
    }

    @MainActor
    func testProgressDefeatMarksEncounteredAndIncrementsOnlyThatMonster() {
        let store = MonsterProgressStore(defaults: nil)

        store.recordDefeat(catalogIndex: 2)
        store.recordDefeat(catalogIndex: 2)
        store.recordDefeat(catalogIndex: 4)

        XCTAssertTrue(store.record(for: 2).encountered)
        XCTAssertEqual(store.record(for: 2).defeatCount, 2)
        XCTAssertEqual(store.record(for: 4).defeatCount, 1)
        XCTAssertEqual(store.record(for: 5).defeatCount, 0)
    }

    @MainActor
    func testProgressRewardStateShowsDisabledProgressEnabledAndClaimed() {
        var state = MonsterProgressStore.rewardState(defeatCount: 17, claimed: false, milestone: 50)
        XCTAssertFalse(state.enabled)
        XCTAssertEqual(state.label, "50 金币 17/50")

        state = MonsterProgressStore.rewardState(defeatCount: 50, claimed: false, milestone: 50)
        XCTAssertTrue(state.enabled)
        XCTAssertEqual(state.label, "领 50 金币")

        state = MonsterProgressStore.rewardState(defeatCount: 100, claimed: true, milestone: 100)
        XCTAssertFalse(state.enabled)
        XCTAssertEqual(state.label, "已领 100 金币")
    }

    @MainActor
    func testProgressCanCatchUpClaimFiftyAndHundredAtOneHundredDefeats() {
        let store = MonsterProgressStore(defaults: nil)
        let account = CoinAccount(balance: 0, defaults: nil)
        for _ in 0..<100 {
            store.recordDefeat(catalogIndex: 1)
        }

        XCTAssertTrue(store.claimReward(catalogIndex: 1, milestone: 50, coins: account, now: Date(timeIntervalSince1970: 1)))
        XCTAssertTrue(store.claimReward(catalogIndex: 1, milestone: 100, coins: account, now: Date(timeIntervalSince1970: 2)))

        XCTAssertEqual(account.balance, 150)
        XCTAssertEqual(store.record(for: 1).defeatCount, 100)
    }

    @MainActor
    func testProgressClaimRewardRejectsDuplicatesAndUnderThreshold() {
        let store = MonsterProgressStore(defaults: nil)
        let account = CoinAccount(balance: 0, defaults: nil)
        for _ in 0..<50 {
            store.recordDefeat(catalogIndex: 1)
        }

        XCTAssertFalse(store.claimReward(catalogIndex: 1, milestone: 100, coins: account))
        XCTAssertTrue(store.claimReward(catalogIndex: 1, milestone: 50, coins: account))
        XCTAssertFalse(store.claimReward(catalogIndex: 1, milestone: 50, coins: account))
        XCTAssertEqual(account.balance, 50)
    }

    @MainActor
    func testProgressMaskedQuestionMarksPreservesCharacterCount() {
        XCTAssertEqual(MonsterProgressStore.maskedQuestionMarks("软泥小灵"), "????")
        XCTAssertEqual(MonsterProgressStore.maskedQuestionMarks("「普通怪物」"), "??????")
        XCTAssertEqual(MonsterProgressStore.maskedQuestionMarks("Dragon 是住在云朵后面"), "??????????????")
    }

    @MainActor
    func testCapFreeCreditBypassesDailyCapWithoutChangingTodayEarned() {
        let account = CoinAccount(balance: 0, defaults: nil)
        XCTAssertEqual(account.earn(amount: CoinAccount.dailyCap, reason: .todayReward), CoinAccount.dailyCap)

        let credited = account.creditMonsterCodexReward(reason: "monster-codex:50:1", amount: 50)

        XCTAssertEqual(credited, 50)
        XCTAssertEqual(account.balance, CoinAccount.dailyCap + 50)
        XCTAssertEqual(account.todayEarnedForTesting(), CoinAccount.dailyCap)
        XCTAssertEqual(account.transactions.first?.id, "monster-codex:50:1")
    }
}
