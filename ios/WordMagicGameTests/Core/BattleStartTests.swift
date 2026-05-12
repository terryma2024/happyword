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

    private final class SilentPronunciationService: PronunciationSpeaking {
        var isAvailable = true

        func prepare() {}
        func speak(_ word: String) {}
        func dispose() {}
    }
}
