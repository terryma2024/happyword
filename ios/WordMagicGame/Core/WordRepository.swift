import Foundation

struct WordRepository {
    private let words: [WordEntry]

    init(words: [WordEntry]) {
        self.words = words.filter(\.isValid)
    }

    func all() -> [WordEntry] {
        words
    }

    func byCategory(_ category: String) -> [WordEntry] {
        words.filter { $0.category == category }
    }

    func word(id: String) -> WordEntry? {
        words.first { $0.id == id }
    }
}

struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x1234_5678 : seed
    }

    mutating func nextDouble() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z = z ^ (z >> 31)
        return Double(z) / Double(UInt64.max)
    }
}

private func shuffled<T>(_ input: [T], random: () -> Double) -> [T] {
    guard input.count > 1 else { return input }
    var result = input
    for index in stride(from: result.count - 1, through: 1, by: -1) {
        let candidate = Int((random() * Double(index + 1)).rounded(.down))
        let swapIndex = min(max(candidate, 0), index)
        result.swapAt(index, swapIndex)
    }
    return result
}

protocol QuestionSource {
    func nextQuestion(lastWordId: String?) throws -> Question
}

extension QuestionSource {
    func nextQuestion() throws -> Question {
        try nextQuestion(lastWordId: nil)
    }
}

final class QuestionGenerator: QuestionSource {
    static let optionsPerQuestion = 3

    private let repository: WordRepository
    private var random: SeededRandom

    init(repository: WordRepository, random: SeededRandom = SeededRandom(seed: 42)) {
        self.repository = repository
        self.random = random
    }

    func nextQuestion(lastWordId: String? = nil) throws -> Question {
        let all = repository.all()
        guard all.count >= Self.optionsPerQuestion else {
            throw BattleError.tooSmallWordPool
        }
        let candidates = all.filter { $0.id != lastWordId }
        let pool = candidates.isEmpty ? all : candidates
        let answer = pool[randomIndex(pool.count)]
        return try question(for: answer)
    }

    func question(for answer: WordEntry) throws -> Question {
        let all = repository.all()
        guard all.count >= Self.optionsPerQuestion else {
            throw BattleError.tooSmallWordPool
        }
        let distractors = pickDistractors(all: all, answer: answer)
        var options = [answer.word] + distractors.map(\.word)
        options = shuffled(options) { self.random.nextDouble() }
        return Question.choice(wordId: answer.id, promptZh: answer.meaningZh, answer: answer.word, options: options)
    }

    private func pickDistractors(all: [WordEntry], answer: WordEntry) -> [WordEntry] {
        let needed = Self.optionsPerQuestion - 1
        var picked: [WordEntry] = []
        var usedWords: Set<String> = [answer.word]

        if let raw = answer.distractors {
            for (index, word) in raw.enumerated() where picked.count < needed && !word.isEmpty && !usedWords.contains(word) {
                usedWords.insert(word)
                picked.append(WordEntry(id: "__distractor-\(answer.id)-\(index)", word: word, meaningZh: "_", category: answer.category, difficulty: answer.difficulty))
            }
        }

        let sameCategory = repository.byCategory(answer.category)
            .filter { $0.id != answer.id && !usedWords.contains($0.word) }
        for entry in shuffled(sameCategory, random: { self.random.nextDouble() }) where picked.count < needed {
            picked.append(entry)
            usedWords.insert(entry.word)
        }

        let global = all.filter { $0.id != answer.id && !usedWords.contains($0.word) }
        for entry in shuffled(global, random: { self.random.nextDouble() }) where picked.count < needed {
            picked.append(entry)
            usedWords.insert(entry.word)
        }
        return picked
    }

    private func randomIndex(_ upperBound: Int) -> Int {
        guard upperBound > 0 else { return 0 }
        return min(Int((random.nextDouble() * Double(upperBound)).rounded(.down)), upperBound - 1)
    }
}

final class FixedQuestionSource: QuestionSource {
    private let questions: [Question]
    private var index = 0

    init(repeating questions: [Question]) {
        self.questions = questions
    }

    static func single(_ question: Question) -> FixedQuestionSource {
        FixedQuestionSource(repeating: [question])
    }

    func nextQuestion(lastWordId: String? = nil) throws -> Question {
        guard !questions.isEmpty else { throw BattleError.tooSmallWordPool }
        let question = questions[index % questions.count]
        index += 1
        return question
    }
}
