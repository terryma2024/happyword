import Foundation

enum BattleScheduleMode: String, Equatable {
    case singleType = "single_type"
    case introOnly = "intro_only"
    case challengeOnly = "challenge_only"
    case twoPhase = "two_phase"
}

struct BattleQuestionPick: Equatable {
    var kind: String = ""
    var preferredWordId: String = ""
}

typealias WordKindSupportFn = (_ wordId: String, _ kind: String) -> Bool

enum BattleQuestionSchedulerSupport {
    private static let introKinds = [QuestionKind.choice.rawValue, QuestionKind.fillLetter.rawValue]
    private static let challengeKinds = [
        QuestionKind.fillLetterMedium.rawValue,
        QuestionKind.spell.rawValue,
        QuestionKind.sentenceCloze.rawValue,
    ]

    static func intersectKinds(_ pool: [String], enabled: [String]) -> [String] {
        pool.filter { enabled.contains($0) }
    }

    static func deriveScheduleMode(
        enabledTypes: [String],
        introPool: [String],
        challengePool: [String],
    ) -> BattleScheduleMode {
        let safe = BattleQuestionTypePolicy.sanitizeEnabledQuestionTypes(enabledTypes)
        if safe.count == 1 {
            return .singleType
        }
        if introPool.isEmpty {
            return .challengeOnly
        }
        if challengePool.isEmpty {
            return .introOnly
        }
        return .twoPhase
    }

    fileprivate static var introKindsList: [String] { introKinds }
    fileprivate static var challengeKindsList: [String] { challengeKinds }
}

final class BattleQuestionScheduler {
    private let mode: BattleScheduleMode
    private let effectiveIntroPool: [String]
    private let effectiveChallengePool: [String]
    private let singleType: String
    private let rng: () -> Double
    private let planWordIds: [String]
    private let shuffledWordIds: [String]
    private var wordCursor = 0
    private var servedChoice: [String] = []
    private var servedFillLetter: [String] = []
    private var introPassComplete = false
    private var lastIntroKind = ""

    init(planWordIds: [String], enabledTypes: [String], rng: @escaping () -> Double = { Double.random(in: 0 ..< 1) }) {
        self.rng = rng
        let safe = BattleQuestionTypePolicy.sanitizeEnabledQuestionTypes(enabledTypes)
        effectiveIntroPool = BattleQuestionSchedulerSupport.intersectKinds(
            BattleQuestionSchedulerSupport.introKindsList,
            enabled: safe,
        )
        effectiveChallengePool = BattleQuestionSchedulerSupport.intersectKinds(
            BattleQuestionSchedulerSupport.challengeKindsList,
            enabled: safe,
        )
        mode = BattleQuestionSchedulerSupport.deriveScheduleMode(
            enabledTypes: safe,
            introPool: effectiveIntroPool,
            challengePool: effectiveChallengePool,
        )
        singleType = safe.count == 1 ? safe[0] : ""
        var uniqueIds: [String] = []
        for id in planWordIds where !id.isEmpty && !uniqueIds.contains(id) {
            uniqueIds.append(id)
        }
        self.planWordIds = uniqueIds
        shuffledWordIds = shuffled(uniqueIds, random: rng)
    }

    func scheduleMode() -> BattleScheduleMode { mode }

    func effectiveIntroKinds() -> [String] { effectiveIntroPool }

    func effectiveChallengeKinds() -> [String] { effectiveChallengePool }

    func isIntroPassActive() -> Bool {
        switch mode {
        case .challengeOnly, .singleType:
            return false
        case .twoPhase:
            return !introPassComplete
        case .introOnly:
            return !introPassComplete
        }
    }

    func activePhasePool() -> [String] {
        switch mode {
        case .singleType:
            return [singleType]
        case .challengeOnly:
            return effectiveChallengePool
        case .introOnly, .twoPhase:
            if isIntroPassActive() || mode == .introOnly {
                return effectiveIntroPool
            }
            return effectiveChallengePool
        }
    }

    func markServed(wordId: String, kind: String, canServe: WordKindSupportFn) {
        if kind == QuestionKind.choice.rawValue, !servedChoice.contains(wordId) {
            servedChoice.append(wordId)
        }
        if kind == QuestionKind.fillLetter.rawValue, !servedFillLetter.contains(wordId) {
            servedFillLetter.append(wordId)
        }
        if (mode == .twoPhase || mode == .introOnly), !introPassComplete {
            if checkIntroPassComplete(canServe: canServe) {
                introPassComplete = true
            }
        }
    }

    func pickNext(lastWordId: String?, canServe: WordKindSupportFn) -> BattleQuestionPick {
        var out = BattleQuestionPick()
        switch mode {
        case .singleType:
            out.kind = singleType
            return out
        case .challengeOnly:
            out.kind = rollChallengeKind()
            return out
        case .twoPhase where introPassComplete:
            out.kind = rollChallengeKind()
            return out
        case .introOnly where introPassComplete:
            return pickIntroSustain(lastWordId: lastWordId, canServe: canServe)
        default:
            return pickIntroPass(lastWordId: lastWordId, canServe: canServe)
        }
    }

    private func rollChallengeKind() -> String {
        if effectiveChallengePool.count == 1 {
            return effectiveChallengePool[0]
        }
        if effectiveChallengePool.count >= 2 {
            let raw = Int((rng() * Double(effectiveChallengePool.count)).rounded(.down))
            let index = min(max(raw, 0), effectiveChallengePool.count - 1)
            return effectiveChallengePool[index]
        }
        return QuestionKind.choice.rawValue
    }

    private func pickIntroPass(lastWordId: String?, canServe: WordKindSupportFn) -> BattleQuestionPick {
        var pick = scanIntroWords(lastWordId: lastWordId, canServe: canServe, requireUnserved: true)
        if !pick.kind.isEmpty {
            lastIntroKind = pick.kind
        } else {
            introPassComplete = true
            pick.kind = rollChallengeKind()
        }
        return pick
    }

    private func pickIntroSustain(lastWordId: String?, canServe: WordKindSupportFn) -> BattleQuestionPick {
        var pick = scanIntroWords(lastWordId: lastWordId, canServe: canServe, requireUnserved: false)
        if !pick.kind.isEmpty {
            lastIntroKind = pick.kind
            return pick
        }
        pick.kind = effectiveIntroPool.first ?? QuestionKind.choice.rawValue
        return pick
    }

    private func scanIntroWords(
        lastWordId: String?,
        canServe: WordKindSupportFn,
        requireUnserved: Bool,
    ) -> BattleQuestionPick {
        let order = shuffledWordIds.isEmpty ? planWordIds : shuffledWordIds
        let attempts = order.isEmpty ? 1 : order.count
        for attempt in 0 ..< attempts {
            let wordId = order.isEmpty ? "" : order[(wordCursor + attempt) % order.count]
            if wordId.isEmpty { continue }
            if let lastWordId, wordId == lastWordId, order.count > 1 { continue }
            let kinds = availableIntroKindsForWord(wordId: wordId, canServe: canServe, requireUnserved: requireUnserved)
            if kinds.isEmpty { continue }
            var pick = BattleQuestionPick()
            pick.preferredWordId = wordId
            pick.kind = pickAlternatingIntroKind(kinds)
            wordCursor = order.isEmpty ? 0 : (wordCursor + attempt + 1) % order.count
            return pick
        }
        return BattleQuestionPick()
    }

    private func availableIntroKindsForWord(
        wordId: String,
        canServe: WordKindSupportFn,
        requireUnserved: Bool,
    ) -> [String] {
        var kinds: [String] = []
        for kind in effectiveIntroPool {
            guard canServe(wordId, kind) else { continue }
            if requireUnserved, isServed(wordId: wordId, kind: kind) { continue }
            if !requireUnserved, isServed(wordId: wordId, kind: kind) { continue }
            kinds.append(kind)
        }
        if !requireUnserved, kinds.isEmpty {
            for kind in effectiveIntroPool where canServe(wordId, kind) {
                kinds.append(kind)
            }
        }
        return kinds
    }

    private func pickAlternatingIntroKind(_ kinds: [String]) -> String {
        if kinds.count == 1 { return kinds[0] }
        if lastIntroKind == QuestionKind.choice.rawValue,
           kinds.contains(QuestionKind.fillLetter.rawValue) {
            return QuestionKind.fillLetter.rawValue
        }
        if lastIntroKind == QuestionKind.fillLetter.rawValue,
           kinds.contains(QuestionKind.choice.rawValue) {
            return QuestionKind.choice.rawValue
        }
        return kinds[0]
    }

    private func isServed(wordId: String, kind: String) -> Bool {
        if kind == QuestionKind.choice.rawValue {
            return servedChoice.contains(wordId)
        }
        if kind == QuestionKind.fillLetter.rawValue {
            return servedFillLetter.contains(wordId)
        }
        return false
    }

    private func checkIntroPassComplete(canServe: WordKindSupportFn) -> Bool {
        if planWordIds.isEmpty { return true }
        for wordId in planWordIds {
            for kind in effectiveIntroPool where canServe(wordId, kind) && !isServed(wordId: wordId, kind: kind) {
                return false
            }
        }
        return true
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
