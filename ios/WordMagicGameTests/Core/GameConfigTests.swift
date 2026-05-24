@testable import WordMagicGame
import XCTest

final class GameConfigTests: XCTestCase {
    func testTimerValidationAcceptsPresetAndCustomBounds() {
        XCTAssertTrue(GameConfig.isValidTimer(30))
        XCTAssertTrue(GameConfig.isValidTimer(180))
        XCTAssertTrue(GameConfig.isValidTimer(300))
        XCTAssertTrue(GameConfig.isValidTimer(600))
        XCTAssertTrue(GameConfig.isValidTimer(1))
        XCTAssertTrue(GameConfig.isValidTimer(3600))
        XCTAssertFalse(GameConfig.isValidTimer(0))
        XCTAssertFalse(GameConfig.isValidTimer(3601))
    }

    func testStepperBoundsClampToHarmonyLimits() {
        XCTAssertEqual(GameConfig.clampHp(0), 1)
        XCTAssertEqual(GameConfig.clampHp(12), 10)
        XCTAssertEqual(GameConfig.clampMonsterCount(0), 1)
        XCTAssertEqual(GameConfig.clampMonsterCount(11), 10)
    }

    // MARK: - Custom timer dialog (parity with Harmony `validateCustomTimerSeconds`)

    func testValidateCustomTimerRejectsEmptyAndWhitespace() {
        let empty = GameConfig.validateCustomTimerInput("")
        XCTAssertFalse(empty.ok)
        XCTAssertFalse(empty.message.isEmpty)

        let ws = GameConfig.validateCustomTimerInput("   \t  ")
        XCTAssertFalse(ws.ok)
    }

    func testValidateCustomTimerRejectsNonDigitFloatNegative() {
        XCTAssertFalse(GameConfig.validateCustomTimerInput("3a").ok)
        XCTAssertFalse(GameConfig.validateCustomTimerInput("3.5").ok)
        XCTAssertFalse(GameConfig.validateCustomTimerInput("-5").ok)
    }

    func testValidateCustomTimerRejectsZeroAndAboveMax() {
        let zero = GameConfig.validateCustomTimerInput("0")
        XCTAssertFalse(zero.ok)
        XCTAssertTrue(zero.message.contains("\(GameConfig.timerCustomRange.lowerBound)"))

        let over = GameConfig.validateCustomTimerInput("3601")
        XCTAssertFalse(over.ok)
        XCTAssertTrue(over.message.contains("\(GameConfig.timerCustomRange.upperBound)"))
    }

    func testValidateCustomTimerAcceptsThreeSecondsAndTrimmable() {
        let three = GameConfig.validateCustomTimerInput("3")
        XCTAssertTrue(three.ok)
        XCTAssertEqual(three.seconds, 3)

        let spaced = GameConfig.validateCustomTimerInput("  42  ")
        XCTAssertTrue(spaced.ok)
        XCTAssertEqual(spaced.seconds, 42)
    }

    func testValidateCustomTimerAcceptsMinMax() {
        let minV = GameConfig.validateCustomTimerInput("\(GameConfig.timerCustomRange.lowerBound)")
        XCTAssertTrue(minV.ok)
        XCTAssertEqual(minV.seconds, GameConfig.timerCustomRange.lowerBound)

        let maxV = GameConfig.validateCustomTimerInput("\(GameConfig.timerCustomRange.upperBound)")
        XCTAssertTrue(maxV.ok)
        XCTAssertEqual(maxV.seconds, GameConfig.timerCustomRange.upperBound)
    }

    // MARK: - Question types (Harmony `enabledQuestionTypes` parity)

    func testDecodeGameConfigWithoutQuestionTypesUsesDefaults() throws {
        let json = Data(
            """
            {"playerMaxHp":5,"monsterMaxHp":3,"monstersTotal":5,"startingSeconds":300,"autoSpeak":true,"mode":"normal","parentPin":""}
            """.utf8,
        )
        let decoded = try JSONDecoder().decode(GameConfig.self, from: json)
        XCTAssertEqual(decoded.enabledQuestionTypes, BattleQuestionTypePolicy.defaultOrderedTypeIds)
    }

    func testSanitizeEnabledQuestionTypesDropsUnknownAndUsesDefaultOrder() {
        let mixed = ["spell", "nope", "choice", "fill-letter"]
        XCTAssertEqual(
            BattleQuestionTypePolicy.sanitizeEnabledQuestionTypes(mixed),
            ["choice", "fill-letter", "spell"],
        )
        XCTAssertEqual(
            BattleQuestionTypePolicy.sanitizeEnabledQuestionTypes([]),
            BattleQuestionTypePolicy.defaultOrderedTypeIds,
        )
    }

    func testEncodeRoundTripReordersQuestionTypesToPolicyOrder() throws {
        let cfg = GameConfig(enabledQuestionTypes: [QuestionKind.sentenceCloze.rawValue, QuestionKind.spell.rawValue, QuestionKind.choice.rawValue])
        let data = try JSONEncoder().encode(cfg)
        let decoded = try JSONDecoder().decode(GameConfig.self, from: data)
        XCTAssertEqual(decoded.enabledQuestionTypes, [QuestionKind.choice.rawValue, QuestionKind.spell.rawValue, QuestionKind.sentenceCloze.rawValue])
    }

    func testBuildMonsterSlotsCyclesSanitizedTypes() {
        let slots = BattleQuestionTypePolicy.buildMonsterSlots(enabledTypeIds: [QuestionKind.choice.rawValue], slotCount: 5)
        XCTAssertEqual(slots.count, 5)
        XCTAssertTrue(slots.allSatisfy { $0.kind == .normal })
    }

    func testAnyWordSupportsQuestionTypes() {
        let short = WordEntry(id: "a", word: "ab", meaningZh: "x", category: "c", difficulty: 1)
        XCTAssertFalse(
            BattleQuestionTypePolicy.anyWordSupportsQuestionTypes([short], typeIds: [QuestionKind.fillLetter.rawValue]),
        )
        let long = WordEntry(id: "b", word: "abcd", meaningZh: "x", category: "c", difficulty: 1)
        XCTAssertTrue(
            BattleQuestionTypePolicy.anyWordSupportsQuestionTypes([long], typeIds: [QuestionKind.fillLetter.rawValue]),
        )
        let cloze = WordEntry(
            id: "c",
            word: "apple",
            meaningZh: "x",
            category: "c",
            difficulty: 1,
            example: ExampleSentence(en: "I eat an apple.", zh: "我吃苹果。")
        )
        XCTAssertTrue(
            BattleQuestionTypePolicy.anyWordSupportsQuestionTypes([cloze], typeIds: [QuestionKind.sentenceCloze.rawValue]),
        )
    }
}
