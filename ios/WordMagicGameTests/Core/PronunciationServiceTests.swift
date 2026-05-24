@testable import WordMagicGame
import XCTest

@MainActor
final class PronunciationServiceTests: XCTestCase {
    func testShouldAutoSpeakMatchesHarmonyGate() {
        XCTAssertTrue(shouldAutoSpeak(autoSpeakEnabled: true, ttsAvailable: true, isRevealing: false, questionKind: .choice))
        XCTAssertFalse(shouldAutoSpeak(autoSpeakEnabled: false, ttsAvailable: true, isRevealing: false, questionKind: .choice))
        XCTAssertFalse(shouldAutoSpeak(autoSpeakEnabled: true, ttsAvailable: false, isRevealing: false, questionKind: .choice))
        XCTAssertFalse(shouldAutoSpeak(autoSpeakEnabled: true, ttsAvailable: true, isRevealing: true, questionKind: .choice))
        XCTAssertFalse(shouldAutoSpeak(autoSpeakEnabled: true, ttsAvailable: true, isRevealing: false, questionKind: .sentenceCloze))
    }

    func testShouldAutoSpeakAfterAnswerFeedbackSuppressesFillLetterMediumStepAdvance() {
        XCTAssertFalse(shouldAutoSpeakAfterAnswerFeedback(AnswerOutcome(correct: true, damage: 0, advancedStep: true)))
        XCTAssertTrue(shouldAutoSpeakAfterAnswerFeedback(AnswerOutcome(correct: true, damage: 1, advancedStep: false)))
        XCTAssertTrue(shouldAutoSpeakAfterAnswerFeedback(AnswerOutcome(correct: false, damage: 1, advancedStep: false)))
    }

    func testAutoSpeakCurrentBattleAnswerUsesEnglishAnswerWhenAllowed() {
        let speaker = RecordingPronunciationService()
        let coordinator = makeCoordinator(pronunciationService: speaker)

        coordinator.startBattle()
        coordinator.autoSpeakCurrentBattleAnswer(isRevealing: false)

        XCTAssertEqual(speaker.spokenWords.first, coordinator.battleEngine?.state.currentQuestion?.answer)
    }

    func testAutoSpeakCurrentBattleAnswerRespectsConfigAndRevealState() {
        let speaker = RecordingPronunciationService()
        let coordinator = makeCoordinator(pronunciationService: speaker)
        var config = coordinator.configStore.config
        config.autoSpeak = false
        coordinator.configStore.save(config)

        coordinator.startBattle()
        coordinator.autoSpeakCurrentBattleAnswer(isRevealing: false)
        coordinator.autoSpeakCurrentBattleAnswer(isRevealing: true)

        XCTAssertTrue(speaker.spokenWords.isEmpty)
    }

    func testManualSpeakCurrentBattleAnswerIgnoresAutoSpeakConfig() {
        let speaker = RecordingPronunciationService()
        let coordinator = makeCoordinator(pronunciationService: speaker)
        var config = coordinator.configStore.config
        config.autoSpeak = false
        coordinator.configStore.save(config)

        coordinator.startBattle()
        coordinator.speakCurrentBattleAnswer()

        XCTAssertEqual(speaker.spokenWords.first, coordinator.battleEngine?.state.currentQuestion?.answer)
    }

    func testSentenceClozeDoesNotAutoSpeakButManualSpeakerStillWorks() {
        let speaker = RecordingPronunciationService()
        let coordinator = makeCoordinator(pronunciationService: speaker)
        coordinator.battleEngine = BattleEngine(questionSource: FixedQuestionSource.single(Self.sentenceClozeQuestion), config: coordinator.configStore.config)
        coordinator.battleEngine?.start()

        coordinator.autoSpeakCurrentBattleAnswer(isRevealing: false)
        XCTAssertTrue(speaker.spokenWords.isEmpty)

        coordinator.speakCurrentBattleAnswer()
        XCTAssertEqual(speaker.spokenWords, ["apple"])
    }

    func testAutoSpeakAfterAnswerUsesNextQuestionAnswer() {
        let speaker = RecordingPronunciationService()
        let coordinator = makeCoordinator(pronunciationService: speaker)

        coordinator.startBattle()
        let firstAnswer = coordinator.battleEngine?.state.currentQuestion?.answer
        _ = coordinator.submitBattleOptionForAnimation(firstAnswer ?? "")
        coordinator.autoSpeakCurrentBattleAnswer(isRevealing: false)

        XCTAssertEqual(speaker.spokenWords.first, coordinator.battleEngine?.state.currentQuestion?.answer)
    }

    private func makeCoordinator(pronunciationService: PronunciationSpeaking) -> AppCoordinator {
        let defaults = UserDefaults(suiteName: "PronunciationServiceTests-\(UUID().uuidString)")!
        return AppCoordinator(configStore: GameConfigStore(defaults: defaults), pronunciationService: pronunciationService)
    }

    private final class RecordingPronunciationService: PronunciationSpeaking {
        var isAvailable = true
        private(set) var spokenWords: [String] = []
        private(set) var prepareCount = 0
        private(set) var disposeCount = 0

        func prepare() {
            prepareCount += 1
        }

        func speak(_ word: String) {
            guard isAvailable else { return }
            let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            spokenWords.append(trimmed)
        }

        func dispose() {
            disposeCount += 1
        }
    }

    private static var sentenceClozeQuestion: Question {
        var question = Question(
            promptZh: "苹果",
            answer: "apple",
            options: ["apple", "banana", "orange"],
            wordId: "fruit-apple",
            kind: .sentenceCloze
        )
        question.sentenceTemplate = "I eat an ____."
        question.sentenceZh = "我吃一个苹果。"
        return question
    }
}
