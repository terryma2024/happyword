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

    func nextQuestionForWord(_ answer: WordEntry, lastWordId _: String? = nil) throws -> Question {
        try question(for: answer)
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

final class FillLetterGenerator {
    private static let alphabet = Array("abcdefghijklmnopqrstuvwxyz").map(String.init)
    private static let optionsPerQuestion = 3

    private var random: SeededRandom

    init(random: SeededRandom = SeededRandom(seed: 42)) {
        self.random = random
    }

    func generate(_ word: WordEntry, lastWordId _: String? = nil) -> Question? {
        let letters = alphabeticLetters(word.word)
        guard letters.count >= 3 else { return nil }

        let missingIndex = randomIndex(in: 1 ... (letters.count - 1))
        let answer = letters[missingIndex]
        let options = letterOptions(answer: answer, wordLetters: Set(letters), excludedAnswers: [answer])
        let template = letters.enumerated().map { index, letter in index == missingIndex ? "_" : letter }.joined(separator: " ")

        var question = Question(promptZh: word.meaningZh, answer: word.word, options: [], wordId: word.id, kind: .fillLetter)
        question.letterTemplate = template
        question.missingIndex = missingIndex
        question.letterOptions = options
        question.letterAnswer = answer
        return question
    }

    func generateMedium(_ word: WordEntry, lastWordId _: String? = nil) -> Question? {
        let letters = alphabeticLetters(word.word)
        guard letters.count >= 4 else { return nil }

        var first = randomIndex(in: 1 ... (letters.count - 1))
        var second = randomIndex(in: 1 ... (letters.count - 1))
        if first == second {
            second += 1
            if second > letters.count - 1 {
                second = 1
            }
        }
        if first > second {
            swap(&first, &second)
        }

        let missingIndices = [first, second]
        let answers = [letters[first], letters[second]]
        let wordLetters = Set(letters)
        let template = letters.enumerated()
            .map { index, letter in missingIndices.contains(index) ? "_" : letter }
            .joined(separator: " ")
        let steps = [
            letterOptions(answer: answers[0], wordLetters: wordLetters, excludedAnswers: answers),
            letterOptions(answer: answers[1], wordLetters: wordLetters, excludedAnswers: answers),
        ]

        var question = Question(promptZh: word.meaningZh, answer: word.word, options: [], wordId: word.id, kind: .fillLetterMedium)
        question.letterTemplateBase = template
        question.missingIndices = missingIndices
        question.letterOptionsSteps = steps
        question.letterAnswers = answers
        question.currentStep = 0
        return question
    }

    private func alphabeticLetters(_ word: String) -> [String] {
        word.lowercased().compactMap { character in
            guard character >= "a", character <= "z" else { return nil }
            return String(character)
        }
    }

    private func letterOptions(answer: String, wordLetters: Set<String>, excludedAnswers: [String]) -> [String] {
        var pool = Self.alphabet.filter { !wordLetters.contains($0) && !excludedAnswers.contains($0) }
        if pool.count < Self.optionsPerQuestion - 1 {
            pool = Self.alphabet.filter { !excludedAnswers.contains($0) }
        }
        let distractors = Array(shuffled(pool, random: { self.random.nextDouble() }).prefix(Self.optionsPerQuestion - 1))
        return shuffled([answer] + distractors, random: { self.random.nextDouble() })
    }

    private func randomIndex(in range: ClosedRange<Int>) -> Int {
        guard range.lowerBound < range.upperBound else { return range.lowerBound }
        let span = range.upperBound - range.lowerBound + 1
        let candidate = Int((random.nextDouble() * Double(span)).rounded(.down))
        return range.lowerBound + min(max(candidate, 0), span - 1)
    }
}

final class SpellGenerator {
    private var random: SeededRandom

    init(random: SeededRandom = SeededRandom(seed: 42)) {
        self.random = random
    }

    func generate(_ word: WordEntry) -> Question? {
        let letters = alphabeticLetters(word.word)
        guard (4 ... 9).contains(letters.count) else { return nil }

        var question = Question(promptZh: word.meaningZh, answer: word.word, options: [], wordId: word.id, kind: .spell)
        question.spellLetters = letters
        question.spellRevealedMask = letters.indices.map { $0 == 0 }
        question.spellPool = shuffled(Array(letters.dropFirst()), random: { self.random.nextDouble() })
        return question
    }

    private func alphabeticLetters(_ word: String) -> [String] {
        word.lowercased().compactMap { character in
            guard character >= "a", character <= "z" else { return nil }
            return String(character)
        }
    }
}

struct BattleQuestionPlan: Equatable {
    var wordIds: [String]
    var monsterSlots: [MonsterPlanSlot]

    static func from(pack: Pack, enabledQuestionTypes: [String]) -> BattleQuestionPlan {
        let slots: [MonsterPlanSlot]
        if !pack.scene.monsterPlan.isEmpty {
            slots = pack.scene.monsterPlan
        } else {
            slots = BattleQuestionTypePolicy.buildMonsterSlots(enabledTypeIds: enabledQuestionTypes)
        }
        return BattleQuestionPlan(wordIds: pack.words.map(\.id), monsterSlots: slots)
    }
}

final class PlanQuestionSource: QuestionSource {
    private let plan: BattleQuestionPlan
    private let repository: WordRepository
    private let choiceGenerator: QuestionGenerator
    private let fillGenerator: FillLetterGenerator
    private let spellGenerator: SpellGenerator
    private let scheduler: BattleQuestionScheduler?
    private var monsterIndexProvider: () -> Int = { 1 }
    private var cursor = 0

    init(
        plan: BattleQuestionPlan,
        repository: WordRepository,
        randomSeed: UInt64 = 42,
        enabledQuestionTypes: [String]? = nil,
        scheduler: BattleQuestionScheduler? = nil,
    ) {
        self.plan = plan
        self.repository = repository
        choiceGenerator = QuestionGenerator(repository: repository, random: SeededRandom(seed: randomSeed))
        fillGenerator = FillLetterGenerator(random: SeededRandom(seed: randomSeed &+ 1))
        spellGenerator = SpellGenerator(random: SeededRandom(seed: randomSeed &+ 2))
        if let scheduler {
            self.scheduler = scheduler
        } else if let enabledQuestionTypes {
            var rng = SeededRandom(seed: randomSeed &+ 3)
            self.scheduler = BattleQuestionScheduler(
                planWordIds: plan.wordIds,
                enabledTypes: enabledQuestionTypes,
                rng: { rng.nextDouble() },
            )
        } else {
            self.scheduler = nil
        }
    }

    func setMonsterIndexProvider(_ provider: @escaping () -> Int) {
        monsterIndexProvider = provider
    }

    func nextQuestion(lastWordId: String? = nil) throws -> Question {
        if let scheduler {
            return try nextScheduledQuestion(lastWordId: lastWordId, scheduler: scheduler)
        }
        let word = pickWord(lastWordId: lastWordId)
        switch currentMonsterKind() {
        case .boss:
            return try spellGenerator.generate(word)
                ?? fillGenerator.generateMedium(word)
                ?? fillGenerator.generate(word)
                ?? choiceGenerator.nextQuestionForWord(word, lastWordId: lastWordId)
        case .elite:
            return try fillGenerator.generateMedium(word)
                ?? fillGenerator.generate(word)
                ?? choiceGenerator.nextQuestionForWord(word, lastWordId: lastWordId)
        case .spelling:
            return try fillGenerator.generate(word)
                ?? choiceGenerator.nextQuestionForWord(word, lastWordId: lastWordId)
        case .normal, .review:
            return try choiceGenerator.nextQuestionForWord(word, lastWordId: lastWordId)
        }
    }

    private func nextScheduledQuestion(
        lastWordId: String?,
        scheduler: BattleQuestionScheduler,
    ) throws -> Question {
        let canServe: WordKindSupportFn = { [repository] wordId, kind in
            guard let word = repository.word(id: wordId) else { return false }
            return BattleQuestionTypePolicy.wordSupportsQuestionType(word, typeId: kind)
        }
        let pick = scheduler.pickNext(lastWordId: lastWordId, canServe: canServe)
        let word: WordEntry
        if !pick.preferredWordId.isEmpty, let preferred = repository.word(id: pick.preferredWordId) {
            word = preferred
        } else {
            word = pickWordForQuestionType(pick.kind, lastWordId: lastWordId)
        }
        let phasePool = scheduler.activePhasePool()
        let resolvedType = BattleQuestionTypePolicy.resolveQuestionTypeWithinPool(
            word,
            primaryType: pick.kind,
            pool: phasePool,
        )
        if let exact = try generateExactQuestion(resolvedType, word: word, lastWordId: lastWordId) {
            scheduler.markServed(wordId: word.id, kind: exact.kind.rawValue, canServe: canServe)
            return exact
        }
        let fallback = try choiceGenerator.nextQuestionForWord(word, lastWordId: lastWordId)
        scheduler.markServed(wordId: word.id, kind: fallback.kind.rawValue, canServe: canServe)
        return fallback
    }

    private func pickWordForQuestionType(_ typeId: String, lastWordId: String?) -> WordEntry {
        let all = repository.all()
        guard !all.isEmpty else {
            return WordEntry(id: "", word: "", meaningZh: "", category: "", difficulty: 1)
        }
        for wordId in plan.wordIds {
            if let word = repository.word(id: wordId),
               BattleQuestionTypePolicy.wordSupportsQuestionType(word, typeId: typeId) {
                if plan.wordIds.count > 1, wordId == lastWordId { continue }
                return word
            }
        }
        return pickWord(lastWordId: lastWordId)
    }

    private func generateExactQuestion(
        _ targetType: String,
        word: WordEntry,
        lastWordId: String?,
    ) throws -> Question? {
        switch targetType {
        case QuestionKind.choice.rawValue:
            return try choiceGenerator.nextQuestionForWord(word, lastWordId: lastWordId)
        case QuestionKind.fillLetter.rawValue:
            return try fillGenerator.generate(word)
        case QuestionKind.fillLetterMedium.rawValue:
            return try fillGenerator.generateMedium(word)
        case QuestionKind.spell.rawValue:
            return try spellGenerator.generate(word)
        default:
            return nil
        }
    }

    private func pickWord(lastWordId: String?) -> WordEntry {
        let all = repository.all()
        guard !all.isEmpty else {
            return WordEntry(id: "", word: "", meaningZh: "", category: "", difficulty: 1)
        }
        guard !plan.wordIds.isEmpty else { return all[0] }

        var attempts = 0
        while attempts < plan.wordIds.count {
            let wordId = plan.wordIds[cursor % plan.wordIds.count]
            cursor = (cursor + 1) % plan.wordIds.count
            attempts += 1
            if plan.wordIds.count > 1, wordId == lastWordId {
                continue
            }
            if let word = repository.word(id: wordId) {
                return word
            }
        }

        for wordId in plan.wordIds {
            if let word = repository.word(id: wordId) {
                return word
            }
        }
        return all[0]
    }

    private func currentMonsterKind() -> MonsterPlanSlotKind {
        guard !plan.monsterSlots.isEmpty else { return .normal }
        let index = max(monsterIndexProvider(), 1) - 1
        return plan.monsterSlots[index % plan.monsterSlots.count].kind
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
