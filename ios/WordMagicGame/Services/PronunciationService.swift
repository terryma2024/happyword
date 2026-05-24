import AVFoundation
import Foundation

@MainActor
protocol PronunciationSpeaking: AnyObject {
    var isAvailable: Bool { get }

    func prepare()
    func speak(_ word: String)
    func dispose()
}

func shouldAutoSpeak(
    autoSpeakEnabled: Bool,
    ttsAvailable: Bool,
    isRevealing: Bool,
    questionKind: QuestionKind? = nil
) -> Bool {
    autoSpeakEnabled && ttsAvailable && !isRevealing && questionKind != .sentenceCloze
}

func shouldAutoSpeakAfterAnswerFeedback(_ outcome: AnswerOutcome) -> Bool {
    !outcome.advancedStep
}

@MainActor
final class SystemPronunciationService: NSObject, PronunciationSpeaking {
    private let synthesizer = AVSpeechSynthesizer()
    private(set) var isAvailable = true

    func prepare() {
        isAvailable = true
    }

    func speak(_ word: String) {
        guard isAvailable else { return }
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US") ?? AVSpeechSynthesisVoice(language: "en-GB")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.volume = 1.0
        synthesizer.speak(utterance)
    }

    func dispose() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }
}
