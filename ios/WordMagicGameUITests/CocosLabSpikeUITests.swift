import XCTest

/// Phase 0 spike automation: boots the embedded Cocos runtime via the DevMenu
/// CocosLab entry and waits for the JSB ping/pong toast. Device-only — the
/// simulator stub shows the "not linked" toast instead.
final class CocosLabSpikeUITests: XCTestCase {
    @MainActor
    func testCocosLabPingPong() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestRouteDevMenu"]
        app.launch()

        let button = app.buttons["DevMenuCocosLabButton"]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "CocosLab button missing")
        button.tap()

        let toast = app.staticTexts["AppToast"]
        XCTAssertTrue(toast.waitForExistence(timeout: 30), "no toast after CocosLab tap")
        if toast.label.contains("not linked") {
            throw XCTSkip("Cocos runtime is device-only; skipping on simulator")
        }
        XCTAssertTrue(
            toast.label.contains("Cocos pong OK"),
            "unexpected toast: \(toast.label)"
        )
    }
}
