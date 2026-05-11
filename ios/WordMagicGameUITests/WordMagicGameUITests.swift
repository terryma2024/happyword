import XCTest

final class WordMagicGameUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testHomeBattleResultDeterministicFlow() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestResetState"]
        app.launch()

        assertLandscape(app)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "小小魔法师")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["开始冒险"].exists)

        app.buttons["开始冒险"].tap()
        assertLandscape(app)
        XCTAssertTrue(app.staticTexts["苹果"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["apple"].exists)

        let answers = ["apple", "pear", "banana", "door", "desk"]
        for index in 0..<15 {
            let answer = answers[index % answers.count]
            XCTAssertTrue(app.buttons[answer].waitForExistence(timeout: 2))
            app.buttons[answer].tap()
        }

        XCTAssertTrue(app.staticTexts["胜利"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["★★★"].exists)
        app.buttons["返回主页"].tap()
        XCTAssertTrue(app.staticTexts["金币 3"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testBattleScreenUsesEnglishLabelsAndLiveCountdown() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestResetState", "-UITestRouteBattle"]
        app.launch()

        assertLandscape(app)
        XCTAssertTrue(app.staticTexts["Combo: 0"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Battle"].exists)
        XCTAssertTrue(app.staticTexts["Question"].exists)
        XCTAssertTrue(app.staticTexts["苹果"].exists)
        XCTAssertTrue(app.buttons["apple"].exists)
        XCTAssertTrue(app.buttons["Pronounce"].exists)
        XCTAssertTrue(app.staticTexts["Choose the right spell"].exists)
        XCTAssertTrue(app.staticTexts["Magician"].exists)
        XCTAssertTrue(app.staticTexts["Player"].exists)
        XCTAssertTrue(app.staticTexts["Slime"].exists)
        XCTAssertTrue(app.staticTexts["Monster 1 / 5"].exists)
        let countdown = app.staticTexts
            .containing(NSPredicate(format: "label BEGINSWITH %@", "Countdown "))
            .firstMatch
        XCTAssertTrue(countdown.waitForExistence(timeout: 5))

        let initialCountdown = countdown.label
        let deadline = Date().addingTimeInterval(4)
        while countdown.label == initialCountdown && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertNotEqual(countdown.label, initialCountdown)
    }

    @MainActor
    func testMonsterCodexFlowFromHome() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestResetState"]
        app.launch()

        assertLandscape(app)
        XCTAssertTrue(app.buttons["图鉴"].waitForExistence(timeout: 5))
        app.buttons["图鉴"].tap()

        assertLandscape(app)
        XCTAssertTrue(app.staticTexts["怪物图鉴"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Slime"].exists)
        XCTAssertTrue(app.staticTexts["「普通怪物」"].exists)
        XCTAssertTrue(app.staticTexts["1 / 10"].exists)

        app.buttons["下一只"].tap()
        XCTAssertTrue(app.staticTexts["Zombie"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["2 / 10"].exists)

        for _ in 0..<8 {
            app.buttons["下一只"].tap()
        }
        XCTAssertTrue(app.staticTexts["Kraken"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["10 / 10"].exists)
        XCTAssertFalse(app.buttons["下一只"].isEnabled)

        app.buttons["上一只"].tap()
        XCTAssertTrue(app.staticTexts["Unicorn"].waitForExistence(timeout: 2))

        app.buttons["返回"].tap()
        XCTAssertTrue(app.buttons["开始冒险"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testPhase2PackManagerToggleAndPinAffectHome() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestResetState"]
        app.launch()

        XCTAssertTrue(app.buttons["设置"].waitForExistence(timeout: 5))
        app.buttons["设置"].tap()
        XCTAssertTrue(app.buttons["我的词包"].waitForExistence(timeout: 5))
        app.buttons["我的词包"].tap()

        XCTAssertTrue(app.staticTexts["我的词包"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["已激活 5 / 5"].exists)
        XCTAssertTrue(app.staticTexts["内置"].exists)
        XCTAssertTrue(app.staticTexts["Fruit Forest"].exists)

        app.buttons["固定 Fruit Forest"].tap()
        XCTAssertTrue(app.buttons["已固定 Fruit Forest"].waitForExistence(timeout: 2))
        app.switches["PackToggle_forest"].tap()
        XCTAssertTrue(app.staticTexts["已激活 4 / 5"].waitForExistence(timeout: 2))

        app.buttons["返回"].tap()
        XCTAssertTrue(app.staticTexts["游戏设置"].waitForExistence(timeout: 5))
        app.buttons["返回"].tap()
        XCTAssertTrue(app.staticTexts["School Castle"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Fruit Forest"].exists)
    }

    @MainActor
    func testPhase2WishlistRedemptionHistoryAndGiftBox() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestResetState", "-UITestSeedCoins", "-UITestSeedParentPin", "-UITestRouteWishlist"]
        app.launch()

        XCTAssertTrue(app.staticTexts["魔法愿望单"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["我的魔法币: 20 ✨"].exists)
        app.buttons["兑换 看 iPad 20 分钟"].tap()

        XCTAssertTrue(app.secureTextFields["家长 PIN"].waitForExistence(timeout: 5))
        app.secureTextFields["家长 PIN"].tap()
        app.secureTextFields["家长 PIN"].typeText("123456")
        app.buttons["确认兑换"].tap()

        XCTAssertTrue(app.staticTexts["愿望实现啦"].waitForExistence(timeout: 5))
        app.buttons["知道了"].tap()
        XCTAssertTrue(app.staticTexts["我的魔法币: 10 ✨"].waitForExistence(timeout: 5))

        app.buttons["兑换历史"].tap()
        XCTAssertTrue(app.staticTexts["兑换历史"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["看 iPad 20 分钟"].exists)
    }

    @MainActor
    func testPhase2TodayPlanRoutesToPackLearningReport() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestResetState", "-UITestRouteTodayPlan"]
        app.launch()

        XCTAssertTrue(app.staticTexts["今日学习计划"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["复习"].exists)
        XCTAssertTrue(app.staticTexts["学习中"].exists)
        XCTAssertTrue(app.staticTexts["新词"].exists)

        app.buttons["学习报告"].tap()
        XCTAssertTrue(app.staticTexts["学习报告"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["词包详情"].exists)
        XCTAssertTrue(app.staticTexts["Fruit Forest"].exists)
    }

    @MainActor
    func testHomeToolbarRoutesToLearningReport() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestResetState"]
        app.launch()

        assertLandscape(app)
        XCTAssertTrue(app.buttons["学习报告"].waitForExistence(timeout: 5))
        app.buttons["学习报告"].tap()

        assertLandscape(app)
        XCTAssertTrue(app.staticTexts["学习报告"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["词包详情"].exists)
    }

    @MainActor
    func testConfigPinParentAdminAndLessonReviewMockFlow() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestResetState"]
        app.launch()

        XCTAssertTrue(app.buttons["设置"].waitForExistence(timeout: 5))
        app.buttons["设置"].tap()
        XCTAssertTrue(app.staticTexts["游戏设置"].waitForExistence(timeout: 5))

        app.buttons["家长 PIN"].tap()
        XCTAssertTrue(app.secureTextFields["6 位数字"].waitForExistence(timeout: 5))
        app.secureTextFields["6 位数字"].tap()
        app.secureTextFields["6 位数字"].typeText("123456")
        app.secureTextFields["再次输入 PIN"].tap()
        app.secureTextFields["再次输入 PIN"].typeText("123456")
        app.buttons["保存 PIN"].tap()

        XCTAssertTrue(app.buttons["家长后台"].waitForExistence(timeout: 5))
        app.buttons["家长后台"].tap()
        XCTAssertTrue(app.secureTextFields["6 位数字"].waitForExistence(timeout: 5))
        app.secureTextFields["6 位数字"].tap()
        app.secureTextFields["6 位数字"].typeText("123456")
        app.buttons["打开"].tap()

        XCTAssertTrue(app.staticTexts["家长管理后台"].waitForExistence(timeout: 5))
        assertPortrait(app)
        XCTAssertTrue(app.staticTexts["本地模拟家长服务"].exists)
        app.buttons["刷新"].tap()
        XCTAssertTrue(app.staticTexts["待审核草稿"].waitForExistence(timeout: 5))

        app.buttons["从相册导入"].tap()
        XCTAssertTrue(app.staticTexts["课本识别审核"].waitForExistence(timeout: 5))
        app.switches.element(boundBy: 1).tap()
        app.buttons["审核通过"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "已发布词包")).firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor
    func testParentAdminDirectRouteIsPortrait() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestResetState", "-UITestRouteParentAdmin"]
        app.launch()

        XCTAssertTrue(app.staticTexts["家长管理后台"].waitForExistence(timeout: 5))
        assertPortrait(app)
    }

    @MainActor
    private func assertLandscape(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5), file: file, line: line)
        let deadline = Date().addingTimeInterval(5)
        while window.frame.width <= window.frame.height && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertGreaterThan(window.frame.width, window.frame.height, file: file, line: line)
    }

    @MainActor
    private func assertPortrait(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5), file: file, line: line)
        let deadline = Date().addingTimeInterval(5)
        while window.frame.height <= window.frame.width && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertGreaterThan(window.frame.height, window.frame.width, file: file, line: line)
    }
}
