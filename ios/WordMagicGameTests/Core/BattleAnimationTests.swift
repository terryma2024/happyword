@testable import WordMagicGame
import XCTest

final class BattleAnimationTests: XCTestCase {
    func testCorrectAnswerUsesForwardNormalHitAnimation() {
        let event = BattleAnimationEvent(outcome: AnswerOutcome(correct: true, damage: 1), word: "apple")

        XCTAssertEqual(event.projectileDirection, .forward)
        XCTAssertEqual(event.projectileIntensity, 1)
        XCTAssertEqual(event.projectileLabel, "apple")
        XCTAssertEqual(event.playerMotion, .nudge)
        XCTAssertEqual(event.monsterMotion, .hurt)
        XCTAssertEqual(event.feedbackText, "Correct!")
        XCTAssertFalse(event.showsCritOverlay)
    }

    func testWrongAnswerUsesBackwardCounterAttackAnimation() {
        let event = BattleAnimationEvent(outcome: AnswerOutcome(correct: false, damage: 1), word: "apple")

        XCTAssertEqual(event.projectileDirection, .backward)
        XCTAssertEqual(event.projectileIntensity, 1)
        XCTAssertEqual(event.projectileLabel, "apple")
        XCTAssertEqual(event.playerMotion, .hurt)
        XCTAssertEqual(event.monsterMotion, .idle)
        XCTAssertEqual(event.feedbackText, "Correct answer: apple")
        XCTAssertFalse(event.showsCritOverlay)
    }

    func testComboBurstUsesCritSpectacleAnimation() {
        let event = BattleAnimationEvent(
            outcome: AnswerOutcome(correct: true, damage: 2, comboTriggered: true),
            word: "apple"
        )

        XCTAssertEqual(event.projectileDirection, .forward)
        XCTAssertEqual(event.projectileIntensity, 2)
        XCTAssertEqual(event.playerMotion, .cast)
        XCTAssertEqual(event.monsterMotion, .zoom)
        XCTAssertEqual(event.feedbackText, "Combo 3! Magic Burst x2")
        XCTAssertTrue(event.showsCritOverlay)
        XCTAssertEqual(event.damageLabel, "-2!")
    }

    func testMonsterDefeatKeepsHitAnimationAndAddsDefeatCue() {
        let event = BattleAnimationEvent(
            outcome: AnswerOutcome(correct: true, damage: 1, monsterDefeated: true),
            word: "apple"
        )

        XCTAssertEqual(event.projectileDirection, .forward)
        XCTAssertEqual(event.monsterMotion, .hurt)
        XCTAssertTrue(event.playsMonsterDefeatCue)
    }
}
