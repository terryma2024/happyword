import XCTest
@testable import WordMagicGame

final class DamageFloaterLabelTests: XCTestCase {
    func testPickFloaterStyleForOneIsBright() {
        let style = pickFloaterStyle(amount: 1)
        XCTAssertEqual(style.text, "-1")
        XCTAssertEqual(style.fontSize, 18)
        XCTAssertTrue(style.hasStroke)
    }

    func testPickFloaterStyleForTwoIsDeep() {
        let style = pickFloaterStyle(amount: 2)
        XCTAssertEqual(style.text, "-2")
        XCTAssertEqual(style.fontSize, 20)
        XCTAssertFalse(style.hasStroke)
        XCTAssertEqual(style.shadowRadius, 2)
    }
}
