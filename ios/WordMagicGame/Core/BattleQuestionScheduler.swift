import Foundation

enum BattleScheduleMode: String, Equatable {
    case singleType = "single_type"
    case stageOrdered = "stage_ordered"
}

struct BattleQuestionPick: Equatable {
    var kind: String = ""
    var preferredWordId: String = ""
}

typealias WordKindSupportFn = (_ wordId: String, _ kind: String) -> Bool

private struct BattleStage {
    var kind: String
    var wordIds: [String]
    var servedIds: [String] = []
    var cursor = 0
}

final class BattleQuestionScheduler {
    private var stages: [BattleStage] = []
    private let rng: () -> Double
    private var activeStageIndex = 0
    private var lastMonsterIndex = 0
    private var monsterStageByIndex: [Int: Int] = [:]
    private var monsterCatalogByIndex: [Int: Int] = [:]

    init(
        planWordIds: [String],
        enabledTypes: [String],
        canServe: WordKindSupportFn? = nil,
        rng: @escaping () -> Double = { Double.random(in: 0 ..< 1) },
    ) {
        self.rng = rng
        let uniqueWordIds = Self.uniqueNonEmpty(planWordIds)
        let safeTypes = BattleQuestionTypePolicy.sanitizeEnabledQuestionTypes(enabledTypes)
        let support: WordKindSupportFn = canServe ?? { _, _ in true }

        for kind in safeTypes {
            let wordIds = uniqueWordIds.filter { support($0, kind) }
            if !wordIds.isEmpty {
                stages.append(BattleStage(kind: kind, wordIds: wordIds))
            }
        }
    }

    func scheduleMode() -> BattleScheduleMode {
        stages.count == 1 ? .singleType : .stageOrdered
    }

    func activeKindForTest() -> String {
        currentStage()?.kind ?? ""
    }

    func activePhasePool() -> [String] {
        guard let stage = currentStage() else {
            return [QuestionKind.choice.rawValue]
        }
        return [stage.kind]
    }

    func pickNext(
        monsterIndex: Int,
        lastWordId: String?,
        canServe _: WordKindSupportFn? = nil,
    ) -> BattleQuestionPick {
        syncMonsterIndex(monsterIndex)
        guard let stage = currentStage() else {
            return BattleQuestionPick(kind: QuestionKind.choice.rawValue, preferredWordId: "")
        }
        return BattleQuestionPick(kind: stage.kind, preferredWordId: pickWord(from: stage, lastWordId: lastWordId))
    }

    func pickNext(lastWordId: String?, canServe: WordKindSupportFn) -> BattleQuestionPick {
        pickNext(monsterIndex: max(lastMonsterIndex, 1), lastWordId: lastWordId)
    }

    func markServed(wordId: String, kind: String, canServe _: WordKindSupportFn? = nil) {
        guard !wordId.isEmpty,
              let stageIndex = currentStageIndex(),
              stages[stageIndex].kind == kind,
              stages[stageIndex].wordIds.contains(wordId)
        else { return }

        if !stages[stageIndex].servedIds.contains(wordId) {
            stages[stageIndex].servedIds.append(wordId)
            advanceCoveredStages()
        }
    }

    func catalogIndexForMonster(monsterIndex: Int) -> Int {
        let safeIndex = max(monsterIndex, 1)
        syncMonsterIndex(safeIndex)
        if let existing = monsterCatalogByIndex[safeIndex], existing > 0 {
            return existing
        }

        let stageIndex = monsterStageByIndex[safeIndex] ?? activeStageIndex
        let kind = stages.indices.contains(stageIndex) ? stages[stageIndex].kind : QuestionKind.choice.rawValue
        let level = Self.monsterLevel(forQuestionType: kind)
        let pool = MonsterCodex.catalogIndices(for: level)
        let rawIndex = Int((rng() * Double(pool.count)).rounded(.down))
        let index = min(max(rawIndex, 0), pool.count - 1)
        let catalogIndex = pool[index]
        monsterCatalogByIndex[safeIndex] = catalogIndex
        return catalogIndex
    }

    private func syncMonsterIndex(_ monsterIndex: Int) {
        let safeIndex = max(monsterIndex, 1)
        if lastMonsterIndex == 0 || safeIndex != lastMonsterIndex {
            lastMonsterIndex = safeIndex
        }
        if monsterStageByIndex[safeIndex] == nil {
            monsterStageByIndex[safeIndex] = activeStageIndex
        }
    }

    private func currentStageIndex() -> Int? {
        guard !stages.isEmpty else { return nil }
        return min(activeStageIndex, stages.count - 1)
    }

    private func currentStage() -> BattleStage? {
        guard let index = currentStageIndex() else { return nil }
        return stages[index]
    }

    private func pickWord(from stage: BattleStage, lastWordId: String?) -> String {
        guard let stageIndex = currentStageIndex() else { return "" }
        let wordIds = stage.wordIds
        guard !wordIds.isEmpty else { return "" }

        let covered = isCovered(stage)
        var deferredRepeat: String?
        for _ in 0 ..< wordIds.count {
            let index = stages[stageIndex].cursor % wordIds.count
            let wordId = wordIds[index]
            stages[stageIndex].cursor = (stages[stageIndex].cursor + 1) % wordIds.count

            if !covered, stage.servedIds.contains(wordId) {
                continue
            }
            if let lastWordId, wordIds.count > 1, wordId == lastWordId {
                deferredRepeat = deferredRepeat ?? wordId
                continue
            }
            return wordId
        }
        return deferredRepeat ?? wordIds[0]
    }

    private func isCovered(_ stage: BattleStage) -> Bool {
        stage.servedIds.count >= stage.wordIds.count
    }

    private func advanceCoveredStages() {
        while activeStageIndex < stages.count - 1 {
            guard let stage = currentStage(), isCovered(stage) else { return }
            activeStageIndex += 1
        }
    }

    private static func monsterLevel(forQuestionType kind: String) -> MonsterLevel {
        switch kind {
        case QuestionKind.fillLetter.rawValue:
            return .intermediate
        case QuestionKind.fillLetterMedium.rawValue:
            return .advanced
        case QuestionKind.spell.rawValue, QuestionKind.sentenceCloze.rawValue:
            return .super
        default:
            return .beginner
        }
    }

    private static func uniqueNonEmpty(_ input: [String]) -> [String] {
        var out: [String] = []
        for id in input where !id.isEmpty && !out.contains(id) {
            out.append(id)
        }
        return out
    }
}
