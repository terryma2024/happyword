@testable import WordMagicGame
import XCTest

final class LocalGrowthTests: XCTestCase {
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

    func testPackSelectionDefaultsCapPinPerfectRotationAndActivationAutoRotate() {
        let initial = ["forest", "home", "park", "school", "castle", "ocean", "space", "snacks", "animals", "colors"]
        let store = PackSelectionStore(defaultIds: initial)
        XCTAssertEqual(store.activePackIds, initial)
        XCTAssertEqual(PackSelectionStore.maxActivePacks, 10)

        XCTAssertFalse(store.setActive(initial + ["extra"]))
        XCTAssertFalse(store.setActive(["forest", "forest"]))

        XCTAssertTrue(store.togglePin("forest"))
        XCTAssertTrue(store.pinnedPackIds.contains("forest"))
        XCTAssertFalse(store.togglePin("missing"))

        let pinnedResult = store.recordPerfectAdventure(on: "forest", candidates: ["ocean"])
        XCTAssertFalse(pinnedResult.rotated)
        XCTAssertEqual(store.activePackIds, initial)

        _ = store.recordPerfectAdventure(on: "home", candidates: ["ocean"])
        _ = store.recordPerfectAdventure(on: "home", candidates: ["ocean"])
        let result = store.recordPerfectAdventure(on: "home", candidates: ["rainbow"])
        XCTAssertTrue(result.rotated)
        XCTAssertEqual(result.swappedOutId, "home")
        XCTAssertEqual(result.swappedInId, "rainbow")
        XCTAssertEqual(store.activePackIds, ["forest", "park", "school", "castle", "ocean", "space", "snacks", "animals", "colors", "rainbow"])

        let autoRotate = store.toggleActive("weather")
        XCTAssertEqual(autoRotate.result, .activatedAutoClosed)
        XCTAssertEqual(autoRotate.autoClosedId, "park")
        XCTAssertEqual(autoRotate.activatedId, "weather")
        XCTAssertEqual(store.activePackIds, ["forest", "school", "castle", "ocean", "space", "snacks", "animals", "colors", "rainbow", "weather"])

        for id in store.activePackIds where !store.pinnedPackIds.contains(id) {
            XCTAssertTrue(store.togglePin(id))
        }
        let refused = store.toggleActive("music")
        XCTAssertEqual(refused.result, .refusedAllPinned)
        XCTAssertEqual(store.activePackIds.count, PackSelectionStore.maxActivePacks)
        XCTAssertFalse(store.activePackIds.contains("music"))
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

    @MainActor
    func testCheckInStoreAwardsWeeklyBonusOnceAfterSevenDayStreak() {
        let defaults = isolatedDefaults(name: "checkin-weekly-bonus")
        defer { defaults.removePersistentDomain(forName: "WordMagicGameTests.checkin-weekly-bonus") }
        let store = CheckInStore(defaults: defaults)
        let coins = CoinAccount(balance: 0)
        let start = date(year: 2026, month: 5, day: 1)

        for offset in 0..<6 {
            let result = store.recordWin(now: addingDays(offset, to: start), coins: coins)
            XCTAssertTrue(result.changed)
            XCTAssertEqual(result.bonusCoins, 0)
        }

        let seventh = store.recordWin(now: addingDays(6, to: start), coins: coins)
        let replay = store.recordWin(now: addingDays(6, to: start), coins: coins)

        XCTAssertTrue(seventh.changed)
        XCTAssertEqual(seventh.bonusCoins, 50)
        XCTAssertEqual(seventh.currentStreak, 7)
        XCTAssertEqual(coins.balance, 50)
        XCTAssertFalse(replay.changed)
        XCTAssertEqual(replay.bonusCoins, 0)
        XCTAssertEqual(coins.balance, 50)
        XCTAssertEqual(store.snapshot.weeklyBonusDayKeys, ["2026-05-07"])
    }

    func testCheckInCalendarWeeksRebuildForVisibleMonth() {
        let may = CheckInCalendar.buildMonthWeeks(
            visibleMonth: date(year: 2026, month: 5, day: 24),
            checkedDayKeys: ["2026-05-07"]
        )
        let june = CheckInCalendar.buildMonthWeeks(
            visibleMonth: date(year: 2026, month: 6, day: 1),
            checkedDayKeys: ["2026-05-07", "2026-06-01"]
        )

        XCTAssertTrue(may.flatMap(\.cells).contains { $0.dayKey == "2026-05-07" && $0.checked })
        XCTAssertFalse(june.flatMap(\.cells).contains { $0.dayKey == "2026-05-07" && $0.inMonth })
        XCTAssertTrue(june.flatMap(\.cells).contains { $0.dayKey == "2026-06-01" && $0.checked })
    }

    func testLearningReportDedupeTotalsAndOrdersPackRows() {
        let shared = WordEntry(id: "shared", word: "apple", meaningZh: "苹果", category: "fruit", difficulty: 1)
        let inactiveSeenWord = DemoWords.words.first { $0.id == "home-door" }!
        let inactiveUnseenWord = DemoWords.words.first { $0.id == "home-window" }!
        let activePack = Pack(id: "forest", title: "Fruit Forest", subtitle: "", story: "", source: .builtin, words: [shared])
        let inactiveSeen = Pack(id: "family", title: "Family Pack", subtitle: "", story: "", source: .family, words: [shared, inactiveSeenWord])
        let inactiveUnseen = Pack(id: "quiet", title: "Quiet Pack", subtitle: "", story: "", source: .global, words: [inactiveUnseenWord])
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
        let pack = Pack.builtin[0]
        let plan = TodayPlanService().build(pack: pack, recorder: recorder, now: fixedDate())

        XCTAssertEqual(plan.packId, "fruit-forest")
        XCTAssertTrue(plan.review.contains { $0.id == "fruit-apple" })
        XCTAssertFalse(plan.newWords.isEmpty)
        let bucketedIds = (plan.review + plan.learning + plan.newWords).map(\.id)
        XCTAssertEqual(bucketedIds.count, pack.words.count)
        XCTAssertEqual(Set(bucketedIds).count, pack.words.count)
    }

    func testHomeScenePaletteUsesSelectedPackSceneColors() {
        let palette = HomeScenePalette(scene: SceneMetadata(bgPrimary: "#123456", bgAccent: "#ABCDEF"))

        XCTAssertEqual(palette.primaryHex, "#123456")
        XCTAssertEqual(palette.accentHex, "#ABCDEF")
    }

    func testParentPinAcceptsExactlySixASCIIDigitsOnly() {
        XCTAssertTrue(GameConfig.isValidPin("123456"))
        XCTAssertFalse(GameConfig.isValidPin("12345"))
        XCTAssertFalse(GameConfig.isValidPin("1234567"))
        XCTAssertFalse(GameConfig.isValidPin("12345a"))
        XCTAssertFalse(GameConfig.isValidPin("１２３４５６"))
        XCTAssertFalse(GameConfig.isValidPin("12345①"))

        XCTAssertEqual(GameConfig.sanitizePinInput("12a34 5678"), "123456")
        XCTAssertEqual(GameConfig.sanitizePinInput("１２345①6"), "3456")
    }

    func testGiftBoxAnimationSpecMatchesHarmonyTimelineAndRibbons() {
        XCTAssertEqual(GiftBoxAnimationSpec.ribbonCount, 10)
        XCTAssertEqual(GiftBoxAnimationSpec.ribbonColors, ["#E63946", "#F4C430", "#457B9D", "#F78DA7"])
        XCTAssertEqual(GiftBoxAnimationSpec.ribbonPhase1Ms, 300)
        XCTAssertEqual(GiftBoxAnimationSpec.ribbonPhase2Ms, 600)
        XCTAssertEqual(GiftBoxAnimationSpec.ribbonClearDelayMs, 900)
        XCTAssertEqual(GiftBoxAnimationSpec.autoCloseDelayMs, 1500)
        XCTAssertEqual(GiftBoxAnimationSpec.modalTotalMs, 3180)

        let ribbons = GiftBoxAnimationSpec.generateRibbons(count: GiftBoxAnimationSpec.ribbonCount)

        XCTAssertEqual(ribbons.count, 10)
        XCTAssertEqual(ribbons.map(\.id), Array(0..<10))
        XCTAssertEqual(ribbons.map(\.angleDegrees), [-10, 42, 73, 104, 135, 187, 218, 249, 280, 332])
        XCTAssertEqual(ribbons.prefix(4).map(\.colorHex), GiftBoxAnimationSpec.ribbonColors)

        let right = GiftBoxAnimationSpec.ribbonFlyTarget(angleDegrees: 0)
        XCTAssertEqual(right.width, 90, accuracy: 0.001)
        XCTAssertEqual(right.height, -25, accuracy: 0.001)

        let up = GiftBoxAnimationSpec.ribbonFlyTarget(angleDegrees: 90)
        XCTAssertEqual(up.width, 0, accuracy: 0.001)
        XCTAssertEqual(up.height, 65, accuracy: 0.001)
    }

    private func fixedDate(timeIntervalSinceNow: TimeInterval = 0) -> Date {
        Date(timeIntervalSince1970: 1_800_000_000 + timeIntervalSinceNow)
    }

    private func date(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        return components.date!
    }

    private func addingDays(_ days: Int, to date: Date) -> Date {
        Calendar(identifier: .gregorian).date(byAdding: .day, value: days, to: date)!
    }

    private func isolatedDefaults(name: String) -> UserDefaults {
        let suiteName = "WordMagicGameTests.\(name)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
