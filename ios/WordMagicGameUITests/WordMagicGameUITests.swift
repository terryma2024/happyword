import XCTest

final class WordMagicGameUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testHomeBattleResultDeterministicFlow() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestResetState", "-UITestExposeCorrectAnswer", "-UITestQuestionTypesChoiceOnly", "-UITestQuickBattle"]
        app.launch()

        assertLandscape(app)
        XCTAssertTrue(app.staticTexts["Small Magician Word Adventure"].waitForExistence(timeout: 5))
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
    func testHomeHidesChildAccountBeforeBinding() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestResetState"]
        app.launch()

        assertLandscape(app)
        XCTAssertTrue(app.staticTexts["Small Magician Word Adventure"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["今天的冒险包含 5 关卡，含拼写、复习与首领关"].exists)
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "小明测试")).firstMatch.exists)
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
        XCTAssertTrue(app.staticTexts["已激活 5 / 10"].exists)
        XCTAssertTrue(app.staticTexts["内置"].exists)
        XCTAssertTrue(app.staticTexts["Fruit Forest"].exists)

        app.buttons["PackPin_fruit-forest"].tap()
        XCTAssertTrue(app.staticTexts["PackManagerStatus"].waitForExistence(timeout: 2))
        XCTAssertEqual(app.staticTexts["PackManagerStatus"].label, "已固定 Fruit Forest")
        app.switches["PackToggle_fruit-forest"].tap()
        XCTAssertTrue(app.staticTexts["已激活 4 / 10"].waitForExistence(timeout: 2))

        app.buttons["返回"].tap()
        XCTAssertTrue(app.staticTexts["ConfigTitle"].waitForExistence(timeout: 5))
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

        XCTAssertTrue(app.otherElements["WishlistGiftBoxModal"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["知道了"].exists)
        XCTAssertTrue(app.otherElements["WishlistGiftBoxModal"].waitForNonExistence(timeout: 4))
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
    func testHomePlanButtonRoutesToTodayPlan() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestResetState"]
        app.launch()

        assertLandscape(app)
        XCTAssertTrue(app.buttons["今日学习计划"].waitForExistence(timeout: 5))
        app.buttons["今日学习计划"].tap()

        assertPortrait(app)
        XCTAssertTrue(app.staticTexts["今日学习计划"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["复习"].exists)
        XCTAssertTrue(app.staticTexts["学习中"].exists)
        XCTAssertTrue(app.staticTexts["新词"].exists)
    }

    @MainActor
    func testReviewToolbarUsesRecentWrongWordAndShowsToastWhenEmpty() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestResetState", "-UITestExposeCorrectAnswer"]
        app.launch()

        assertLandscape(app)
        XCTAssertTrue(app.buttons["复习"].waitForExistence(timeout: 5))
        app.buttons["复习"].tap()
        XCTAssertTrue(app.staticTexts["先答错几题再来复习吧"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["开始冒险"].exists)

        app.buttons["开始冒险"].tap()
        XCTAssertTrue(app.buttons["BattleCorrectOption"].waitForExistence(timeout: 5))
        let seededWrongPrompt = try XCTUnwrap(currentFruitPrompt(in: app, timeout: 5))
        tapFirstIncorrectFruitOption(in: app)
        XCTAssertTrue(waitForBattleFeedback(in: app)?.hasPrefix("Correct answer:") == true)
        waitForBattleFeedbackToClear(in: app)

        app.buttons["Escape"].tap()
        XCTAssertTrue(app.staticTexts["继续练习"].waitForExistence(timeout: 5))
        app.buttons["返回主页"].tap()
        XCTAssertTrue(app.buttons["开始冒险"].waitForExistence(timeout: 5))

        app.buttons["复习"].tap()
        XCTAssertTrue(app.staticTexts["Battle"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Monster 1 / 3"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[seededWrongPrompt].waitForExistence(timeout: 5))
    }

    @MainActor
    func testHomeHidesChildProfileBadgeWithoutDeviceBinding() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestResetState", "-UITestClearBinding"]
        app.launch()

        assertLandscape(app)
        XCTAssertTrue(app.buttons["开始冒险"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["HomeChildProfileButton"].exists)
    }

    @MainActor
    func testHomeChildProfileBadgeOpensParentAccountAndEditRenamesChild() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestResetState", "-UITestSeedBoundDevice"]
        app.launch()

        assertLandscape(app)
        let profileButton = app.descendants(matching: .any)["HomeChildProfileButton"]
        XCTAssertTrue(profileButton.waitForExistence(timeout: 5))
        XCTAssertTrue(profileButton.label.contains("小明测试46373"))
        profileButton.tap()

        XCTAssertTrue(app.staticTexts["学习档案"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Family ID"].exists)
        XCTAssertTrue(app.staticTexts["学习档案"].exists)
        app.buttons["✏️ 编辑"].tap()

        XCTAssertTrue(app.staticTexts["学习档案"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["学习者名字"].waitForExistence(timeout: 5))
        app.textFields["学习者名字"].tap()
        app.textFields["学习者名字"].clearAndTypeText("小星星")
        app.buttons["保存名字"].tap()

        XCTAssertTrue(app.buttons["返回"].waitForExistence(timeout: 5))
        app.buttons["返回"].tap()
        XCTAssertTrue(app.staticTexts["ConfigTitle"].waitForExistence(timeout: 5))
        app.buttons["返回"].tap()
        XCTAssertTrue(profileButton.waitForExistence(timeout: 5))
        XCTAssertTrue(profileButton.label.contains("小星星"))
    }

    @MainActor
    func testPortraitAccountPagesUseExpectedBackButtonPlacement() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestResetState", "-UITestSeedBoundDevice", "-UITestRouteRedemptionHistory"]
        app.launch()

        assertPortrait(app)
        assertTopLeftBackButton(app.buttons["返回"], in: app)

        app.terminate()
        app.launchArguments = ["-UITestResetState", "-UITestSeedBoundDevice", "-UITestRouteBoundDeviceInfo"]
        app.launch()

        assertPortrait(app)
        assertTopLeftBackButton(app.buttons["返回"], in: app)
    }

    @MainActor
    func testBoundDeviceInfoMatchesHarmonyParentAccountLayout() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestResetState", "-UITestSeedBoundDevice", "-UITestRouteBoundDeviceInfo"]
        app.launch()

        assertPortrait(app)
        let title = app.staticTexts["学习档案"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(title.frame.minY, app.windows.element(boundBy: 0).frame.minY + 20)
        XCTAssertTrue(app.staticTexts["学习档案"].exists)
        XCTAssertTrue(app.staticTexts["🦁 小明测试46373"].exists)
        XCTAssertTrue(app.buttons["✏️ 编辑"].exists)
        XCTAssertTrue(app.staticTexts["Family ID"].exists)
        XCTAssertTrue(app.staticTexts["family-demo"].exists)
        XCTAssertTrue(app.staticTexts["Binding ID"].exists)
        XCTAssertTrue(app.staticTexts["binding-demo"].exists)
        XCTAssertTrue(app.staticTexts["Device ID 末四位"].exists)
        XCTAssertTrue(app.staticTexts["Device ID 来源"].exists)
        XCTAssertTrue(app.staticTexts["Keychain (持久)"].exists)
        XCTAssertTrue(app.staticTexts["绑定时间"].exists)
        XCTAssertTrue(app.buttons["账号与数据管理"].exists)
        XCTAssertTrue(app.buttons["解除设备绑定"].exists)

        app.buttons["✏️ 编辑"].tap()
        XCTAssertTrue(app.staticTexts["学习档案"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["学习者名字"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testShortCodeBindingAndUnbindFlow() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestResetState", "-UITestMockBinding", "-UITestSeedParentPin", "-UITestRouteConfig"]
        app.launch()

        XCTAssertTrue(app.staticTexts["ConfigTitle"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["绑定家长账号"].exists)
        app.buttons["绑定家长账号"].tap()

        XCTAssertTrue(app.staticTexts.matching(identifier: "ScanBindingTitle").firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["ScanBindingParentLoginLink"].exists)
        XCTAssertTrue(app.buttons["ScanBindingTermsButton"].exists)
        XCTAssertTrue(app.buttons["ScanBindingPrivacyButton"].exists)
        XCTAssertTrue(app.buttons["ScanBindingManualEntry"].waitForExistence(timeout: 5))
        app.buttons["ScanBindingManualEntry"].tap()

        XCTAssertTrue(app.textFields["6 位短码"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["ScanBindingParentLoginLinkManual"].exists)
        XCTAssertTrue(app.buttons["ScanBindingTermsButton"].exists)
        XCTAssertTrue(app.buttons["ScanBindingPrivacyButton"].exists)
        app.textFields["6 位短码"].tap()
        app.textFields["6 位短码"].typeText("123456")
        app.buttons["绑定"].tap()

        XCTAssertTrue(app.staticTexts["绑定成功：小明测试46373"].waitForExistence(timeout: 5))
        let boundProfile = app.buttons.matching(identifier: "ConfigBoundDeviceInfoButton").element
        if boundProfile.waitForExistence(timeout: 2) {
            XCTAssertTrue(boundProfile.label.contains("小明测试46373"))
            boundProfile.tap()
        }
        XCTAssertTrue(app.staticTexts["学习档案"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["🦁 小明测试46373"].exists)
        app.buttons["解除设备绑定"].tap()
        app.secureTextFields["家长 PIN"].tap()
        app.secureTextFields["家长 PIN"].typeText("123456")
        app.buttons["确认解除"].tap()

        XCTAssertTrue(app.buttons["绑定家长账号"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testDebugBackendMenuAndBypassSecretRoutesAreReachableInDebugBuild() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestResetState", "-UITestRouteDevMenu"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Developer Options"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Backend environment (debug builds only)"].exists)
        XCTAssertTrue(app.buttons["DevMenuBypassSecretButton"].exists)
        XCTAssertTrue(app.buttons["DevMenuRefreshManifestButton"].exists)
        XCTAssertTrue(app.buttons["DevMenuLocalCard"].exists)
        XCTAssertTrue(app.buttons["DevMenuStagingCard"].exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "https://happyword.cool")).firstMatch.exists)

        app.terminate()
        app.launchArguments = ["-UITestResetState", "-UITestRouteBypassSecret"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Bypass Secret"].waitForExistence(timeout: 5))
        let bypassInput = app.secureTextFields.firstMatch
        XCTAssertTrue(bypassInput.waitForExistence(timeout: 5))
        bypassInput.tap()
        bypassInput.typeText("secret-demo")
        app.buttons["保存"].tap()

        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "https://happyword.cool")).firstMatch.waitForExistence(timeout: 5))
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
        app.launchArguments = ["-UITestResetState", "-UITestSeedBoundDevice"]
        app.launch()

        XCTAssertTrue(app.buttons["设置"].waitForExistence(timeout: 5))
        app.buttons["设置"].tap()
        XCTAssertTrue(app.staticTexts["ConfigTitle"].waitForExistence(timeout: 5))

        app.buttons["ConfigParentPinButton"].tap()
        XCTAssertTrue(app.secureTextFields["6 位数字"].waitForExistence(timeout: 5))
        app.secureTextFields["6 位数字"].tap()
        app.secureTextFields["6 位数字"].typeText("123456")
        app.secureTextFields["再次输入 PIN"].tap()
        app.secureTextFields["再次输入 PIN"].typeText("123456")
        app.buttons["保存 PIN"].tap()

        XCTAssertTrue(app.buttons["家长管理后台"].waitForExistence(timeout: 5))
        app.buttons["家长管理后台"].tap()
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
        XCTAssertTrue(app.descendants(matching: .any)["LessonReviewThumbnail"].exists)
        XCTAssertTrue(app.staticTexts["LessonReviewCount"].waitForExistence(timeout: 5))
        app.buttons["LessonReviewRowEdit_0"].tap()
        XCTAssertTrue(app.textFields["LessonReviewRowWordInput_0"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["LessonReviewRowMeaningInput_0"].exists)
        app.buttons["LessonReviewRowCancel_0"].tap()
        app.switches.element(boundBy: 1).tap()
        app.buttons["审核通过"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "复核完成")).firstMatch.waitForExistence(timeout: 5))
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
    func testWishlistAddWishCreatesCustomWishAfterParentPin() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestResetState", "-UITestSeedParentPin", "-UITestRouteWishlist"]
        app.launch()

        XCTAssertTrue(app.staticTexts["魔法愿望单"].waitForExistence(timeout: 5))
        app.buttons["添加愿望"].tap()

        XCTAssertTrue(app.staticTexts["添加愿望"].waitForExistence(timeout: 5))
        app.textFields["愿望名称"].tap()
        app.textFields["愿望名称"].typeText("周末去公园")
        app.textFields["魔法币"].tap()
        app.textFields["魔法币"].typeText("12")
        app.textFields["图标"].tap()
        app.textFields["图标"].clearAndTypeText("🌳")
        app.secureTextFields["家长 PIN"].tap()
        app.secureTextFields["家长 PIN"].typeText("123456")
        app.buttons["保存愿望"].tap()

        XCTAssertTrue(app.staticTexts["周末去公园"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["12 ✨"].exists)
    }

    @MainActor
    func testWishlistAddWishRejectsInvalidInputAndKeepsDialogOpen() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestResetState", "-UITestSeedParentPin", "-UITestRouteWishlist"]
        app.launch()

        XCTAssertTrue(app.staticTexts["魔法愿望单"].waitForExistence(timeout: 5))
        app.buttons["添加愿望"].tap()

        XCTAssertTrue(app.staticTexts["添加愿望"].waitForExistence(timeout: 5))
        app.textFields["愿望名称"].tap()
        app.textFields["愿望名称"].typeText(" ")
        app.textFields["魔法币"].tap()
        app.textFields["魔法币"].typeText("0")
        app.secureTextFields["家长 PIN"].tap()
        app.secureTextFields["家长 PIN"].typeText("123456")
        app.buttons["保存愿望"].tap()

        XCTAssertTrue(app.staticTexts["请输入愿望名称、正整数魔法币和图标"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["添加愿望"].exists)
    }

    @MainActor
    func testConfigQuestionTypesAndCustomTimerValidationMatchHarmony() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestResetState", "-UITestRouteConfig"]
        app.launch()

        XCTAssertTrue(app.staticTexts["ConfigTitle"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["ConfigQuestionType_choice"].exists)
        XCTAssertTrue(app.buttons["ConfigQuestionType_fill-letter"].exists)
        XCTAssertTrue(app.buttons["ConfigQuestionType_fill-letter-medium"].exists)
        XCTAssertTrue(app.buttons["ConfigQuestionType_spell"].exists)
        XCTAssertTrue(app.buttons["ConfigQuestionType_sentence-cloze"].exists)

        app.buttons["ConfigQuestionType_spell"].tap()
        app.buttons["ConfigQuestionType_spell"].tap()
        app.buttons["ConfigTimerCustom"].tap()

        let customTimerInput = app.textFields["CustomTimerDialogInput"]
        XCTAssertTrue(customTimerInput.waitForExistence(timeout: 5))
        customTimerInput.tap()
        customTimerInput.clearAndTypeText("0")
        app.buttons["CustomTimerDialogConfirmButton"].tap()
        XCTAssertTrue(app.staticTexts["最少 1 秒"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["CustomTimerDialogTitle"].exists)

        customTimerInput.clearAndTypeText("3")
        app.buttons["CustomTimerDialogConfirmButton"].tap()
        XCTAssertTrue(app.textFields["CustomTimerDialogInput"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["ConfigTimerCustom"].label.contains("3s"))
    }

    @MainActor
    func testBattleFeedbackProjectileAndSpellControlsMatchHarmony() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestResetState", "-UITestExposeCorrectAnswer", "-UITestQuestionTypesChoiceOnly", "-UITestRouteBattle"]
        app.launch()

        assertLandscape(app)
        XCTAssertTrue(app.staticTexts["Battle"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Pronounce"].exists)
        XCTAssertTrue(app.staticTexts["Choose the right spell"].exists)
        XCTAssertTrue(app.staticTexts["HP 10 / 10"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["HP 3 / 3"].firstMatch.waitForExistence(timeout: 5))

        tapFirstIncorrectFruitOption(in: app)
        XCTAssertTrue(waitForBattleFeedback(in: app)?.hasPrefix("Correct answer:") == true)
        XCTAssertTrue(app.staticTexts["HP 9 / 10"].firstMatch.waitForExistence(timeout: 5))
        waitForBattleFeedbackToClear(in: app)

        let correct = app.buttons["BattleCorrectOption"]
        XCTAssertTrue(correct.waitForExistence(timeout: 5))
        correct.tap()
        XCTAssertTrue(app.staticTexts["Battle"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Pronounce"].exists)
    }

    @MainActor
    func testBattleComboAndSpellLetterRejectionMatchHarmony() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestResetState", "-UITestExposeCorrectAnswer", "-UITestQuestionTypesChoiceOnly", "-UITestRouteBattle"]
        app.launch()

        assertLandscape(app)
        XCTAssertTrue(app.staticTexts["Combo: 0"].waitForExistence(timeout: 5))

        XCTAssertTrue(tapCorrectBattleOptionsUntilComboBurst(in: app))
        XCTAssertTrue(app.staticTexts["Combo: 0"].waitForExistence(timeout: 5))
        waitForBattleFeedbackToClear(in: app)

        app.terminate()
        app.launchArguments = ["-UITestResetState", "-UITestExposeCorrectAnswer", "-UITestQuestionTypesSpellOnly", "-UITestBattleBossFirst", "-UITestRouteBattle"]
        app.launch()
        assertLandscape(app)
        XCTAssertTrue(app.staticTexts["_"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["HP 10 / 10"].firstMatch.waitForExistence(timeout: 5))

        tapFirstIncorrectBattleOption(in: app)
        XCTAssertEqual(waitForBattleFeedback(in: app), "Try again")
        XCTAssertTrue(app.staticTexts["_"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["HP 9 / 10"].firstMatch.waitForExistence(timeout: 5))

        tapCurrentCorrectBattleOption(in: app)
        XCTAssertTrue(app.staticTexts["Battle"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["BattleCorrectOption"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testBattleSentenceClozePromptAndOptionsMatchHarmony() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-UITestResetState",
            "-UITestQuestionTypesSentenceClozeOnly",
            "-UITestBattleBossFirst",
            "-UITestRouteBattle",
        ]
        app.launch()

        assertLandscape(app)
        XCTAssertTrue(app.staticTexts["BattleSentenceClozePrompt"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["BattleSentenceClozePrompt"].label, "I eat an ____ after lunch.")
        XCTAssertTrue(app.staticTexts["BattleSentenceClozeZh"].exists)
        XCTAssertEqual(app.staticTexts["BattleSentenceClozeZh"].label, "我午饭后吃一个苹果。")
        XCTAssertTrue(app.descendants(matching: .any)["BattleOptionsRow_SentenceCloze"].exists)
        XCTAssertTrue(app.buttons["apple"].exists)
        XCTAssertTrue(app.buttons["banana"].exists)
        XCTAssertTrue(app.buttons["orange"].exists)
    }

    @MainActor
    func testPackSyncActivationGrowsHomeRegionChipRow() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestResetState", "-UITestSeedBoundDevice", "-UITestRoutePackManager"]
        app.launch()

        XCTAssertTrue(app.staticTexts["我的词包"].waitForExistence(timeout: 5))
        app.buttons["同步词包"].tap()
        XCTAssertTrue(app.staticTexts["已同步官方/家庭词包"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Space Station"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Family Snacks"].exists)

        XCTAssertTrue(app.switches["PackToggle_space-station"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testLearningReportZeroStateCountersMatchHarmony() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestResetState", "-UITestRouteLearningReportEmpty"]
        app.launch()

        XCTAssertTrue(app.staticTexts["学习报告"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["0%"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["已答 0 / 0 题"].exists)
        XCTAssertEqual(app.descendants(matching: .any)["LearningReportMastered"].label, "掌握 0")
        XCTAssertEqual(app.descendants(matching: .any)["LearningReportFamiliar"].label, "熟悉 0")
        XCTAssertEqual(app.descendants(matching: .any)["LearningReportLearning"].label, "学习中 0")
        XCTAssertEqual(app.descendants(matching: .any)["LearningReportNewCount"].label, "新词 10")
        XCTAssertTrue(app.staticTexts["0 / 10"].exists)
        XCTAssertTrue(app.staticTexts["0% 完成"].exists)
    }

    @MainActor
    func testGalleryQrBindingCompletesWithMockPayload() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestResetState", "-UITestMockBinding", "-UITestSeedParentPin", "-UITestRouteScanBinding"]
        app.launch()

        XCTAssertTrue(app.staticTexts["ScanBindingTitle"].waitForExistence(timeout: 5))
        app.buttons["ScanBindingPickFromGallery"].tap()

        XCTAssertTrue(app.staticTexts["家长账户"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "小明测试")).firstMatch.exists)
    }

    @MainActor
    func testParentAdminPendingPublishReviewAndGalleryFlowsAreIndividuallyCovered() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestResetState", "-UITestRouteParentAdmin"]
        app.launch()

        XCTAssertTrue(app.staticTexts["ParentAdminTitle"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["ParentAdminServerLabel"].exists)
        app.buttons["ParentAdminRefresh"].tap()
        XCTAssertTrue(app.staticTexts["ParentAdminPendingTitle"].waitForExistence(timeout: 5))

        app.textFields["ParentAdminPublishNotes"].tap()
        app.textFields["ParentAdminPublishNotes"].typeText("ui parity")
        app.buttons["ParentAdminPublishButton"].tap()
        XCTAssertTrue(app.staticTexts["ParentAdminPublishSummary"].label.contains("已发布词包"))

        app.buttons["从相册导入"].tap()
        XCTAssertTrue(app.staticTexts["课本识别审核"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["LessonReviewThumbnail"].exists)
        XCTAssertTrue(app.staticTexts["LessonReviewCount"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches.element(boundBy: 1).exists)
        app.buttons["LessonReviewRowEdit_0"].tap()
        XCTAssertTrue(app.textFields["LessonReviewRowWordInput_0"].waitForExistence(timeout: 5))
        app.buttons["LessonReviewRowCancel_0"].tap()
        app.buttons["返回"].tap()
        XCTAssertTrue(app.staticTexts["ParentAdminTitle"].waitForExistence(timeout: 5))

        app.buttons.matching(identifier: "LessonDraftReviewLink_draft-1").firstMatch.tap()
        XCTAssertTrue(app.staticTexts["课本识别审核"].waitForExistence(timeout: 5))
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
    private func assertTopLeftBackButton(_ button: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(button.waitForExistence(timeout: 5), file: file, line: line)
        let frame = button.frame
        let screen = app.windows.element(boundBy: 0).frame
        XCTAssertLessThan(frame.minX, screen.minX + 130, file: file, line: line)
        XCTAssertLessThan(frame.minY, screen.minY + 90, file: file, line: line)
    }

    @MainActor
    private func tapCurrentCorrectBattleOption(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons["BattleCorrectOption"]
        let victory = app.staticTexts["胜利"]
        let loss = app.staticTexts["继续练习"]
        let deadline = Date().addingTimeInterval(2)
        while (!button.exists || !button.isHittable) && !victory.exists && !loss.exists && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        if victory.exists {
            return
        }
        if loss.exists {
            XCTFail("Battle ended before victory", file: file, line: line)
            return
        }
        XCTAssertTrue(button.exists, file: file, line: line)
        XCTAssertTrue(button.isHittable, file: file, line: line)
        button.tap()
    }

    @MainActor
    private func tapCorrectBattleOptionsUntilComboBurst(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        for _ in 0..<12 {
            waitForBattleFeedbackToClear(in: app)
            tapCurrentCorrectBattleOption(in: app, file: file, line: line)
            if waitForBattleFeedback(in: app)?.hasPrefix("Combo 3!") == true {
                return true
            }
        }
        return false
    }

    @MainActor
    private func tapCorrectBattleOptionsUntilVictory(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let victory = app.staticTexts["胜利"]
        let loss = app.staticTexts["继续练习"]
        for _ in 0..<40 {
            if victory.exists {
                return
            }
            waitForBattleFeedbackToClear(in: app)
            let button = app.buttons["BattleCorrectOption"]
            let deadline = Date().addingTimeInterval(2)
            while (!button.exists || !button.isHittable) && !victory.exists && !loss.exists && Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            }
            if victory.exists {
                return
            }
            if loss.exists {
                XCTFail("Battle ended before victory", file: file, line: line)
                return
            }
            tapCurrentCorrectBattleOption(in: app, file: file, line: line)
            if victory.waitForExistence(timeout: 1.5) {
                return
            }
            waitForBattleFeedbackToClear(in: app)
        }
    }

    @MainActor
    private func tapFirstIncorrectBattleOption(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let exposedWrongButton = app.buttons["BattleIncorrectOption"].firstMatch
        if exposedWrongButton.waitForExistence(timeout: 1), exposedWrongButton.isHittable {
            exposedWrongButton.tap()
            return
        }
        let wrongButtonIds = ["BattleOptionA", "BattleOptionB", "BattleOptionC", "BattleOptionD"]
        for id in wrongButtonIds {
            let button = app.buttons[id]
            if button.exists && button.isHittable {
                button.tap()
                return
            }
        }
        for button in app.buttons.allElementsBoundByIndex {
            guard button.exists,
                  button.isHittable,
                  !["BattleCorrectOption", "Pronounce", "返回"].contains(button.label)
            else { continue }
            button.tap()
            return
        }
        XCTFail("No hittable incorrect battle option", file: file, line: line)
    }

    @MainActor
    private func tapFirstIncorrectFruitOption(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        guard let correct = currentFruitAnswer(in: app, timeout: 2) else {
            XCTFail("No current fruit answer", file: file, line: line)
            return
        }
        let exposedWrongButton = app.buttons["BattleIncorrectOption"].firstMatch
        if exposedWrongButton.exists && exposedWrongButton.isHittable {
            exposedWrongButton.tap()
            return
        }
        for wrong in Self.fruitAnswers.values where wrong != correct {
            let button = app.buttons[wrong]
            if button.exists && button.isHittable {
                button.tap()
                return
            }
        }
        XCTFail("No hittable incorrect fruit option", file: file, line: line)
    }

    @MainActor
    private func waitForBattleFeedback(in app: XCUIApplication) -> String? {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if app.staticTexts["Correct!"].exists {
                return "Correct!"
            }
            let wrong = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "Correct answer:")).firstMatch
            if wrong.exists {
                return wrong.label
            }
            let combo = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "Combo 3!")).firstMatch
            if combo.exists {
                return combo.label
            }
            if app.staticTexts["Try again"].exists {
                return "Try again"
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return nil
    }

    @MainActor
    private func waitForBattleFeedbackToClear(in app: XCUIApplication) {
        let deadline = Date().addingTimeInterval(3)
        while (app.staticTexts["Correct!"].exists
            || app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "Correct answer:")).firstMatch.exists
            || app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "Combo 3!")).firstMatch.exists
            || app.staticTexts["Try again"].exists)
            && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
    }

    @MainActor
    private func currentFruitAnswer(in app: XCUIApplication, timeout: TimeInterval) -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for (prompt, answer) in Self.fruitAnswers
            where app.staticTexts[prompt].exists
                && ((app.buttons[answer].exists && app.buttons[answer].isHittable)
                    || (app.buttons["BattleCorrectOption"].exists && app.buttons["BattleCorrectOption"].isHittable)) {
                return answer
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return nil
    }

    @MainActor
    private func currentFruitPrompt(in app: XCUIApplication, timeout: TimeInterval) -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for (prompt, answer) in Self.fruitAnswers
            where app.staticTexts[prompt].exists
                && ((app.buttons[answer].exists && app.buttons[answer].isHittable)
                    || (app.buttons["BattleCorrectOption"].exists && app.buttons["BattleCorrectOption"].isHittable)) {
                return prompt
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

private extension XCUIElement {
    func clearAndTypeText(_ text: String) {
        guard let current = value as? String else {
            typeText(text)
            return
        }
        tap()
        let delete = String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count)
        typeText(delete)
        typeText(text)
    }
}
