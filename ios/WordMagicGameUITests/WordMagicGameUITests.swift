import XCTest

final class WordMagicGameUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunchShowsScaffold() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["MagicWord"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["iOS replica scaffold"].exists)
    }
}
