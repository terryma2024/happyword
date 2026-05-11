import Foundation

enum QuestionKind: String, Codable, Equatable {
    case choice
    case fillLetter = "fill-letter"
    case fillLetterMedium = "fill-letter-medium"
    case spell
}

struct Question: Codable, Equatable, Identifiable {
    var id: String { wordId }
    var promptZh: String
    var answer: String
    var options: [String]
    var wordId: String
    var kind: QuestionKind

    var letterTemplate: String = ""
    var missingIndex: Int = -1
    var letterOptions: [String] = []
    var letterAnswer: String = ""

    var letterTemplateBase: String = ""
    var missingIndices: [Int] = []
    var letterOptionsSteps: [[String]] = []
    var letterAnswers: [String] = []
    var currentStep: Int = 0

    var spellLetters: [String] = []
    var spellRevealedMask: [Bool] = []
    var spellPool: [String] = []

    static func choice(wordId: String, promptZh: String, answer: String, options: [String]) -> Question {
        Question(promptZh: promptZh, answer: answer, options: options, wordId: wordId, kind: .choice)
    }

    var isValid: Bool {
        guard !wordId.isEmpty, !answer.isEmpty else { return false }
        switch kind {
        case .choice:
            return !promptZh.isEmpty && options.count == 3 && Set(options).count == 3 && options.contains(answer)
        case .fillLetter:
            return !letterTemplate.isEmpty &&
                letterOptions.count == 3 &&
                Set(letterOptions).count == 3 &&
                letterOptions.contains(letterAnswer)
        case .fillLetterMedium:
            return missingIndices.count == 2 &&
                letterOptionsSteps.count == 2 &&
                letterAnswers.count == 2 &&
                (0...1).contains(currentStep)
        case .spell:
            return (4...9).contains(spellLetters.count) &&
                spellRevealedMask.count == spellLetters.count &&
                spellRevealedMask.first == true
        }
    }
}
