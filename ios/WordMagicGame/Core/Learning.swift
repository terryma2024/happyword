import Foundation

enum WordLearningOutcome: String, Codable, Equatable {
    case correct
    case wrong
    case unknown
}

enum WordMemoryState: String, Codable, Equatable {
    case new
    case learning
    case familiar
    case review
    case mastered
}

struct WordLearningStat: Equatable, Codable {
    var wordId: String
    var seenCount: Int
    var correctCount: Int
    var wrongCount: Int
    var lastAnsweredAt: Date
    var nextReviewAt: Date?
    var memoryState: WordMemoryState
    var lastOutcome: WordLearningOutcome
    var consecutiveCorrect: Int
    var consecutiveWrong: Int
    var mastery: Double

    init(
        wordId: String,
        attempts: Int,
        correct: Int,
        lastSeenAt: Date
    ) {
        self.init(
            wordId: wordId,
            seenCount: attempts,
            correctCount: correct,
            wrongCount: max(attempts - correct, 0),
            lastAnsweredAt: lastSeenAt,
            nextReviewAt: attempts > 0 ? lastSeenAt.addingTimeInterval(86_400) : nil,
            memoryState: attempts >= 3 && attempts > 0 && Double(correct) / Double(attempts) >= 0.9 ? .mastered : (attempts > 0 ? .learning : .new),
            lastOutcome: .unknown,
            consecutiveCorrect: attempts > 0 && correct == attempts ? correct : 0,
            consecutiveWrong: attempts > 0 && correct == 0 ? max(attempts - correct, 0) : 0,
            mastery: attempts == 0 ? 0 : min(max(Double(correct) / Double(attempts), 0), 1)
        )
    }

    init(
        wordId: String,
        seenCount: Int,
        correctCount: Int,
        wrongCount: Int,
        lastAnsweredAt: Date,
        nextReviewAt: Date? = nil,
        memoryState: WordMemoryState = .new,
        lastOutcome: WordLearningOutcome = .unknown,
        consecutiveCorrect: Int = 0,
        consecutiveWrong: Int = 0,
        mastery: Double = 0
    ) {
        self.wordId = wordId
        self.seenCount = max(seenCount, 0)
        self.correctCount = max(correctCount, 0)
        self.wrongCount = max(wrongCount, 0)
        self.lastAnsweredAt = lastAnsweredAt
        self.nextReviewAt = nextReviewAt
        self.memoryState = memoryState
        self.lastOutcome = lastOutcome
        self.consecutiveCorrect = max(consecutiveCorrect, 0)
        self.consecutiveWrong = max(consecutiveWrong, 0)
        self.mastery = min(max(mastery, 0), 1)
    }

    var attempts: Int {
        get { seenCount }
        set { seenCount = max(newValue, 0) }
    }

    var correct: Int {
        get { correctCount }
        set { correctCount = max(newValue, 0) }
    }

    var lastSeenAt: Date {
        get { lastAnsweredAt }
        set { lastAnsweredAt = newValue }
    }

    var accuracy: Double {
        seenCount == 0 ? 0 : Double(correctCount) / Double(seenCount)
    }

    var wrong: Int {
        wrongCount
    }
}

final class LearningRecorder {
    private static let key = "wordmagic_learning_recorder/snapshot_v1"

    private struct Snapshot: Codable, Equatable {
        var version: Int = 1
        var statsByWordId: [String: WordLearningStat]
    }

    private(set) var statsByWordId: [String: WordLearningStat] = [:]
    private let defaults: UserDefaults?

    init(defaults: UserDefaults? = nil, statsByWordId: [String: WordLearningStat] = [:]) {
        self.defaults = defaults
        if ProcessInfo.processInfo.arguments.contains("-UITestResetState") {
            defaults?.removeObject(forKey: Self.key)
        }
        if statsByWordId.isEmpty,
           let data = defaults?.data(forKey: Self.key),
           let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            self.statsByWordId = snapshot.statsByWordId
        } else {
            self.statsByWordId = statsByWordId
        }
    }

    func record(wordId: String, correct: Bool, at date: Date = Date()) {
        var stat = statsByWordId[wordId] ?? WordLearningStat(wordId: wordId, attempts: 0, correct: 0, lastSeenAt: date)
        stat.seenCount += 1
        if correct {
            stat.correctCount += 1
            stat.lastOutcome = .correct
            stat.consecutiveCorrect += 1
            stat.consecutiveWrong = 0
            stat.mastery = min(stat.mastery + 0.1, 1)
            stat.nextReviewAt = date.addingTimeInterval(86_400)
        }
        if !correct {
            stat.wrongCount += 1
            stat.lastOutcome = .wrong
            stat.consecutiveWrong += 1
            stat.consecutiveCorrect = 0
            stat.mastery = max(stat.mastery - 0.2, 0)
            stat.nextReviewAt = date.addingTimeInterval(86_400)
        }
        stat.lastAnsweredAt = date
        stat.memoryState = Self.memoryState(for: stat)
        statsByWordId[wordId] = stat
        save()
    }

    func stat(for wordId: String) -> WordLearningStat? {
        statsByWordId[wordId]
    }

    func recentWrongIds(limit: Int) -> [String] {
        guard limit > 0 else { return [] }
        return statsByWordId.values
            .filter { $0.wrong > 0 }
            .sorted { lhs, rhs in
                if lhs.lastAnsweredAt == rhs.lastAnsweredAt {
                    return lhs.wordId < rhs.wordId
                }
                return lhs.lastAnsweredAt > rhs.lastAnsweredAt
            }
            .prefix(limit)
            .map(\.wordId)
    }

    func allStats() -> [WordLearningStat] {
        Array(statsByWordId.values)
    }

    private static func memoryState(for stat: WordLearningStat) -> WordMemoryState {
        if stat.seenCount >= 3 && stat.accuracy >= 0.9 {
            return .mastered
        }
        if stat.seenCount > 0 && stat.lastOutcome == .wrong {
            return .review
        }
        if stat.seenCount >= 2 {
            return .familiar
        }
        if stat.seenCount > 0 {
            return .learning
        }
        return .new
    }

    private func save() {
        guard let defaults else { return }
        let snapshot = Snapshot(statsByWordId: statsByWordId)
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: Self.key)
        }
    }
}

enum ReviewReason: String, Codable, Equatable {
    case dueReview = "due_review"
    case recentWrong = "recent_wrong"
    case weakWord = "weak_word"
}

struct DailyReviewItem: Codable, Equatable {
    var wordId = ""
    var reasons: [ReviewReason] = []
    var primaryReason: ReviewReason = .dueReview
    var score = 0
    var lastAnsweredAt = Date(timeIntervalSince1970: 0)
}

struct DailyReviewSnapshot: Codable, Equatable {
    var dayKey = ""
    var generatedAt = Date(timeIntervalSince1970: 0)
    var sourceCutoff = Date(timeIntervalSince1970: 0)
    var wordIds: [String] = []
    var reviewedWordIds: [String] = []
    var items: [DailyReviewItem] = []

    var remainingWordIds: [String] {
        let reviewed = Set(reviewedWordIds)
        return wordIds.filter { !reviewed.contains($0) }
    }
}

struct DailyLearningState: Codable, Equatable {
    var dayKey = ""
    var packBattleWon = false
    var reviewAllDone = true
    var reviewSnapshot = DailyReviewSnapshot()

    init(dayKey: String = "") {
        self.dayKey = dayKey
    }
}

struct HomeDailyStatus: Equatable {
    var label = ""
    var remainingReviewCount = 0
    var todayAdventureCompleted = false
    var dailyCheckInCompleted = false

    static func decide(from state: DailyLearningState) -> HomeDailyStatus {
        let remaining = state.reviewSnapshot.remainingWordIds.count
        let packDone = state.packBattleWon
        let reviewDone = remaining == 0
        let adventureDone = packDone && reviewDone
        return HomeDailyStatus(
            label: adventureDone ? "已完成" : (packDone ? "请点击复习加战斗(\(remaining))" : "请选择一个场景加战斗"),
            remainingReviewCount: remaining,
            todayAdventureCompleted: adventureDone,
            dailyCheckInCompleted: packDone || reviewDone
        )
    }
}

enum DailyLearningDayKey {
    static func compact(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d%02d%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func localStartOfDay(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: date)
    }
}

enum ReviewBattleTuning {
    static let reviewBattleSeconds = 10 * 60

    static func reviewMonsterCount(requiredWordCount: Int, monsterHp: Int, configuredTotal: Int, defaultMonsterHp: Int) -> Int {
        guard requiredWordCount > 0 else { return 1 }
        let hp = monsterHp > 0 ? monsterHp : defaultMonsterHp
        let safeHp = hp > 0 ? hp : 5
        let answersPerMonster = Double(safeHp) * 4.0 / 3.0
        let rawCount = Int(ceil(Double(requiredWordCount) / answersPerMonster))
        return min(max(rawCount, 1), max(configuredTotal, 1))
    }
}

struct ReviewQueueBuilder {
    private let reviewLimit = 50
    private let recentWrongWindow: TimeInterval = 7 * 86_400

    func buildSnapshot(
        words: [WordEntry],
        stats: [WordLearningStat],
        now: Date,
        selectedWordIds: [String],
        calendar: Calendar = .current
    ) -> DailyReviewSnapshot {
        let cutoff = DailyLearningDayKey.localStartOfDay(now, calendar: calendar)
        let statById = Dictionary(uniqueKeysWithValues: stats.filter { !$0.wordId.isEmpty }.map { ($0.wordId, $0) })
        let selected = Set(selectedWordIds)
        var seen = Set<String>()
        let wordIds = words.compactMap { word -> String? in
            guard !word.id.isEmpty, !seen.contains(word.id) else { return nil }
            seen.insert(word.id)
            return word.id
        }
        var items: [DailyReviewItem] = []
        for wordId in wordIds {
            guard let stat = statById[wordId], stat.lastAnsweredAt < cutoff else { continue }
            let item = reviewItem(wordId: wordId, stat: stat, cutoff: cutoff, selectedBoost: selected.contains(wordId))
            if !item.reasons.isEmpty {
                items.append(item)
            }
        }
        items.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.lastAnsweredAt != $1.lastAnsweredAt { return $0.lastAnsweredAt > $1.lastAnsweredAt }
            return $0.wordId < $1.wordId
        }
        let capped = Array(items.prefix(reviewLimit))
        return DailyReviewSnapshot(
            dayKey: DailyLearningDayKey.compact(now, calendar: calendar),
            generatedAt: now,
            sourceCutoff: cutoff,
            wordIds: capped.map(\.wordId),
            reviewedWordIds: [],
            items: capped
        )
    }

    private func reviewItem(wordId: String, stat: WordLearningStat, cutoff: Date, selectedBoost: Bool) -> DailyReviewItem {
        var reasons: [ReviewReason] = []
        var score = 0

        if let nextReview = stat.nextReviewAt, nextReview <= cutoff {
            reasons.append(.dueReview)
            score += 100
            let overdueDays = Int(floor(cutoff.timeIntervalSince(nextReview) / 86_400))
            score += min(max(overdueDays, 0), 14) * 4
        }
        if inferredLastOutcome(stat) == .wrong,
           stat.lastAnsweredAt.timeIntervalSince1970 > 0,
           cutoff.timeIntervalSince(stat.lastAnsweredAt) <= recentWrongWindow {
            reasons.append(.recentWrong)
            score += 80
            let ageDays = Int(floor(cutoff.timeIntervalSince(stat.lastAnsweredAt) / 86_400))
            if ageDays <= 1 {
                score += 20
            } else if ageDays <= 3 {
                score += 10
            } else if ageDays <= 7 {
                score += 5
            }
        }
        if isWeakWord(stat) {
            reasons.append(.weakWord)
            score += 50
        }
        if selectedBoost {
            score += 5
        }
        return DailyReviewItem(
            wordId: wordId,
            reasons: reasons,
            primaryReason: reasons.first ?? .dueReview,
            score: score,
            lastAnsweredAt: stat.lastAnsweredAt
        )
    }

    private func inferredLastOutcome(_ stat: WordLearningStat) -> WordLearningOutcome {
        if stat.lastOutcome == .correct || stat.lastOutcome == .wrong {
            return stat.lastOutcome
        }
        if stat.consecutiveWrong > 0 {
            return .wrong
        }
        if stat.consecutiveCorrect > 0 {
            return .correct
        }
        return .unknown
    }

    private func isWeakWord(_ stat: WordLearningStat) -> Bool {
        guard stat.memoryState != .mastered else { return false }
        if stat.seenCount >= 3 && stat.accuracy < 0.6 {
            return true
        }
        if stat.wrongCount >= 2 && stat.correctCount <= stat.wrongCount {
            return true
        }
        return stat.seenCount >= 2 && stat.mastery <= 0.35
    }
}

struct TodayPlan: Equatable {
    var packId: String
    var review: [WordEntry]
    var learning: [WordEntry]
    var newWords: [WordEntry]
}

struct TodayPlanService {
    func build(pack: Pack, recorder: LearningRecorder, now: Date = Date()) -> TodayPlan {
        var review: [WordEntry] = []
        var learning: [WordEntry] = []
        var newWords: [WordEntry] = []
        let reviewInterval: TimeInterval = 86_400 * 2

        for word in pack.words {
            guard let stat = recorder.stat(for: word.id) else {
                newWords.append(word)
                continue
            }
            if now.timeIntervalSince(stat.lastSeenAt) >= reviewInterval {
                review.append(word)
            } else {
                learning.append(word)
            }
        }

        return TodayPlan(packId: pack.id, review: review, learning: learning, newWords: newWords)
    }
}

struct PackReportRow: Equatable, Identifiable {
    var id: String { packId }
    var packId: String
    var packTitle: String
    var source: PackSource
    var isActive: Bool
    var seenWords: Int
    var correctAnswers: Int
    var attempts: Int

    var accuracy: Double {
        attempts == 0 ? 0 : Double(correctAnswers) / Double(attempts)
    }
}

struct LearningReport: Equatable {
    var totalSeenWords: Int
    var totalAttempts: Int
    var correctAnswers: Int
    var packRows: [PackReportRow]
}

struct LearningReportBuilder {
    func build(library: PackLibrary, activePackIds: [String], recorder: LearningRecorder, now: Date = Date()) -> LearningReport {
        let allPacks = library.allPacks()
        let activeSet = Set(activePackIds)
        let knownWordIds = Set(allPacks.flatMap { $0.words.map(\.id) })
        let stats = recorder.statsByWordId.values.filter { knownWordIds.contains($0.wordId) }
        let statByWordId = Dictionary(uniqueKeysWithValues: stats.map { ($0.wordId, $0) })

        let rows = allPacks.compactMap { pack -> PackReportRow? in
            let packStats = pack.words.compactMap { statByWordId[$0.id] }
            let isActive = activeSet.contains(pack.id)
            if !isActive && packStats.isEmpty {
                return nil
            }
            return PackReportRow(
                packId: pack.id,
                packTitle: pack.title,
                source: pack.source,
                isActive: isActive,
                seenWords: packStats.count,
                correctAnswers: packStats.reduce(0) { $0 + $1.correct },
                attempts: packStats.reduce(0) { $0 + $1.attempts }
            )
        }

        let activeRows = activePackIds.compactMap { id in rows.first { $0.packId == id } }
        let inactiveRows = rows
            .filter { !$0.isActive }
            .sorted {
                if $0.accuracy == $1.accuracy {
                    return $0.packId < $1.packId
                }
                return $0.accuracy < $1.accuracy
            }

        return LearningReport(
            totalSeenWords: Set(stats.map(\.wordId)).count,
            totalAttempts: stats.reduce(0) { $0 + $1.attempts },
            correctAnswers: stats.reduce(0) { $0 + $1.correct },
            packRows: activeRows + inactiveRows
        )
    }
}
