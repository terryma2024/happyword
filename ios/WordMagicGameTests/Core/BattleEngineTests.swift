@testable import WordMagicGame
import XCTest

final class BattleEngineTests: XCTestCase {
    func testDefaultsMatchHarmonyBattleRules() {
        let config = GameConfig.default

        XCTAssertEqual(config.playerMaxHp, 10)
        XCTAssertEqual(config.monsterMaxHp, 3)
        XCTAssertEqual(config.monstersTotal, 5)
        XCTAssertEqual(config.startingSeconds, 300)
        XCTAssertTrue(config.autoSpeak)
    }

    func testCorrectWrongAndComboBurstTransitions() throws {
        let source = FixedQuestionSource(repeating: [
            Question.choice(wordId: "apple", promptZh: "苹果", answer: "apple", options: ["apple", "pear", "banana"]),
            Question.choice(wordId: "pear", promptZh: "梨", answer: "pear", options: ["pear", "apple", "banana"]),
            Question.choice(wordId: "banana", promptZh: "香蕉", answer: "banana", options: ["banana", "apple", "pear"]),
            Question.choice(wordId: "door", promptZh: "门", answer: "door", options: ["door", "bed", "desk"]),
        ])
        let engine = BattleEngine(
            questionSource: source,
            config: GameConfig(playerMaxHp: 5, monsterMaxHp: 3, monstersTotal: 2, startingSeconds: 300)
        )

        engine.start()
        XCTAssertEqual(engine.state.status, .playing)
        XCTAssertEqual(engine.state.currentQuestion?.wordId, "apple")

        let first = try engine.submitAnswer("apple")
        XCTAssertTrue(first.correct)
        XCTAssertEqual(first.damage, 1)
        XCTAssertEqual(engine.state.monsterHp, 2)
        XCTAssertEqual(engine.state.comboCount, 1)

        let wrong = try engine.submitAnswer("apple")
        XCTAssertFalse(wrong.correct)
        XCTAssertEqual(engine.state.playerHp, 4)
        XCTAssertEqual(engine.state.comboCount, 0)

        _ = try engine.submitAnswer("banana")
        let thirdCorrect = try engine.submitAnswer("door")
        let burst = try engine.submitAnswer("apple")

        XCTAssertTrue(thirdCorrect.monsterDefeated)
        XCTAssertTrue(burst.comboTriggered)
        XCTAssertEqual(burst.damage, 2)
        XCTAssertFalse(burst.monsterDefeated)
        XCTAssertEqual(engine.state.defeatedMonsters, 1)
        XCTAssertEqual(engine.state.monsterIndex, 2)
        XCTAssertEqual(engine.state.monsterHp, 1)
        XCTAssertEqual(engine.state.comboCount, 0)
        XCTAssertEqual(thirdCorrect.damage, 1)
    }

    func testBuildsWonSessionResultWithStarsAndLearnedWords() throws {
        let source = FixedQuestionSource(repeating: [
            Question.choice(wordId: "apple", promptZh: "苹果", answer: "apple", options: ["apple", "pear", "banana"]),
            Question.choice(wordId: "pear", promptZh: "梨", answer: "pear", options: ["pear", "apple", "banana"]),
            Question.choice(wordId: "banana", promptZh: "香蕉", answer: "banana", options: ["banana", "apple", "pear"]),
        ])
        let engine = BattleEngine(
            questionSource: source,
            config: GameConfig(playerMaxHp: 5, monsterMaxHp: 1, monstersTotal: 2, startingSeconds: 300)
        )

        engine.start()
        _ = try engine.submitAnswer("apple")
        let final = try engine.submitAnswer("pear")

        XCTAssertTrue(final.battleEnded)
        XCTAssertEqual(final.endStatus, .won)

        let result = try engine.buildSessionResult()
        XCTAssertEqual(result.status, .won)
        XCTAssertEqual(result.stars, 3)
        XCTAssertEqual(result.defeatedMonsters, 2)
        XCTAssertEqual(result.learnedWordCount, 2)
        XCTAssertEqual(result.correctRate, 1.0)
    }

    func testTimerLossEndsBattleOnce() throws {
        let engine = BattleEngine(
            questionSource: FixedQuestionSource.single(
                Question.choice(wordId: "apple", promptZh: "苹果", answer: "apple", options: ["apple", "pear", "banana"])
            ),
            config: GameConfig(playerMaxHp: 5, monsterMaxHp: 3, monstersTotal: 5, startingSeconds: 3)
        )

        engine.start()
        let outcome = engine.tick(deltaSeconds: 3)

        XCTAssertTrue(outcome.battleEnded)
        XCTAssertEqual(outcome.endStatus, .lost)
        XCTAssertEqual(engine.state.remainingSeconds, 0)
        XCTAssertFalse(engine.tick(deltaSeconds: 1).battleEnded)
    }

    func testFillLetterMediumFirstStepAdvancesInPlaceAndRevealsLetter() throws {
        let medium = Question(
            promptZh: "苹果",
            answer: "apple",
            options: [],
            wordId: "fruit-apple",
            kind: .fillLetterMedium,
            letterTemplateBase: "a _ p _ e",
            missingIndices: [1, 3],
            letterOptionsSteps: [["p", "b", "c"], ["l", "r", "s"]],
            letterAnswers: ["p", "l"]
        )
        let next = Question.choice(wordId: "fruit-pear", promptZh: "梨", answer: "pear", options: ["pear", "apple", "banana"])
        let engine = BattleEngine(questionSource: FixedQuestionSource(repeating: [medium, next]))

        engine.start()
        let outcome = try engine.submitAnswer("p")

        XCTAssertTrue(outcome.correct)
        XCTAssertTrue(outcome.advancedStep)
        XCTAssertEqual(outcome.damage, 0)
        XCTAssertEqual(engine.state.monsterHp, engine.state.monsterMaxHp)
        XCTAssertEqual(engine.state.comboCount, 0)
        XCTAssertEqual(engine.state.totalAnswers, 0)
        XCTAssertEqual(engine.state.currentQuestion?.wordId, "fruit-apple")
        XCTAssertEqual(engine.state.currentQuestion?.currentStep, 1)
        XCTAssertEqual(engine.state.currentQuestion?.letterTemplateBase, "a p p _ e")
    }
}
