import XCTest
@testable import WordMagicGame

final class BattleQuestionSchedulerTests: XCTestCase {
    func testSingleTypeAlwaysReturnsThatKind() {
        let scheduler = BattleQuestionScheduler(
            planWordIds: ["w-a", "w-b"],
            enabledTypes: [QuestionKind.spell.rawValue],
            rng: { 0 },
        )
        XCTAssertEqual(scheduler.scheduleMode(), .singleType)
        for _ in 0 ..< 6 {
            let pick = scheduler.pickNext(lastWordId: nil) { _, _ in true }
            XCTAssertEqual(pick.kind, QuestionKind.spell.rawValue)
        }
    }

    func testIntroOnlyNeverReturnsChallengeKind() {
        let scheduler = BattleQuestionScheduler(
            planWordIds: ["w-a", "w-b", "w-c"],
            enabledTypes: [QuestionKind.choice.rawValue, QuestionKind.fillLetter.rawValue],
            rng: { 0.25 },
        )
        XCTAssertEqual(scheduler.scheduleMode(), .introOnly)
        let canServe: WordKindSupportFn = { _, _ in true }
        for index in 0 ..< 12 {
            let kind = scheduler.pickNext(lastWordId: nil, canServe: canServe).kind
            XCTAssertFalse(kind == QuestionKind.fillLetterMedium.rawValue || kind == QuestionKind.spell.rawValue)
            scheduler.markServed(wordId: "w-\(index % 3)", kind: kind, canServe: canServe)
        }
    }

    func testChallengeRollsAcrossAllEnabledChallengeTypes() {
        var seen = Set<String>()
        for seed in 0 ..< 80 {
            let scheduler = BattleQuestionScheduler(
                planWordIds: ["w-a"],
                enabledTypes: [
                    QuestionKind.fillLetterMedium.rawValue,
                    QuestionKind.spell.rawValue,
                    QuestionKind.sentenceCloze.rawValue,
                ],
                rng: { Double(seed % 17) / 17.0 },
            )
            seen.insert(scheduler.pickNext(lastWordId: nil) { _, _ in true }.kind)
        }

        XCTAssertTrue(seen.contains(QuestionKind.fillLetterMedium.rawValue))
        XCTAssertTrue(seen.contains(QuestionKind.spell.rawValue))
        XCTAssertTrue(seen.contains(QuestionKind.sentenceCloze.rawValue))
    }

    func testChallengeRollNeverReturnsSentenceClozeWhenDisabled() {
        let scheduler = BattleQuestionScheduler(
            planWordIds: ["w-a"],
            enabledTypes: [QuestionKind.fillLetterMedium.rawValue, QuestionKind.spell.rawValue],
            rng: { 0.99 },
        )

        for _ in 0 ..< 10 {
            XCTAssertNotEqual(
                scheduler.pickNext(lastWordId: nil) { _, _ in true }.kind,
                QuestionKind.sentenceCloze.rawValue
            )
        }
    }

    func testSpellWrongTapPenaltyEndsBattleAtOneHp() {
        var config = GameConfig()
        config.playerMaxHp = 1
        let engine = BattleEngine(questionSource: FixedQuestionSource.single(Self.spellQuestion), config: config)
        engine.start()
        XCTAssertEqual(engine.applySpellLetterPenalty(), 1)
        XCTAssertEqual(engine.state.status, .lost)
    }

    private static var spellQuestion: Question {
        var question = Question(
            promptZh: "猫",
            answer: "cat",
            options: ["cat"],
            wordId: "w-cat",
            kind: .spell,
        )
        question.spellLetters = ["c", "a", "t"]
        question.spellRevealedMask = [true, false, false]
        question.spellPool = ["a", "t", "x"]
        return question
    }
}
