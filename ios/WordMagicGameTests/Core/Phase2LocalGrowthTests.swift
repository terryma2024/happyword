@testable import WordMagicGame
import XCTest

final class Phase2LocalGrowthTests: XCTestCase {
    func testPackLibraryMergesFamilyOverGlobalOverBuiltinAndKeepsSceneFallback() {
        let builtin = Pack(
            id: "forest",
            title: "Fruit Forest",
            subtitle: "Starter",
            story: "builtin",
            source: .builtin,
            scene: SceneMetadata(bgPrimary: "#EAF7FF", bgAccent: "#FFD8A8", bossName: "Dragon"),
            words: [DemoWords.words[0]]
        )
        let global = Pack(
            id: "forest",
            title: "Global Forest",
            subtitle: "Official",
            story: "global",
            source: .global,
            words: [DemoWords.words[1]]
        )
        let family = Pack(
            id: "forest",
            title: "Family Forest",
            subtitle: "Home",
            story: "family",
            source: .family,
            words: [DemoWords.words[2]]
        )

        let library = PackLibrary(builtin: [builtin], global: [global], family: [family])

        XCTAssertEqual(library.allPacks().map(\.title), ["Family Forest"])
        XCTAssertEqual(library.pack(id: "forest")?.source, .family)
        XCTAssertEqual(library.pack(id: "forest")?.scene.bossName, "Dragon")
        XCTAssertEqual(library.builtinIds(), ["forest"])
    }

    func testPackSelectionDefaultsCapPinAndPerfectRotation() {
        let store = PackSelectionStore(defaultIds: ["forest", "home", "park", "school", "castle"])
        XCTAssertEqual(store.activePackIds, ["forest", "home", "park", "school", "castle"])

        XCTAssertFalse(store.setActive(["forest", "home", "park", "school", "castle", "ocean"]))
        XCTAssertFalse(store.setActive(["forest", "forest"]))

        XCTAssertTrue(store.togglePin("forest"))
        XCTAssertTrue(store.pinnedPackIds.contains("forest"))
        XCTAssertFalse(store.togglePin("ocean"))

        let pinnedResult = store.recordPerfectAdventure(on: "forest", candidates: ["ocean"])
        XCTAssertFalse(pinnedResult.rotated)
        XCTAssertEqual(store.activePackIds, ["forest", "home", "park", "school", "castle"])

        _ = store.recordPerfectAdventure(on: "home", candidates: ["ocean"])
        _ = store.recordPerfectAdventure(on: "home", candidates: ["ocean"])
        let result = store.recordPerfectAdventure(on: "home", candidates: ["ocean"])
        XCTAssertTrue(result.rotated)
        XCTAssertEqual(result.swappedOutId, "home")
        XCTAssertEqual(result.swappedInId, "ocean")
        XCTAssertEqual(store.activePackIds, ["forest", "park", "school", "castle", "ocean"])
    }

    @MainActor
    func testCoinWishlistAndRedemptionHistoryLocalLoop() {
        let coins = CoinAccount(balance: 0)
        XCTAssertEqual(coins.earn(stars: 3, now: fixedDate()), 3)
        XCTAssertEqual(coins.balance, 3)
        XCTAssertEqual(coins.earn(amount: 30, reason: .todayReward, now: fixedDate()), 17)
        XCTAssertEqual(coins.balance, 20)

        let wishlist = WishlistStore()
        let history = RedemptionHistoryStore()
        let customId = wishlist.addCustomWish(name: "贴纸", costCoins: 6, iconEmoji: "⭐", now: fixedDate())
        XCTAssertFalse(customId.isEmpty)
        XCTAssertTrue(wishlist.addCustomWish(name: "", costCoins: 6, iconEmoji: "⭐", now: fixedDate()).isEmpty)

        let record = wishlist.redeem(wishId: customId, coins: coins, history: history, now: fixedDate())
        XCTAssertEqual(record?.displayName, "贴纸")
        XCTAssertEqual(coins.balance, 14)
        XCTAssertEqual(history.records.first?.wishId, customId)
        XCTAssertEqual(history.records.count, 1)
    }

    func testLearningReportDedupeTotalsAndOrdersPackRows() {
        let shared = WordEntry(id: "shared", word: "apple", meaningZh: "苹果", category: "fruit", difficulty: 1)
        let activePack = Pack(id: "forest", title: "Fruit Forest", subtitle: "", story: "", source: .builtin, words: [shared])
        let inactiveSeen = Pack(id: "family", title: "Family Pack", subtitle: "", story: "", source: .family, words: [shared, DemoWords.words[3]])
        let inactiveUnseen = Pack(id: "quiet", title: "Quiet Pack", subtitle: "", story: "", source: .global, words: [DemoWords.words[4]])
        let library = PackLibrary(builtin: [activePack, inactiveSeen, inactiveUnseen])
        let recorder = LearningRecorder()
        recorder.record(wordId: "shared", correct: true, at: fixedDate())
        recorder.record(wordId: "home-door", correct: false, at: fixedDate())

        let report = LearningReportBuilder().build(library: library, activePackIds: ["forest"], recorder: recorder, now: fixedDate())

        XCTAssertEqual(report.totalSeenWords, 2)
        XCTAssertEqual(report.packRows.map(\.packId), ["forest", "family"])
        XCTAssertEqual(report.packRows[0].seenWords, 1)
        XCTAssertEqual(report.packRows[1].seenWords, 2)
    }

    func testTodayPlanBucketsSelectedPackWithoutMutatingBattle() {
        let recorder = LearningRecorder()
        recorder.record(wordId: "fruit-apple", correct: true, at: fixedDate(timeIntervalSinceNow: -86_400 * 3))
        let plan = TodayPlanService().build(pack: Pack.builtin[0], recorder: recorder, now: fixedDate())

        XCTAssertEqual(plan.packId, "forest")
        XCTAssertTrue(plan.review.contains { $0.id == "fruit-apple" })
        XCTAssertFalse(plan.learning.isEmpty)
        XCTAssertFalse(plan.newWords.isEmpty)
    }

    private func fixedDate(timeIntervalSinceNow: TimeInterval = 0) -> Date {
        Date(timeIntervalSince1970: 1_800_000_000 + timeIntervalSinceNow)
    }
}
