@testable import WordMagicGame
import XCTest

@MainActor
final class BattleStartTests: XCTestCase {
    func testStartBattleBuildsQuestionsFromSelectedPackAndCanMoveAnswerFromFirstOption() throws {
        let selectedPack = try XCTUnwrap(Pack.builtin.first { $0.id == "fruit-forest" })
        var sawAnswerAwayFromFirstOption = false

        for seed in 1 ... 20 {
            let coordinator = AppCoordinator(
                configStore: GameConfigStore(defaults: UserDefaults(suiteName: "BattleStartTests-\(UUID().uuidString)")!),
                pronunciationService: SilentPronunciationService(),
                battleRandomSeed: UInt64(seed)
            )
            coordinator.selectPack(selectedPack)

            coordinator.startBattle()

            let question = try XCTUnwrap(coordinator.battleEngine?.state.currentQuestion)
            let packWords = Set(selectedPack.words.map(\.word))
            XCTAssertTrue(selectedPack.words.map(\.id).contains(question.wordId))
            XCTAssertEqual(Set(question.options).count, 3)
            XCTAssertTrue(question.options.allSatisfy { packWords.contains($0) })
            XCTAssertTrue(question.options.contains(question.answer))
            sawAnswerAwayFromFirstOption = sawAnswerAwayFromFirstOption || question.options.first != question.answer
        }

        XCTAssertTrue(sawAnswerAwayFromFirstOption)
    }

    func testRepeatedBattleKeepsQuestionPoolScopedToSelectedPack() throws {
        let selectedPack = try XCTUnwrap(Pack.builtin.first { $0.id == "ocean-realm" })
        let selectedWordIds = Set(selectedPack.words.map(\.id))
        let coordinator = AppCoordinator(
            configStore: GameConfigStore(defaults: UserDefaults(suiteName: "BattleRetryScope-\(UUID().uuidString)")!),
            pronunciationService: SilentPronunciationService(),
            battleRandomSeed: 1
        )
        coordinator.selectPack(selectedPack)

        coordinator.startBattle()
        let firstQuestion = try XCTUnwrap(coordinator.battleEngine?.state.currentQuestion)
        coordinator.battleEngine = nil
        coordinator.route = .home
        coordinator.startBattle()
        let retryQuestion = try XCTUnwrap(coordinator.battleEngine?.state.currentQuestion)

        XCTAssertTrue(selectedWordIds.contains(firstQuestion.wordId))
        XCTAssertTrue(selectedWordIds.contains(retryQuestion.wordId))
    }

    func testAnimatedBattleAnswerRecordsLearningStatForCloudSync() throws {
        let coordinator = AppCoordinator(
            configStore: GameConfigStore(defaults: UserDefaults(suiteName: "BattleAnimatedLearning-\(UUID().uuidString)")!),
            pronunciationService: SilentPronunciationService(),
            battleRandomSeed: 1
        )
        coordinator.startBattle()
        let question = try XCTUnwrap(coordinator.battleEngine?.state.currentQuestion)

        _ = coordinator.submitBattleOptionForAnimation(question.answer)

        let stat = try XCTUnwrap(coordinator.learningRecorder.stat(for: question.wordId))
        XCTAssertEqual(stat.attempts, 1)
        XCTAssertEqual(stat.correct, 1)
    }

    func testReviewBattleWithoutWrongWordsShowsToastAndStaysHome() {
        let coordinator = AppCoordinator(
            configStore: GameConfigStore(defaults: UserDefaults(suiteName: "ReviewBattleEmpty-\(UUID().uuidString)")!),
            pronunciationService: SilentPronunciationService(),
            dailyLearningStateService: DailyLearningStateService(defaults: isolatedDefaults(name: "review-empty")),
            battleRandomSeed: 1
        )

        coordinator.startReviewBattle()

        XCTAssertEqual(coordinator.route, .home)
        XCTAssertNil(coordinator.battleEngine)
        XCTAssertEqual(coordinator.toastMessage, "今天没有需要复习的单词")
    }

    func testReviewBattleUsesStablePreDayWrongWordAsFocusedPlan() throws {
        let coordinator = AppCoordinator(
            configStore: GameConfigStore(defaults: UserDefaults(suiteName: "ReviewBattleFocused-\(UUID().uuidString)")!),
            pronunciationService: SilentPronunciationService(),
            dailyLearningStateService: DailyLearningStateService(defaults: isolatedDefaults(name: "review-focused")),
            battleRandomSeed: 1
        )
        coordinator.learningRecorder.record(wordId: "fruit-apple", correct: false, at: Date(timeIntervalSinceNow: -86_400 * 2))

        coordinator.startReviewBattle()

        XCTAssertEqual(coordinator.route, .battle)
        let question = try XCTUnwrap(coordinator.battleEngine?.state.currentQuestion)
        XCTAssertEqual(question.wordId, "fruit-apple")
        XCTAssertTrue(question.options.contains(question.answer))
        XCTAssertEqual(coordinator.battleEngine?.state.remainingSeconds, ReviewBattleTuning.reviewBattleSeconds)
    }

    private final class SilentPronunciationService: PronunciationSpeaking {
        var isAvailable = true

        func prepare() {}
        func speak(_ word: String) {}
        func dispose() {}
    }

    private func isolatedDefaults(name: String) -> UserDefaults {
        let suiteName = "BattleStartTests.\(name).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
