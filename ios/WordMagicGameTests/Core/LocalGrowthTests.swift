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

    func testStoryAndCoverOnlyGlobalPackReceivesFallbackPaletteAndPreservesMetadata() {
        let scene = SceneMetadata(
            storyEn: "A tiny kitchen train carries bright new words.",
            storyZh: "厨房小火车载着闪亮的新单词出发。",
            spellbookCoverUrl: "https://cdn.example.test/covers/kitchen.png"
        )
        let global = Pack(
            id: "gpk-kitchen",
            title: "Kitchen Words",
            subtitle: "Kitchen",
            story: "Kitchen",
            source: .global,
            scene: scene,
            words: [DemoWords.words[0]]
        )

        let library = PackLibrary(builtin: [], global: [global], family: [])
        let resolved = library.pack(id: "gpk-kitchen")

        XCTAssertEqual(resolved?.scene.storyEn, scene.storyEn)
        XCTAssertEqual(resolved?.scene.storyZh, scene.storyZh)
        XCTAssertEqual(resolved?.scene.spellbookCoverUrl, scene.spellbookCoverUrl)
        XCTAssertNotEqual(resolved?.scene.bgPrimary, "")
        XCTAssertNotEqual(resolved?.scene.bgPrimary, "#FFFFFF")
        XCTAssertNotEqual(resolved?.scene.bgAccent, "")
        XCTAssertNotEqual(resolved?.scene.bgAccent, "#FFFFFF")
        XCTAssertNotEqual(resolved?.scene.bossName, "")
        XCTAssertFalse(resolved?.scene.bossCandidates.isEmpty ?? true)
        XCTAssertFalse(resolved?.scene.monsterPlan.isEmpty ?? true)
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
    func testCoordinatorRestoresPackSelectionAfterRelaunch() {
        let defaults = isolatedDefaults(name: "pack-selection-relaunch")
        defer { defaults.removePersistentDomain(forName: "WordMagicGameTests.pack-selection-relaunch") }
        let selectedPack = Pack.builtin[1]
        let disabledPack = Pack.builtin[0]

        let firstLaunch = AppCoordinator(configStore: GameConfigStore(defaults: defaults))
        firstLaunch.selectPack(selectedPack)
        firstLaunch.togglePackActive(disabledPack)

        let relaunched = AppCoordinator(configStore: GameConfigStore(defaults: defaults))

        XCTAssertEqual(relaunched.selectedPack.id, selectedPack.id)
        XCTAssertFalse(relaunched.packSelectionStore.activePackIds.contains(disabledPack.id))
        XCTAssertTrue(relaunched.packSelectionStore.activePackIds.contains(selectedPack.id))
    }

    func testPackManagerTitleTypographyFavorsLongNames() {
        XCTAssertLessThanOrEqual(PackManagerLayoutRules.headerTitleFontSize, 25)
        XCTAssertLessThanOrEqual(PackManagerLayoutRules.packTitleFontSize, 17)
        XCTAssertEqual(PackManagerLayoutRules.packTitleLineLimit, 2)
        XCTAssertLessThanOrEqual(PackManagerLayoutRules.packTitleMinimumScaleFactor, 0.9)
        XCTAssertGreaterThanOrEqual(PackManagerLayoutRules.packSourceIconSide, 30)
        XCTAssertGreaterThanOrEqual(PackManagerLayoutRules.packActionAreaWidth, 128)
    }

    @MainActor
    func testCoinWishlistAndRedemptionHistoryLocalLoop() {
        let coins = CoinAccount(balance: 0)
        XCTAssertEqual(coins.earn(stars: 3, now: fixedDate()), 3)
        XCTAssertEqual(coins.balance, 3)
        XCTAssertEqual(coins.earn(amount: CoinAccount.dailyCap, reason: .todayReward, now: fixedDate()), CoinAccount.dailyCap - 3)
        XCTAssertEqual(coins.balance, CoinAccount.dailyCap)

        let wishlist = WishlistStore()
        let history = RedemptionHistoryStore()
        let customId = wishlist.addCustomWish(name: "贴纸", costCoins: 6, iconEmoji: "⭐", now: fixedDate())
        XCTAssertFalse(customId.isEmpty)
        XCTAssertTrue(wishlist.addCustomWish(name: "", costCoins: 6, iconEmoji: "⭐", now: fixedDate()).isEmpty)

        let record = wishlist.redeem(wishId: customId, coins: coins, history: history, now: fixedDate())
        XCTAssertEqual(record?.displayName, "贴纸")
        XCTAssertEqual(coins.balance, CoinAccount.dailyCap - 6)
        XCTAssertEqual(history.records.first?.wishId, customId)
        XCTAssertEqual(history.records.count, 1)
    }

    @MainActor
    func testLocalGrowthStoresRestoreAfterRelaunch() {
        let defaults = isolatedDefaults(name: "local-growth-relaunch")
        defer { defaults.removePersistentDomain(forName: "WordMagicGameTests.local-growth-relaunch") }
        let firstCoins = CoinAccount(balance: 0, defaults: defaults)
        let firstWishlist = WishlistStore(defaults: defaults)
        let firstHistory = RedemptionHistoryStore(defaults: defaults)
        let firstLearning = LearningRecorder(defaults: defaults)
        let customId = firstWishlist.addCustomWish(name: "贴纸", costCoins: 6, iconEmoji: "⭐", now: fixedDate())

        _ = firstCoins.earn(amount: 8, reason: .todayReward, now: fixedDate())
        _ = firstWishlist.redeem(wishId: customId, coins: firstCoins, history: firstHistory, now: fixedDate())
        firstLearning.record(wordId: "fruit-apple", correct: false, at: fixedDate())
        firstLearning.record(wordId: "fruit-apple", correct: true, at: fixedDate(timeIntervalSinceNow: 10))

        let relaunchedCoins = CoinAccount(defaults: defaults)
        let relaunchedWishlist = WishlistStore(defaults: defaults)
        let relaunchedHistory = RedemptionHistoryStore(defaults: defaults)
        let relaunchedLearning = LearningRecorder(defaults: defaults)

        XCTAssertEqual(relaunchedCoins.balance, 2)
        XCTAssertEqual(relaunchedCoins.transactions.map(\.reason), [.redemption, .todayReward])
        XCTAssertTrue(relaunchedWishlist.wishes.contains { $0.id == customId && $0.displayName == "贴纸" })
        XCTAssertEqual(relaunchedHistory.records.first?.wishId, customId)
        XCTAssertEqual(relaunchedLearning.stat(for: "fruit-apple")?.attempts, 2)
        XCTAssertEqual(relaunchedLearning.stat(for: "fruit-apple")?.correct, 1)
        XCTAssertEqual(relaunchedLearning.recentWrongIds(limit: 1), ["fruit-apple"])
    }

    @MainActor
    func testCoordinatorRestoresLocalGrowthStateAfterRelaunch() {
        let defaults = isolatedDefaults(name: "coordinator-local-growth-relaunch")
        defer { defaults.removePersistentDomain(forName: "WordMagicGameTests.coordinator-local-growth-relaunch") }
        let firstLaunch = AppCoordinator(configStore: GameConfigStore(defaults: defaults))
        let customId = firstLaunch.wishlistStore.addCustomWish(name: "贴纸", costCoins: 6, iconEmoji: "⭐", now: fixedDate())

        _ = firstLaunch.coinAccount.earn(amount: 8, reason: .todayReward, now: fixedDate())
        _ = firstLaunch.wishlistStore.redeem(
            wishId: customId,
            coins: firstLaunch.coinAccount,
            history: firstLaunch.redemptionHistoryStore,
            now: fixedDate()
        )
        firstLaunch.learningRecorder.record(wordId: "fruit-apple", correct: false, at: fixedDate())

        let relaunched = AppCoordinator(configStore: GameConfigStore(defaults: defaults))

        XCTAssertEqual(relaunched.coinAccount.balance, 2)
        XCTAssertTrue(relaunched.wishlistStore.wishes.contains { $0.id == customId && $0.displayName == "贴纸" })
        XCTAssertEqual(relaunched.redemptionHistoryStore.records.first?.wishId, customId)
        XCTAssertEqual(relaunched.learningRecorder.recentWrongIds(limit: 1), ["fruit-apple"])
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

    func testDailyLearningDayKeyUsesCompactLocalYYYYMMDD() {
        XCTAssertEqual(DailyLearningDayKey.compact(date(year: 2026, month: 5, day: 26, hour: 12), calendar: gregorianUTC()), "20260526")
    }

    func testReviewSnapshotUsesPreDayStatsAndReasonPriority() {
        let start = date(year: 2026, month: 5, day: 26)
        let noon = date(year: 2026, month: 5, day: 26, hour: 12)
        let words = ["due", "recent-wrong", "weak", "same-day-wrong", "fresh"].map(testWord)
        let stats = [
            testStat("due", lastAnswered: addingDays(-5, to: start), memoryState: .familiar, nextReview: addingDays(-1, to: start), correct: 5, wrong: 0, seen: 5, mastery: 0.8, lastOutcome: .correct),
            testStat("recent-wrong", lastAnswered: addingDays(-2, to: start), memoryState: .review, nextReview: addingDays(1, to: start), correct: 1, wrong: 1, seen: 2, mastery: 0.4, lastOutcome: .wrong),
            testStat("weak", lastAnswered: addingDays(-3, to: start), memoryState: .learning, nextReview: addingDays(1, to: start), correct: 2, wrong: 3, seen: 5, mastery: 0.3, lastOutcome: .correct),
            testStat("same-day-wrong", lastAnswered: start.addingTimeInterval(60), memoryState: .review, nextReview: start.addingTimeInterval(120), correct: 0, wrong: 1, seen: 1, mastery: 0, lastOutcome: .wrong),
        ]

        let snapshot = ReviewQueueBuilder().buildSnapshot(
            words: words,
            stats: stats,
            now: noon,
            selectedWordIds: ["due"],
            calendar: gregorianUTC()
        )

        XCTAssertEqual(snapshot.dayKey, "20260526")
        XCTAssertEqual(snapshot.wordIds, ["due", "recent-wrong", "weak"])
        XCTAssertFalse(snapshot.wordIds.contains("same-day-wrong"))
        XCTAssertEqual(snapshot.items.map(\.primaryReason), [.dueReview, .recentWrong, .weakWord])
    }

    func testReviewSnapshotCapsAtFiftyWords() {
        let start = date(year: 2026, month: 5, day: 26)
        let words = (0..<80).map { testWord(String(format: "w-%02d", $0)) }
        let stats = words.map {
            testStat($0.id, lastAnswered: addingDays(-1, to: start), memoryState: .review, nextReview: start.addingTimeInterval(-1), correct: 0, wrong: 1, seen: 1, mastery: 0, lastOutcome: .wrong)
        }

        let snapshot = ReviewQueueBuilder().buildSnapshot(words: words, stats: stats, now: start.addingTimeInterval(3600), selectedWordIds: [], calendar: gregorianUTC())

        XCTAssertEqual(snapshot.wordIds.count, 50)
    }

    func testHomeDailyStatusUsesABMatrix() {
        var state = DailyLearningState(dayKey: "20260526")
        state.reviewSnapshot.wordIds = ["a", "b"]

        var status = HomeDailyStatus.decide(from: state)
        XCTAssertEqual(status.label, "请选择一个场景加战斗")
        XCTAssertEqual(status.remainingReviewCount, 2)
        XCTAssertFalse(status.todayAdventureCompleted)
        XCTAssertFalse(status.dailyCheckInCompleted)

        state.reviewSnapshot.reviewedWordIds = ["a", "b"]
        status = HomeDailyStatus.decide(from: state)
        XCTAssertEqual(status.label, "请选择一个场景加战斗")
        XCTAssertTrue(status.dailyCheckInCompleted)
        XCTAssertFalse(status.todayAdventureCompleted)

        state.packBattleWon = true
        state.reviewSnapshot.reviewedWordIds = ["a"]
        status = HomeDailyStatus.decide(from: state)
        XCTAssertEqual(status.label, "请点击复习加战斗(1)")
        XCTAssertTrue(status.dailyCheckInCompleted)
        XCTAssertFalse(status.todayAdventureCompleted)

        state.reviewSnapshot.reviewedWordIds = ["a", "b"]
        status = HomeDailyStatus.decide(from: state)
        XCTAssertEqual(status.label, "已完成")
        XCTAssertTrue(status.todayAdventureCompleted)
    }

    @MainActor
    func testDailyLearningStateServiceMarksWinsAndReviewedWords() {
        var state = DailyLearningState(dayKey: "20260526")
        state.reviewSnapshot.wordIds = ["a", "b"]
        let service = DailyLearningStateService(defaults: isolatedDefaults(name: "daily-state-service"))

        service.markPackBattleWon(in: &state)
        service.markReviewedWords(["a", "a", "missing"], in: &state)

        XCTAssertTrue(state.packBattleWon)
        XCTAssertEqual(state.reviewSnapshot.reviewedWordIds, ["a"])
        XCTAssertFalse(state.reviewAllDone)

        service.markReviewedWords(["b"], in: &state)
        XCTAssertTrue(state.reviewAllDone)
    }

    func testReviewMonsterCountUsesWordCountHpAndConfiguredCap() {
        XCTAssertEqual(ReviewBattleTuning.reviewMonsterCount(requiredWordCount: 20, monsterHp: 5, configuredTotal: 10, defaultMonsterHp: 5), 3)
        XCTAssertEqual(ReviewBattleTuning.reviewMonsterCount(requiredWordCount: 1, monsterHp: 5, configuredTotal: 10, defaultMonsterHp: 5), 1)
        XCTAssertEqual(ReviewBattleTuning.reviewMonsterCount(requiredWordCount: 50, monsterHp: 1, configuredTotal: 10, defaultMonsterHp: 5), 10)
        XCTAssertEqual(ReviewBattleTuning.reviewMonsterCount(requiredWordCount: 20, monsterHp: 0, configuredTotal: 10, defaultMonsterHp: 5), 3)
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

    private func date(year: Int, month: Int, day: Int, hour: Int = 0) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return components.date!
    }

    private func addingDays(_ days: Int, to date: Date) -> Date {
        Calendar(identifier: .gregorian).date(byAdding: .day, value: days, to: date)!
    }

    private func testWord(_ id: String) -> WordEntry {
        WordEntry(id: id, word: id, meaningZh: id, category: "test", difficulty: 1)
    }

    private func testStat(
        _ id: String,
        lastAnswered: Date,
        memoryState: WordMemoryState,
        nextReview: Date,
        correct: Int,
        wrong: Int,
        seen: Int,
        mastery: Double,
        lastOutcome: WordLearningOutcome
    ) -> WordLearningStat {
        WordLearningStat(
            wordId: id,
            seenCount: seen,
            correctCount: correct,
            wrongCount: wrong,
            lastAnsweredAt: lastAnswered,
            nextReviewAt: nextReview,
            memoryState: memoryState,
            lastOutcome: lastOutcome,
            consecutiveCorrect: lastOutcome == .correct ? 1 : 0,
            consecutiveWrong: lastOutcome == .wrong ? 1 : 0,
            mastery: mastery
        )
    }

    private func gregorianUTC() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func isolatedDefaults(name: String) -> UserDefaults {
        let suiteName = "WordMagicGameTests.\(name)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
