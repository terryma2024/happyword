import XCTest

/// Diagnostic helper: starts a battle and captures full-screen screenshots so
/// the Cocos scene (rendered in its own UIWindow) can be inspected off-device.
final class CocosBattleScreenshotUITests: XCTestCase {
    @MainActor
    func testCaptureBattleScreenshot() throws {
        let app = XCUIApplication()
        app.launch()

        // The button's own identifier is shadowed by the AdventureCard
        // container; match by visible label instead.
        let start = app.buttons["开始今日冒险"]
        XCTAssertTrue(start.waitForExistence(timeout: 10), "home start button missing")
        start.tap()

        // First boot takes a couple of seconds; capture early and settled frames.
        sleep(3)
        attachScreenshot(named: "battle-3s")
        sleep(4)
        attachScreenshot(named: "battle-7s")
    }

    @MainActor
    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
