import Foundation

struct WordLearningStat: Equatable {
    var wordId: String
    var attempts: Int
    var correct: Int
    var lastSeenAt: Date

    var accuracy: Double {
        attempts == 0 ? 0 : Double(correct) / Double(attempts)
    }
}

final class LearningRecorder {
    private(set) var statsByWordId: [String: WordLearningStat] = [:]

    func record(wordId: String, correct: Bool, at date: Date = Date()) {
        var stat = statsByWordId[wordId] ?? WordLearningStat(wordId: wordId, attempts: 0, correct: 0, lastSeenAt: date)
        stat.attempts += 1
        if correct {
            stat.correct += 1
        }
        stat.lastSeenAt = date
        statsByWordId[wordId] = stat
    }

    func stat(for wordId: String) -> WordLearningStat? {
        statsByWordId[wordId]
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

        if learning.isEmpty {
            learning = Array(newWords.prefix(2))
        }
        if newWords.isEmpty {
            newWords = Array(pack.words.prefix(2))
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
