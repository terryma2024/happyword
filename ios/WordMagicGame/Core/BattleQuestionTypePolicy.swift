import Foundation

/// Parity with Harmony `BattleQuestionTypePolicy.ets` — ordering, sanitization,
/// word support checks, and mapping config question-type ids to battle slot kinds.
enum BattleQuestionTypePolicy {
    static let defaultOrderedTypeIds: [String] = [
        QuestionKind.choice.rawValue,
        QuestionKind.fillLetter.rawValue,
        QuestionKind.fillLetterMedium.rawValue,
        QuestionKind.spell.rawValue,
        QuestionKind.sentenceCloze.rawValue,
    ]

    static func sanitizeEnabledQuestionTypes(_ raw: [String]) -> [String] {
        var out: [String] = []
        for t in defaultOrderedTypeIds where raw.contains(t) && !out.contains(t) {
            out.append(t)
        }
        if out.isEmpty {
            return defaultOrderedTypeIds
        }
        return out
    }

    static func monsterSlotKind(forQuestionTypeId typeId: String) -> MonsterPlanSlotKind {
        switch typeId {
        case QuestionKind.fillLetter.rawValue:
            return .spelling
        case QuestionKind.fillLetterMedium.rawValue:
            return .elite
        case QuestionKind.spell.rawValue, QuestionKind.sentenceCloze.rawValue:
            return .boss
        default:
            return .normal
        }
    }

    private static func catalogIndex(for kind: MonsterPlanSlotKind) -> Int {
        switch kind {
        case .normal:
            return 1
        case .spelling, .review:
            return 2
        case .elite:
            return 3
        case .boss:
            return 4
        }
    }

    static func buildMonsterSlots(enabledTypeIds: [String], slotCount: Int = 5) -> [MonsterPlanSlot] {
        let safe = sanitizeEnabledQuestionTypes(enabledTypeIds)
        return (0 ..< slotCount).map { index in
            let typeId = safe[index % safe.count]
            let kind = monsterSlotKind(forQuestionTypeId: typeId)
            return MonsterPlanSlot(kind: kind, catalogIndex: catalogIndex(for: kind))
        }
    }

    private static func alphaLetterCount(_ word: String) -> Int {
        word.lowercased().filter { $0 >= "a" && $0 <= "z" }.count
    }

    static func wordSupportsQuestionType(_ word: WordEntry, typeId: String) -> Bool {
        let letters = alphaLetterCount(word.word)
        switch typeId {
        case QuestionKind.choice.rawValue:
            return !word.word.isEmpty
        case QuestionKind.fillLetter.rawValue:
            return letters >= 3
        case QuestionKind.fillLetterMedium.rawValue:
            return letters >= 4
        case QuestionKind.spell.rawValue:
            return letters >= 4 && letters <= 9
        case QuestionKind.sentenceCloze.rawValue:
            return wordSupportsSentenceCloze(word)
        default:
            return false
        }
    }

    static func anyWordSupportsQuestionTypes(_ words: [WordEntry], typeIds: [String]) -> Bool {
        let safe = sanitizeEnabledQuestionTypes(typeIds)
        for word in words {
            for typeId in safe where wordSupportsQuestionType(word, typeId: typeId) {
                return true
            }
        }
        return false
    }

    static func questionTypeFallbackChain(primaryType: String) -> [String] {
        switch primaryType {
        case QuestionKind.spell.rawValue:
            return [
                QuestionKind.spell.rawValue,
                QuestionKind.fillLetterMedium.rawValue,
                QuestionKind.fillLetter.rawValue,
                QuestionKind.choice.rawValue,
            ]
        case QuestionKind.sentenceCloze.rawValue:
            return [
                QuestionKind.sentenceCloze.rawValue,
                QuestionKind.fillLetterMedium.rawValue,
                QuestionKind.spell.rawValue,
                QuestionKind.fillLetter.rawValue,
                QuestionKind.choice.rawValue,
            ]
        case QuestionKind.fillLetterMedium.rawValue:
            return [
                QuestionKind.fillLetterMedium.rawValue,
                QuestionKind.fillLetter.rawValue,
                QuestionKind.choice.rawValue,
            ]
        case QuestionKind.fillLetter.rawValue:
            return [QuestionKind.fillLetter.rawValue, QuestionKind.choice.rawValue]
        default:
            return [QuestionKind.choice.rawValue]
        }
    }

    static func resolveQuestionTypeForWord(_ word: WordEntry, primaryType: String) -> String {
        for typeId in questionTypeFallbackChain(primaryType: primaryType)
            where wordSupportsQuestionType(word, typeId: typeId) {
            return typeId
        }
        return QuestionKind.choice.rawValue
    }

    static func resolveQuestionTypeWithinPool(
        _ word: WordEntry,
        primaryType: String,
        pool: [String],
    ) -> String {
        for typeId in questionTypeFallbackChain(primaryType: primaryType)
            where pool.contains(typeId) && wordSupportsQuestionType(word, typeId: typeId) {
            return typeId
        }
        for typeId in pool where wordSupportsQuestionType(word, typeId: typeId) {
            return typeId
        }
        return QuestionKind.choice.rawValue
    }

    static func displayLabel(forTypeId typeId: String) -> String {
        switch typeId {
        case QuestionKind.choice.rawValue:
            return "中文选词"
        case QuestionKind.fillLetter.rawValue:
            return "单字母填空"
        case QuestionKind.fillLetterMedium.rawValue:
            return "双字母填空"
        case QuestionKind.spell.rawValue:
            return "多字母选择"
        case QuestionKind.sentenceCloze.rawValue:
            return "句子填词"
        default:
            return "题型"
        }
    }
}
