@testable import WordMagicGame
import XCTest

final class BattleEngineTests: XCTestCase {
    func testMapsMonsterLevelsToCoinValues() {
        XCTAssertEqual(BattleRewardCalc.coinValue(for: .beginner), 1)
        XCTAssertEqual(BattleRewardCalc.coinValue(for: .intermediate), 2)
        XCTAssertEqual(BattleRewardCalc.coinValue(for: .advanced), 3)
        XCTAssertEqual(BattleRewardCalc.coinValue(for: .super), 4)
    }

    func testUsesMonsterLevelScoreAsFinalAward() {
        XCTAssertEqual(BattleRewardCalc.coinAward(monsterLevelScore: 9), 9)
        XCTAssertEqual(BattleRewardCalc.coinAward(monsterLevelScore: 0), 0)
    }

    func testRetiredBonusMultiplierNeverAddsCoins() {
        XCTAssertEqual(BattleRewardCalc.retiredBonusCoinDelta(stars: 3, bonusKillCount: 1, won: true), 0)
        XCTAssertEqual(BattleRewardCalc.retiredBonusCoinDelta(stars: 2, bonusKillCount: 3, won: false), 0)
    }

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
        XCTAssertEqual(result.monsterLevelScore, 3)
        XCTAssertEqual(result.coinsEarned, 3)
    }

    func testAdvancedAndSuperMonstersCanDealHeavyAttackDamage() throws {
        let engine = BattleEngine(
            questionSource: FixedQuestionSource(repeating: [
                Question.choice(wordId: "apple", promptZh: "苹果", answer: "apple", options: ["apple", "pear", "banana"]),
                Question.choice(wordId: "pear", promptZh: "梨", answer: "pear", options: ["pear", "apple", "banana"]),
                Question.choice(wordId: "banana", promptZh: "香蕉", answer: "banana", options: ["banana", "apple", "pear"]),
            ]),
            config: GameConfig(playerMaxHp: 5, monsterMaxHp: 1, monstersTotal: 10, startingSeconds: 300),
            randomDouble: { 0.25 }
        )

        engine.start()
        for _ in 1...7 {
            let answer = try XCTUnwrap(engine.state.currentQuestion?.answer)
            _ = try engine.submitAnswer(answer)
        }
        let current = try XCTUnwrap(engine.state.currentQuestion)
        let wrongAnswer = try XCTUnwrap(current.options.first { $0 != current.answer })
        let outcome = try engine.submitAnswer(wrongAnswer)

        XCTAssertFalse(outcome.correct)
        XCTAssertEqual(outcome.damage, 2)
        XCTAssertEqual(engine.state.playerHp, 3)
    }

    func testBonusMonsterKillsDoNotIncreaseWonCoinReward() throws {
        let engine = BattleEngine(
            questionSource: FixedQuestionSource(repeating: [
                Question.choice(wordId: "apple", promptZh: "苹果", answer: "apple", options: ["apple", "pear", "banana"]),
                Question.choice(wordId: "pear", promptZh: "梨", answer: "pear", options: ["pear", "apple", "banana"]),
            ]),
            config: GameConfig(playerMaxHp: 5, monsterMaxHp: 1, monstersTotal: 8, startingSeconds: 300),
            randomDouble: { 0.10 }
        )

        engine.start()
        while engine.state.status == .playing {
            let answer = try XCTUnwrap(engine.state.currentQuestion?.answer)
            _ = try engine.submitAnswer(answer)
        }

        let result = try engine.buildSessionResult()
        XCTAssertEqual(result.status, .won)
        XCTAssertEqual(result.stars, 3)
        XCTAssertEqual(result.bonusKillCount, 1)
        XCTAssertEqual(result.monsterLevelScore, 16)
        XCTAssertEqual(result.coinsEarned, 16)
    }

    func testRecordsMonsterLevelScoreAtKillTime() throws {
        let engine = BattleEngine(
            questionSource: FixedQuestionSource(repeating: [
                Question.choice(wordId: "apple", promptZh: "苹果", answer: "apple", options: ["apple", "pear", "banana"]),
                Question.choice(wordId: "pear", promptZh: "梨", answer: "pear", options: ["pear", "apple", "banana"]),
                Question.choice(wordId: "banana", promptZh: "香蕉", answer: "banana", options: ["banana", "apple", "pear"]),
                Question.choice(wordId: "door", promptZh: "门", answer: "door", options: ["door", "bed", "desk"]),
            ]),
            config: GameConfig(playerMaxHp: 5, monsterMaxHp: 1, monstersTotal: 4, startingSeconds: 300),
            monsterCatalogIndex: { battleIndex in
                switch battleIndex {
                case 1: 1
                case 2: 2
                case 3: 8
                default: 10
                }
            }
        )

        engine.start()
        while engine.state.status == .playing {
            let answer = try XCTUnwrap(engine.state.currentQuestion?.answer)
            _ = try engine.submitAnswer(answer)
        }

        let result = try engine.buildSessionResult()
        XCTAssertEqual(result.monsterLevelScore, 10)
        XCTAssertEqual(result.coinsEarned, 10)
    }

    func testPartialLossKeepsOnlyDefeatedMonsterLevelScore() throws {
        let engine = BattleEngine(
            questionSource: FixedQuestionSource(repeating: [
                Question.choice(wordId: "apple", promptZh: "苹果", answer: "apple", options: ["apple", "pear", "banana"]),
                Question.choice(wordId: "pear", promptZh: "梨", answer: "pear", options: ["pear", "apple", "banana"]),
            ]),
            config: GameConfig(playerMaxHp: 1, monsterMaxHp: 1, monstersTotal: 2, startingSeconds: 300),
            monsterCatalogIndex: { _ in 8 }
        )

        engine.start()
        _ = try engine.submitAnswer("apple")
        let current = try XCTUnwrap(engine.state.currentQuestion)
        let wrongAnswer = try XCTUnwrap(current.options.first { $0 != current.answer })
        _ = try engine.submitAnswer(wrongAnswer)

        let result = try engine.buildSessionResult()
        XCTAssertEqual(result.status, .lost)
        XCTAssertEqual(result.stars, 1)
        XCTAssertEqual(result.monsterLevelScore, 3)
        XCTAssertEqual(result.coinsEarned, 3)
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
