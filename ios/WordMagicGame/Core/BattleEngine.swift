import Combine
import Foundation

enum BattleStatus: String, Codable, Equatable {
    case ready
    case playing
    case won
    case lost
}

enum BattleError: Error, Equatable {
    case notPlaying
    case alreadyEnded
    case missingQuestion
    case invalidOption(String)
    case tooSmallWordPool
}

struct BattleState: Equatable {
    var playerMaxHp: Int
    var playerHp: Int
    var monsterMaxHp: Int
    var monsterHp: Int
    var monsterIndex: Int
    var monstersTotal: Int
    var remainingSeconds: Int
    var status: BattleStatus = .ready
    var currentQuestion: Question?
    var comboCount: Int = 0
    var defeatedMonsters: Int = 0
    var totalAnswers: Int = 0
    var correctAnswers: Int = 0
    var learnedWordIds: [String] = []
    var currentMonsterBonus: Bool = false
    var bonusKillCount: Int = 0
    var defeatedMonsterLevelScore: Int = 0

    init(config: GameConfig) {
        playerMaxHp = config.playerMaxHp
        playerHp = config.playerMaxHp
        monsterMaxHp = config.monsterMaxHp
        monsterHp = config.monsterMaxHp
        monsterIndex = 1
        monstersTotal = config.monstersTotal
        remainingSeconds = config.startingSeconds
    }
}

struct AnswerOutcome: Equatable {
    var correct = false
    var damage = 0
    var advancedStep = false
    var comboTriggered = false
    var monsterDefeated = false
    var newMonsterSpawned = false
    var battleEnded = false
    var endStatus: BattleStatus?
}

struct TickOutcome: Equatable {
    var battleEnded = false
    var endStatus: BattleStatus?
}

struct SessionResult: Equatable {
    var status: BattleStatus
    var defeatedMonsters: Int
    var monstersTotal: Int
    var totalAnswers: Int
    var correctAnswers: Int
    var correctRate: Double
    var learnedWordCount: Int
    var stars: Int
    var coinsEarned: Int = 0
    var coinsTotal: Int = 0
    var bonusKillCount: Int = 0
    var monsterLevelScore: Int = 0
}

enum BattleRewardCalc {
    static func coinValue(for level: MonsterLevel) -> Int {
        switch level {
        case .beginner:
            return 1
        case .intermediate:
            return 2
        case .advanced:
            return 3
        case .super:
            return 4
        }
    }

    static func coinAward(monsterLevelScore: Int) -> Int {
        max(0, monsterLevelScore)
    }

    static func retiredBonusCoinDelta(stars _: Int, bonusKillCount _: Int, won _: Bool) -> Int {
        0
    }
}

final class BattleEngine: ObservableObject {
    static let comboBurstThreshold = 3
    static let comboBurstDamage = 2

    private let questionSource: QuestionSource
    private let randomDouble: () -> Double
    private let monsterCatalogIndex: (Int) -> Int
    @Published private(set) var state: BattleState

    init(
        questionSource: QuestionSource,
        config: GameConfig = .default,
        randomDouble: @escaping () -> Double = { Double.random(in: 0..<1) },
        monsterCatalogIndex: @escaping (Int) -> Int = { $0 }
    ) {
        self.questionSource = questionSource
        self.randomDouble = randomDouble
        self.monsterCatalogIndex = monsterCatalogIndex
        state = BattleState(config: config)
    }

    func start() {
        guard state.status == .ready else { return }
        state.status = .playing
        state.currentMonsterBonus = rollsBonusMonster(for: catalogIndex(for: state.monsterIndex))
        if let question = try? questionSource.nextQuestion() {
            state.currentQuestion = question
            rememberWord(question.wordId)
        }
    }

    /// V0.8.4 — Spell wrong letter tap: −1 HP without advancing the question.
    func applySpellLetterPenalty() -> Int {
        guard state.status == .playing else { return 0 }
        let damage = 1
        var next = state
        next.playerHp -= damage
        if next.playerHp <= 0 {
            next.playerHp = 0
            next.status = .lost
            next.currentQuestion = nil
        }
        state = next
        return damage
    }

    func submitAnswer(_ option: String) throws -> AnswerOutcome {
        guard state.status == .playing else { throw BattleError.notPlaying }
        guard var question = state.currentQuestion else { throw BattleError.missingQuestion }

        let validOptions = options(for: question)
        guard validOptions.contains(option) else {
            throw BattleError.invalidOption(option)
        }

        let correct = isCorrect(option: option, question: question)
        var outcome = AnswerOutcome(correct: correct, damage: correct ? 1 : monsterAttackDamage(for: catalogIndex(for: state.monsterIndex)))

        if question.kind == .fillLetterMedium && correct && question.currentStep < 1 {
            revealMediumStepLetter(&question, chosen: option)
            question.currentStep += 1
            state.currentQuestion = question
            outcome.damage = 0
            outcome.advancedStep = true
            return outcome
        }

        state.totalAnswers += 1
        if correct {
            state.correctAnswers += 1
            state.comboCount += 1
            if state.comboCount >= Self.comboBurstThreshold {
                outcome.damage = Self.comboBurstDamage
                outcome.comboTriggered = true
                state.comboCount = 0
            }
            state.monsterHp -= outcome.damage
            if state.monsterHp <= 0 {
                state.monsterHp = 0
                state.defeatedMonsterLevelScore += BattleRewardCalc.coinValue(
                    for: MonsterCodex.level(forCatalogIndex1Based: catalogIndex(for: state.monsterIndex))
                )
                state.defeatedMonsters += 1
                if state.currentMonsterBonus {
                    state.bonusKillCount += 1
                }
                outcome.monsterDefeated = true
                if state.defeatedMonsters >= state.monstersTotal {
                    finish(status: .won)
                    outcome.battleEnded = true
                    outcome.endStatus = .won
                    return outcome
                }
                state.monsterIndex += 1
                state.monsterHp = state.monsterMaxHp
                state.currentMonsterBonus = rollsBonusMonster(for: catalogIndex(for: state.monsterIndex))
                outcome.newMonsterSpawned = true
            }
        } else {
            state.comboCount = 0
            state.playerHp -= outcome.damage
            if state.playerHp <= 0 {
                state.playerHp = 0
                finish(status: .lost)
                outcome.battleEnded = true
                outcome.endStatus = .lost
                return outcome
            }
        }

        let next = try questionSource.nextQuestion(lastWordId: question.wordId)
        state.currentQuestion = next
        rememberWord(next.wordId)
        return outcome
    }

    /// Ends the battle immediately as a loss (Escape button).
    func escapeBattle() {
        guard state.status == .playing else { return }
        finish(status: .lost)
    }

    func tick(deltaSeconds: Int) -> TickOutcome {
        guard state.status == .playing else { return TickOutcome() }
        state.remainingSeconds -= deltaSeconds
        if state.remainingSeconds <= 0 {
            state.remainingSeconds = 0
            finish(status: .lost)
            return TickOutcome(battleEnded: true, endStatus: .lost)
        }
        return TickOutcome()
    }

    func buildSessionResult() throws -> SessionResult {
        guard state.status == .won || state.status == .lost else {
            throw BattleError.notPlaying
        }
        let rate = state.totalAnswers > 0 ? Double(state.correctAnswers) / Double(state.totalAnswers) : 0
        let stars = computeStars(rate: rate)
        return SessionResult(
            status: state.status,
            defeatedMonsters: state.defeatedMonsters,
            monstersTotal: state.monstersTotal,
            totalAnswers: state.totalAnswers,
            correctAnswers: state.correctAnswers,
            correctRate: rate,
            learnedWordCount: state.learnedWordIds.count,
            stars: stars,
            coinsEarned: BattleRewardCalc.coinAward(monsterLevelScore: state.defeatedMonsterLevelScore),
            bonusKillCount: state.bonusKillCount,
            monsterLevelScore: state.defeatedMonsterLevelScore
        )
    }

    private func finish(status: BattleStatus) {
        state.status = status
        state.currentQuestion = nil
    }

    private func options(for question: Question) -> [String] {
        switch question.kind {
        case .choice:
            question.options
        case .fillLetter:
            question.letterOptions
        case .fillLetterMedium:
            question.letterOptionsSteps.indices.contains(question.currentStep) ? question.letterOptionsSteps[question.currentStep] : []
        case .spell:
            [question.answer]
        }
    }

    private func isCorrect(option: String, question: Question) -> Bool {
        switch question.kind {
        case .choice, .spell:
            option == question.answer
        case .fillLetter:
            option == question.letterAnswer
        case .fillLetterMedium:
            question.letterAnswers.indices.contains(question.currentStep) && option == question.letterAnswers[question.currentStep]
        }
    }

    private func revealMediumStepLetter(_ question: inout Question, chosen: String) {
        guard question.kind == .fillLetterMedium,
              question.letterAnswers.indices.contains(question.currentStep),
              question.letterAnswers[question.currentStep] == chosen,
              question.missingIndices.indices.contains(question.currentStep)
        else { return }

        guard let blankRange = question.letterTemplateBase.range(of: "_") else { return }
        question.letterTemplateBase.replaceSubrange(blankRange, with: chosen)
    }

    private func rememberWord(_ wordId: String) {
        guard !state.learnedWordIds.contains(wordId) else { return }
        state.learnedWordIds.append(wordId)
    }

    private func computeStars(rate: Double) -> Int {
        if state.status == .won && rate >= 0.8 {
            return 3
        }
        if state.status == .won || state.defeatedMonsters >= 3 {
            return 2
        }
        if state.defeatedMonsters >= 1 {
            return 1
        }
        return 0
    }

    private func catalogIndex(for battleMonsterIndex: Int) -> Int {
        monsterCatalogIndex(battleMonsterIndex)
    }

    private func monsterAttackDamage(for catalogIndex1Based: Int) -> Int {
        let level = MonsterCodex.level(forCatalogIndex1Based: catalogIndex1Based)
        guard level == .advanced || level == .super else { return 1 }
        return randomDouble() < 0.5 ? 2 : 1
    }

    private func rollsBonusMonster(for catalogIndex1Based: Int) -> Bool {
        let level = MonsterCodex.level(forCatalogIndex1Based: catalogIndex1Based)
        guard level == .advanced || level == .super else { return false }
        return randomDouble() < 0.3
    }
}
