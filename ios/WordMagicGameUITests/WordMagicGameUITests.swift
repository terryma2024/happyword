import XCTest

final class WordMagicGameUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testHomeBattleResultDeterministicFlow() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestResetState", "-UITestExposeCorrectAnswer"]
        app.launch()

        assertLandscape(app)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "小小魔法师")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["开始冒险"].exists)

        app.buttons["开始冒险"].tap()
        assertLandscape(app)
        XCTAssertTrue(app.buttons["BattleCorrectOption"].waitForExistence(timeout: 5))

        tapCorrectBattleOptionsUntilVictory(in: app)

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
        let answer = currentFruitAnswer(in: app, timeout: 5)
        XCTAssertNotNil(answer)
        XCTAssertTrue(app.buttons[answer ?? ""].exists)
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
        XCTAssertTrue(app.staticTexts["1 / 100"].exists)

        app.buttons["下一只"].tap()
        XCTAssertTrue(app.staticTexts["Zombie"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["2 / 100"].exists)

        for _ in 0..<9 {
            app.buttons["下一只"].tap()
        }
        XCTAssertTrue(app.staticTexts["Jellyfish"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["11 / 100"].exists)

        for _ in 0..<89 {
            app.buttons["下一只"].tap()
        }
        XCTAssertTrue(app.staticTexts["Music Box Fairy"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["100 / 100"].exists)
        XCTAssertFalse(app.buttons["下一只"].isEnabled)

        app.buttons["上一只"].tap()
        XCTAssertTrue(app.staticTexts["Kite Serpent"].waitForExistence(timeout: 2))

        app.buttons["返回"].tap()
        XCTAssertTrue(app.buttons["开始冒险"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testPackManagerToggleAndPinAffectHome() {
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
        app.switches["PackToggle_fruit-forest"].tap()
        XCTAssertTrue(app.staticTexts["已激活 4 / 5"].waitForExistence(timeout: 2))

        app.buttons["返回"].tap()
        XCTAssertTrue(app.staticTexts["游戏设置"].waitForExistence(timeout: 5))
        app.buttons["返回"].tap()
        XCTAssertTrue(app.staticTexts["School Castle"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Fruit Forest"].exists)
    }

    @MainActor
    func testWishlistRedemptionHistoryAndGiftBox() {
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
    func testTodayPlanRoutesToPackLearningReport() {
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
    func testShortCodeBindingAndUnbindFlow() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestResetState", "-UITestMockBinding", "-UITestSeedParentPin", "-UITestRouteConfig"]
        app.launch()

        XCTAssertTrue(app.staticTexts["游戏设置"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["绑定家长账号"].exists)
        app.buttons["绑定家长账号"].tap()

        XCTAssertTrue(app.staticTexts["绑定家长账号"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["6 位短码"].exists)
        app.textFields["6 位短码"].tap()
        app.textFields["6 位短码"].typeText("123456")
        app.buttons["绑定"].tap()

        XCTAssertTrue(app.staticTexts["绑定成功：小明测试46373"].waitForExistence(timeout: 5))
        app.buttons["完成"].tap()
        XCTAssertTrue(app.buttons["账号信息"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["已绑定 小明测试46373"].exists)

        app.buttons["账号信息"].tap()
        XCTAssertTrue(app.staticTexts["绑定设备"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["小明测试46373"].exists)
        app.secureTextFields["家长 PIN"].tap()
        app.secureTextFields["家长 PIN"].typeText("123456")
        app.buttons["解除绑定"].tap()

        XCTAssertTrue(app.buttons["绑定家长账号"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testBoundDeviceCanSyncGlobalAndFamilyPacks() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestResetState", "-UITestSeedBoundDevice", "-UITestRoutePackManager"]
        app.launch()

        XCTAssertTrue(app.staticTexts["我的词包"].waitForExistence(timeout: 5))
        app.buttons["同步词包"].tap()
        XCTAssertTrue(app.staticTexts["已同步官方/家庭词包"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["官方"].exists)
        XCTAssertTrue(app.staticTexts["Space Station"].exists)
        XCTAssertTrue(app.staticTexts["家庭"].exists)
        XCTAssertTrue(app.staticTexts["Family Snacks"].exists)
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

    @MainActor
    private func tapCurrentCorrectBattleOption(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons["BattleCorrectOption"]
        XCTAssertTrue(button.waitForExistence(timeout: 2), file: file, line: line)
        XCTAssertTrue(button.isHittable, file: file, line: line)
        button.tap()
    }

    @MainActor
    private func tapCorrectBattleOptionsUntilVictory(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let victory = app.staticTexts["胜利"]
        for _ in 0..<40 {
            if victory.exists {
                return
            }
            let button = app.buttons["BattleCorrectOption"]
            let deadline = Date().addingTimeInterval(2)
            while (!button.exists || !button.isHittable) && !victory.exists && Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            }
            if victory.exists {
                return
            }
            tapCurrentCorrectBattleOption(in: app, file: file, line: line)
        }
    }

    @MainActor
    private func currentFruitAnswer(in app: XCUIApplication, timeout: TimeInterval) -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for (prompt, answer) in Self.fruitAnswers where app.staticTexts[prompt].exists && app.buttons[answer].exists && app.buttons[answer].isHittable {
                return answer
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return nil
    }

    private static let fruitAnswers = [
        "苹果": "apple",
        "香蕉": "banana",
        "橙子": "orange",
        "葡萄": "grape",
        "梨": "pear",
        "桃子": "peach",
        "柠檬": "lemon",
        "芒果": "mango",
        "瓜": "melon",
        "樱桃": "cherry",
    ]
}
