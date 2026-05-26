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
        let tokens = phraseTokens(word.word)
        let letters = allLetters(tokens)
        let fillable = fillableTokens(tokens)
        guard fillable.count >= 3 else { return nil }

        let missingToken = fillable[randomIndex(in: 1 ... (fillable.count - 1))]
        let missingIndex = missingToken.originalIndex
        let answer = missingToken.glyph
        let options = letterOptions(answer: answer, wordLetters: Set(letters), excludedAnswers: [answer])
        let template = template(from: tokens, missingPositions: [missingIndex])

        var question = Question(promptZh: word.meaningZh, answer: word.word, options: [], wordId: word.id, kind: .fillLetter)
        question.letterTemplate = template
        question.missingIndex = missingIndex
        question.letterOptions = options
        question.letterAnswer = answer
        return question
    }

    func generateMedium(_ word: WordEntry, lastWordId _: String? = nil) -> Question? {
        let tokens = phraseTokens(word.word)
        let letters = allLetters(tokens)
        let fillable = fillableTokens(tokens)
        guard fillable.count >= 4 else { return nil }

        let first = randomIndex(in: 1 ... (fillable.count - 1))
        var second = randomIndex(in: 1 ... (fillable.count - 1))
        if first == second {
            second += 1
            if second > fillable.count - 1 {
                second = 1
            }
        }
        var firstToken = fillable[first]
        var secondToken = fillable[second]
        if firstToken.originalIndex > secondToken.originalIndex {
            swap(&firstToken, &secondToken)
        }

        let missingIndices = [firstToken.originalIndex, secondToken.originalIndex]
        let answers = [firstToken.glyph, secondToken.glyph]
        let wordLetters = Set(letters)
        let template = template(from: tokens, missingPositions: Set(missingIndices))
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
        let tokens = phraseTokens(word.word)
        let fillableIndices = tokens.indices.filter { tokens[$0].isLetter && !tokens[$0].isArticle }
        guard (4 ... 9).contains(fillableIndices.count) else { return nil }
        let letters = tokens.map(\.glyph)

        var question = Question(promptZh: word.meaningZh, answer: word.word, options: [], wordId: word.id, kind: .spell)
        question.spellLetters = letters
        question.spellRevealedMask = tokens.indices.map { index in
            !tokens[index].isLetter || tokens[index].isArticle || index == fillableIndices[0]
        }
        question.spellPool = shuffled(fillableIndices.dropFirst().map { letters[$0] }, random: { self.random.nextDouble() })
        return question
    }
}

struct SentenceClozeTargetSpan: Equatable {
    var start: String.Index
    var end: String.Index
}

func findSentenceClozeTargetSpan(exampleEn: String, targetWord: String) -> SentenceClozeTargetSpan? {
    let target = targetWord.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !exampleEn.isEmpty, !target.isEmpty else { return nil }
    var start = exampleEn.startIndex
    while start < exampleEn.endIndex {
        if let end = matchTargetAt(raw: exampleEn, target: target, start: start),
           hasLetterBoundary(raw: exampleEn, start: start, end: end) {
            return SentenceClozeTargetSpan(start: start, end: end)
        }
        start = exampleEn.index(after: start)
    }
    return nil
}

func wordSupportsSentenceCloze(_ word: WordEntry) -> Bool {
    guard let example = word.example,
          !example.en.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          !example.zh.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { return false }
    return findSentenceClozeTargetSpan(exampleEn: example.en, targetWord: word.word) != nil
}

final class SentenceClozeGenerator {
    private var random: SeededRandom

    init(random: SeededRandom = SeededRandom(seed: 42)) {
        self.random = random
    }

    func generate(_ word: WordEntry, repo: WordRepository, lastWordId: String? = nil) -> Question? {
        guard let example = word.example,
              let span = findSentenceClozeTargetSpan(exampleEn: example.en, targetWord: word.word),
              !example.zh.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        let options = buildOptions(word: word, repo: repo, lastWordId: lastWordId)
        guard options.count >= 3 else { return nil }

        var question = Question(promptZh: word.meaningZh, answer: word.word, options: shuffled(Array(options.prefix(3))) { self.random.nextDouble() }, wordId: word.id, kind: .sentenceCloze)
        question.sentenceTemplate = String(example.en[..<span.start]) + "____" + String(example.en[span.end...])
        question.sentenceZh = example.zh
        return question.isValid ? question : nil
    }

    private func buildOptions(word: WordEntry, repo: WordRepository, lastWordId: String?) -> [String] {
        var out: [String] = []
        pushUnique(&out, word.word)
        for distractor in word.distractors ?? [] {
            pushUnique(&out, distractor)
        }
        for entry in repo.all() {
            if entry.id == word.id || entry.id == lastWordId { continue }
            pushUnique(&out, entry.word)
            if out.count >= 3 { break }
        }
        return out
    }

    private func pushUnique(_ out: inout [String], _ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let normalized = trimmed.lowercased()
        guard !out.contains(where: { $0.lowercased() == normalized }) else { return }
        out.append(trimmed)
    }
}

private struct PhraseToken {
    var glyph: String
    var originalIndex: Int
    var isLetter: Bool
    var isArticle: Bool
}

private func phraseTokens(_ raw: String) -> [PhraseToken] {
    let chars = Array(raw.lowercased())
    var articlePositions = Set<Int>()
    var index = 0
    while index < chars.count {
        guard isAsciiLetter(chars[index]) else {
            index += 1
            continue
        }
        let start = index
        var word = ""
        while index < chars.count, isAsciiLetter(chars[index]) {
            word.append(chars[index])
            index += 1
        }
        if ["a", "an", "the"].contains(word) {
            for position in start ..< index {
                articlePositions.insert(position)
            }
        }
    }

    return chars.enumerated().compactMap { index, character in
        if isAsciiLetter(character) {
            return PhraseToken(glyph: String(character), originalIndex: index, isLetter: true, isArticle: articlePositions.contains(index))
        }
        if character == " " {
            return PhraseToken(glyph: " ", originalIndex: index, isLetter: false, isArticle: false)
        }
        return nil
    }
}

private func isAsciiLetter(_ character: Character) -> Bool {
    character >= "a" && character <= "z"
}

private func isWhitespace(_ character: Character) -> Bool {
    character == " " || character == "\t" || character == "\n" || character == "\r"
}

private func matchTargetAt(raw: String, target: String, start: String.Index) -> String.Index? {
    let lowerRaw = raw.lowercased()
    let lowerTarget = target.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    guard let rawStart = lowerRaw.index(lowerRaw.startIndex, offsetBy: raw.distance(from: raw.startIndex, to: start), limitedBy: lowerRaw.endIndex) else {
        return nil
    }
    var rawIndex = rawStart
    var targetIndex = lowerTarget.startIndex
    while targetIndex < lowerTarget.endIndex {
        let targetChar = lowerTarget[targetIndex]
        if isWhitespace(targetChar) {
            var targetSpaceEnd = targetIndex
            while targetSpaceEnd < lowerTarget.endIndex, isWhitespace(lowerTarget[targetSpaceEnd]) {
                targetSpaceEnd = lowerTarget.index(after: targetSpaceEnd)
            }
            guard rawIndex < lowerRaw.endIndex, isWhitespace(lowerRaw[rawIndex]) else { return nil }
            while rawIndex < lowerRaw.endIndex, isWhitespace(lowerRaw[rawIndex]) {
                rawIndex = lowerRaw.index(after: rawIndex)
            }
            targetIndex = targetSpaceEnd
            continue
        }
        guard rawIndex < lowerRaw.endIndex, lowerRaw[rawIndex] == targetChar else { return nil }
        rawIndex = lowerRaw.index(after: rawIndex)
        targetIndex = lowerTarget.index(after: targetIndex)
    }
    let offset = lowerRaw.distance(from: lowerRaw.startIndex, to: rawIndex)
    return raw.index(raw.startIndex, offsetBy: offset)
}

private func hasLetterBoundary(raw: String, start: String.Index, end: String.Index) -> Bool {
    let before: Character? = start > raw.startIndex ? raw[raw.index(before: start)] : nil
    let after: Character? = end < raw.endIndex ? raw[end] : nil
    return !(before.map(isAsciiLetter) ?? false) && !(after.map(isAsciiLetter) ?? false)
}

private func fillableTokens(_ tokens: [PhraseToken]) -> [PhraseToken] {
    tokens.filter { $0.isLetter && !$0.isArticle }
}

private func allLetters(_ tokens: [PhraseToken]) -> [String] {
    tokens.filter(\.isLetter).map(\.glyph)
}

private func template(from tokens: [PhraseToken], missingPositions: Set<Int>) -> String {
    tokens.map { token in
        token.isLetter && missingPositions.contains(token.originalIndex) ? "_" : token.glyph
    }
    .joined()
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
    private let sentenceClozeGenerator: SentenceClozeGenerator
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
        sentenceClozeGenerator = SentenceClozeGenerator(random: SeededRandom(seed: randomSeed &+ 4))
        if let scheduler {
            self.scheduler = scheduler
        } else if let enabledQuestionTypes {
            var rng = SeededRandom(seed: randomSeed &+ 3)
            let canServe: WordKindSupportFn = { [repository] wordId, kind in
                guard let word = repository.word(id: wordId) else { return false }
                return BattleQuestionTypePolicy.wordSupportsQuestionType(word, typeId: kind)
            }
            self.scheduler = BattleQuestionScheduler(
                planWordIds: plan.wordIds,
                enabledTypes: enabledQuestionTypes,
                canServe: canServe,
                rng: { rng.nextDouble() },
            )
        } else {
            self.scheduler = nil
        }
    }

    func setMonsterIndexProvider(_ provider: @escaping () -> Int) {
        monsterIndexProvider = provider
    }

    func catalogIndexForMonster(_ monsterIndex: Int) -> Int {
        if let scheduler {
            return scheduler.catalogIndexForMonster(monsterIndex: monsterIndex)
        }
        guard !plan.monsterSlots.isEmpty else { return monsterIndex }
        let slot = plan.monsterSlots[(max(monsterIndex, 1) - 1) % plan.monsterSlots.count]
        return slot.catalogIndex > 0 ? slot.catalogIndex : monsterIndex
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
        let pick = scheduler.pickNext(monsterIndex: monsterIndexProvider(), lastWordId: lastWordId, canServe: canServe)
        let word: WordEntry
        if !pick.preferredWordId.isEmpty, let preferred = repository.word(id: pick.preferredWordId) {
            word = preferred
        } else {
            word = pickWordForQuestionType(pick.kind, lastWordId: lastWordId)
        }
        if let exact = try generateExactQuestion(pick.kind, word: word, lastWordId: lastWordId) {
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
        if !plan.wordIds.isEmpty {
            var skippedLast: WordEntry?
            var attempts = 0
            while attempts < plan.wordIds.count {
                let wordId = plan.wordIds[cursor % plan.wordIds.count]
                cursor = (cursor + 1) % plan.wordIds.count
                attempts += 1
                guard let word = repository.word(id: wordId),
                      BattleQuestionTypePolicy.wordSupportsQuestionType(word, typeId: typeId)
                else { continue }
                if plan.wordIds.count > 1, wordId == lastWordId {
                    skippedLast = skippedLast ?? word
                    continue
                }
                return word
            }
            if let skippedLast {
                return skippedLast
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
            return fillGenerator.generate(word)
        case QuestionKind.fillLetterMedium.rawValue:
            return fillGenerator.generateMedium(word)
        case QuestionKind.spell.rawValue:
            return spellGenerator.generate(word)
        case QuestionKind.sentenceCloze.rawValue:
            return sentenceClozeGenerator.generate(word, repo: repository, lastWordId: lastWordId)
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
