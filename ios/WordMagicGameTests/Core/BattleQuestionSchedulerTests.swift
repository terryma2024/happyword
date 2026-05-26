import XCTest
@testable import WordMagicGame

final class BattleQuestionSchedulerTests: XCTestCase {
    func testStagesAdvanceStrictlyEasyToHardAfterWordCoverage() {
        let scheduler = BattleQuestionScheduler(
            planWordIds: ["w-a", "w-b", "w-c"],
            enabledTypes: [
                QuestionKind.choice.rawValue,
                QuestionKind.fillLetter.rawValue,
                QuestionKind.fillLetterMedium.rawValue,
            ],
            rng: { 0 },
        )
        let canServe: WordKindSupportFn = { _, _ in true }

        for expectedWord in ["w-a", "w-b", "w-c"] {
            let pick = scheduler.pickNext(monsterIndex: 1, lastWordId: nil, canServe: canServe)
            XCTAssertEqual(pick.kind, QuestionKind.choice.rawValue)
            XCTAssertEqual(pick.preferredWordId, expectedWord)
            scheduler.markServed(wordId: pick.preferredWordId, kind: pick.kind, canServe: canServe)
        }

        for expectedWord in ["w-a", "w-b", "w-c"] {
            let pick = scheduler.pickNext(monsterIndex: 1, lastWordId: nil, canServe: canServe)
            XCTAssertEqual(pick.kind, QuestionKind.fillLetter.rawValue)
            XCTAssertEqual(pick.preferredWordId, expectedWord)
            scheduler.markServed(wordId: pick.preferredWordId, kind: pick.kind, canServe: canServe)
        }

        XCTAssertEqual(
            scheduler.pickNext(monsterIndex: 1, lastWordId: nil, canServe: canServe).kind,
            QuestionKind.fillLetterMedium.rawValue
        )
    }

    func testSchedulerSkipsUnsupportedStages() {
        let scheduler = BattleQuestionScheduler(
            planWordIds: ["w-a", "w-b"],
            enabledTypes: [QuestionKind.choice.rawValue, QuestionKind.spell.rawValue],
            canServe: { _, kind in kind == QuestionKind.spell.rawValue },
            rng: { 0 },
        )

        let pick = scheduler.pickNext(monsterIndex: 1, lastWordId: nil)

        XCTAssertEqual(pick.kind, QuestionKind.spell.rawValue)
    }

    func testCurrentMonsterKeepsCatalogWhileStageAdvancesBeforeDeath() {
        let scheduler = BattleQuestionScheduler(
            planWordIds: ["w-a"],
            enabledTypes: [QuestionKind.choice.rawValue, QuestionKind.fillLetterMedium.rawValue],
            rng: { 0 },
        )
        let canServe: WordKindSupportFn = { _, _ in true }
        let firstCatalog = scheduler.catalogIndexForMonster(monsterIndex: 1)

        let firstPick = scheduler.pickNext(monsterIndex: 1, lastWordId: nil, canServe: canServe)
        scheduler.markServed(wordId: firstPick.preferredWordId, kind: firstPick.kind, canServe: canServe)
        let secondPick = scheduler.pickNext(monsterIndex: 1, lastWordId: nil, canServe: canServe)

        XCTAssertEqual(firstPick.kind, QuestionKind.choice.rawValue)
        XCTAssertEqual(secondPick.kind, QuestionKind.fillLetterMedium.rawValue)
        XCTAssertEqual(MonsterCodex.entry(catalogIndex1Based: firstCatalog).level, .beginner)
        XCTAssertEqual(scheduler.catalogIndexForMonster(monsterIndex: 1), firstCatalog)
    }

    func testNewMonsterUsesActiveStageLevelPool() {
        let scheduler = BattleQuestionScheduler(
            planWordIds: ["w-a"],
            enabledTypes: [QuestionKind.choice.rawValue, QuestionKind.fillLetterMedium.rawValue],
            rng: { 0 },
        )
        let canServe: WordKindSupportFn = { _, _ in true }
        let pick = scheduler.pickNext(monsterIndex: 1, lastWordId: nil, canServe: canServe)
        scheduler.markServed(wordId: pick.preferredWordId, kind: pick.kind, canServe: canServe)

        let nextCatalog = scheduler.catalogIndexForMonster(monsterIndex: 2)

        XCTAssertEqual(scheduler.activeKindForTest(), QuestionKind.fillLetterMedium.rawValue)
        XCTAssertEqual(MonsterCodex.entry(catalogIndex1Based: nextCatalog).level, .advanced)
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
