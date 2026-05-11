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
}
