package cool.happyword.wordmagic

import android.content.Context
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertTextContains
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.isEnabled
import androidx.compose.ui.test.junit4.v2.createEmptyComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performTextReplacement
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import org.junit.After
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class FamilyLearningFlowTest {
    @get:Rule
    val composeRule = createEmptyComposeRule()

    private var scenario: ActivityScenario<MainActivity>? = null
    private val targetContext: Context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    @After
    fun cleanup() {
        scenario?.close()
        scenario = null
        clearLocalState()
    }

    @Test
    fun configQuestionTypesAndCustomTimerValidationMatchHarmony() {
        launch(bound = false)
        openConfig()

        listOf(
            "ConfigQuestionType_choice",
            "ConfigQuestionType_fill-letter",
            "ConfigQuestionType_fill-letter-medium",
            "ConfigQuestionType_spell",
        ).forEach { tag ->
            composeRule.onNodeWithTag(tag).assertExists()
        }

        composeRule.onNodeWithTag("ConfigQuestionType_spell").performClick()
        composeRule.onNodeWithTag("ConfigQuestionType_fill-letter-medium").performScrollTo().performClick()
        composeRule.onNodeWithTag("ConfigQuestionType_fill-letter").performScrollTo().performClick()
        composeRule.onNodeWithTag("ConfigQuestionType_choice").performScrollTo().performClick()
        composeRule.onNodeWithTag("ConfigQuestionType_choice").performScrollTo().performClick()

        composeRule.onNodeWithTag("ConfigTimerCustom").performClick()
        composeRule.onNodeWithTag("CustomTimerDialogTitle").assertIsDisplayed()
        composeRule.onNodeWithTag("CustomTimerDialogInput").performTextReplacement("0")
        composeRule.onNodeWithTag("CustomTimerDialogConfirmButton").performClick()
        composeRule.onNodeWithTag("CustomTimerDialogError").assertTextContains("最少 1 秒")
        composeRule.onNodeWithTag("CustomTimerDialogInput").performTextReplacement("3")
        composeRule.onNodeWithTag("CustomTimerDialogConfirmButton").performClick()
        composeRule.waitUntil(timeoutMillis = 2_000) {
            composeRule.onAllNodesWithTag("CustomTimerDialogTitle").fetchSemanticsNodes().isEmpty()
        }
        composeRule.onNodeWithText("✓自定义 (3s)").assertIsDisplayed()
    }

    @Test
    fun packManagerSyncAddsCloudPacksAndCanActivateGlobalPack() {
        launch(bound = true)
        openConfig()
        composeRule.onNodeWithTag("ConfigPackManagerButton").performScrollTo().performClick()
        composeRule.onNodeWithTag("PackManagerScreen").assertIsDisplayed()

        composeRule.onNodeWithTag("PackManagerSyncButton").performClick()
        composeRule.waitForIdle()
        composeRule.onNodeWithTag("PackManagerLimitMessage").assertTextContains("同步成功", substring = true)
        composeRule.onNodeWithTag("PackManagerScreen").performScrollToNode(hasTestTag("PackLabel_global-colors"))
        composeRule.onNodeWithTag("PackLabel_global-colors").performScrollTo().assertTextContains("Color Harbor")
        composeRule.onNodeWithTag("PackManagerScreen").performScrollToNode(hasTestTag("PackLabel_family-space"))
        composeRule.onNodeWithTag("PackLabel_family-space").performScrollTo().assertTextContains("Family Space")
    }

    @Test
    fun packManagerCloudActivationUpdatesHomeRegionsLikeHarmony() {
        launch(bound = true)
        openConfig()
        composeRule.onNodeWithTag("ConfigPackManagerButton").performScrollTo().performClick()
        composeRule.onNodeWithTag("PackManagerSyncButton").performClick()
        composeRule.onNodeWithTag("PackManagerScreen").performScrollToNode(hasTestTag("PackToggle_global-colors"))

        composeRule.onNodeWithTag("PackToggle_fruit-forest").performScrollTo().performClick()
        composeRule.onNodeWithTag("PackToggle_ocean-realm").performScrollTo().performClick()
        composeRule.onNodeWithTag("PackManagerScreen").performScrollToNode(hasTestTag("PackToggle_global-colors"))
        composeRule.onNodeWithTag("PackToggle_global-colors").performScrollTo().performClick()
        composeRule.onNodeWithTag("PackManagerScreen").performScrollToNode(hasTestTag("PackToggle_family-space"))
        composeRule.onNodeWithTag("PackToggle_family-space").performScrollTo().performClick()
        composeRule.onNodeWithTag("PackManagerScreen").performScrollToNode(hasTestTag("PackManagerBack"))
        composeRule.onNodeWithTag("PackManagerBack").performClick()

        composeRule.onNodeWithTag("HomeScreen").assertIsDisplayed()
        composeRule.onNodeWithTag("RegionChip_global-colors").assertIsDisplayed()
        composeRule.onNodeWithTag("RegionChip_family-space").assertIsDisplayed()
    }

    @Test
    fun parentAdminPinGateReviewAndGalleryFlowsMatchHarmony() {
        launch(bound = true)
        setParentPinFromConfig()

        composeRule.onNodeWithTag("ConfigParentAdminButton").performScrollTo().performClick()
        composeRule.onNodeWithTag("ParentPinScreen").assertIsDisplayed()
        composeRule.onNodeWithTag("ParentPinInput").performTextInput("000000")
        composeRule.onNodeWithTag("ParentPinScreen").assertIsDisplayed()
        composeRule.onNodeWithTag("ParentPinInput").performTextReplacement("123456")
        composeRule.waitUntil(timeoutMillis = 2_000) { hasTag("ParentAdminScreen") }

        composeRule.onNodeWithText("家长管理后台").assertIsDisplayed()
        composeRule.onNodeWithText("待审核草稿").performScrollTo().assertIsDisplayed()
        composeRule.onAllNodesWithText("审核")[0].performClick()
        composeRule.onNodeWithTag("LessonDraftReviewScreen").assertIsDisplayed()
        composeRule.onNodeWithText("apple 苹果").assertIsDisplayed()
        composeRule.onNodeWithText("返回").performClick()
        composeRule.onNodeWithTag("ParentAdminScreen").assertIsDisplayed()
        composeRule.onNodeWithText("🖼 从相册选择").performScrollTo().performClick()
        composeRule.onNodeWithTag("LessonDraftReviewScreen").assertIsDisplayed()
    }

    @Test
    fun wishlistCustomWishValidationAndCreationMatchHarmony() {
        launch(bound = true)
        setParentPinFromConfig()
        composeRule.onNodeWithTag("ConfigBackButton").performClick()
        composeRule.onNodeWithTag("HomeWishlistButton").performClick()
        composeRule.onNodeWithTag("WishlistScreen").assertIsDisplayed()

        assertTrue(composeRule.onAllNodesWithTag("WishRemove_wish-ipad-20min").fetchSemanticsNodes().isEmpty())
        composeRule.onNodeWithTag("WishlistAddCustomButton").assertIsDisplayed().performClick()
        composeRule.onNodeWithTag("AddCustomWishPinInput").performTextInput("123456")
        composeRule.onNodeWithTag("AddCustomWishPinConfirm").performClick()
        composeRule.onNodeWithTag("AddCustomWishNameInput").assertIsDisplayed()
        composeRule.onNodeWithTag("AddCustomWishSubmitButton").performClick()
        composeRule.onNodeWithTag("AddCustomWishError").assertTextContains("请输入愿望名称")

        composeRule.onNodeWithTag("AddCustomWishNameInput").performTextReplacement("周末去公园")
        composeRule.onNodeWithTag("AddCustomWishCostInput").performTextReplacement("0")
        composeRule.onNodeWithTag("AddCustomWishEmojiInput").performTextReplacement("🌳")
        composeRule.onNodeWithTag("AddCustomWishSubmitButton").performClick()
        composeRule.onNodeWithTag("AddCustomWishError").assertTextContains("数量需在 5 ~ 200 之间")

        composeRule.onNodeWithTag("AddCustomWishCostInput").performTextReplacement("12")
        composeRule.onNodeWithTag("AddCustomWishSubmitButton").performClick()
        composeRule.waitUntil(timeoutMillis = 2_000) {
            composeRule.onAllNodesWithTag("AddCustomWishNameInput").fetchSemanticsNodes().isEmpty()
        }
        composeRule.onNodeWithText("周末去公园").assertIsDisplayed()
        assertTrue(composeRule.onAllNodesWithText("✕").fetchSemanticsNodes().isNotEmpty())
    }

    @Test
    fun bindingScreenCoversManualErrorAndGalleryQrEntryPoints() {
        launch(bound = false)
        openConfig()
        composeRule.onNodeWithTag("ConfigCloudBindingButton").performScrollTo().performClick()
        composeRule.onNodeWithTag("ScanBindingScreen").assertIsDisplayed()
        composeRule.onNodeWithTag("ScanBindingGalleryButton").assertIsDisplayed()
        composeRule.onNodeWithTag("ScanBindingScannerButton").assertIsDisplayed()
        composeRule.onNodeWithTag("ScanBindingManualToggle").performClick()
        composeRule.onNodeWithTag("ScanBindingManualInput").performTextInput("000001")
        composeRule.onNodeWithTag("ScanBindingManualSubmit").performClick()
        composeRule.onNodeWithTag("ScanBindingFailureHint").assertIsDisplayed()
    }

    @Test
    fun manualShortCodeBindingRedeemsAndShowsBoundDeviceInfo() {
        launch(bound = false)
        openConfig()
        composeRule.onNodeWithTag("ConfigCloudBindingButton").performScrollTo().performClick()
        composeRule.onNodeWithTag("ScanBindingScreen").assertIsDisplayed()

        composeRule.onNodeWithTag("ScanBindingManualToggle").performClick()
        composeRule.onNodeWithTag("ScanBindingManualInput").performTextInput("123456")
        composeRule.onNodeWithTag("ScanBindingManualSubmit").performClick()
        composeRule.waitUntil(timeoutMillis = 3_000) { hasTag("ParentPinScreen") || hasTag("BoundDeviceInfoScreen") }
        if (hasTag("ParentPinScreen")) {
            composeRule.onNodeWithTag("ParentPinInput").performTextInput("123456")
            composeRule.waitUntil(timeoutMillis = 3_000) { hasTag("BoundDeviceInfoScreen") }
        }
        composeRule.onNodeWithTag("BoundDeviceInfoTitle").assertIsDisplayed()
        composeRule.onNodeWithTag("BoundDeviceInfoNicknameValue").assertTextContains("小明测试", substring = true)
    }

    @Test
    fun learningReportZeroStateShowsAllCounters() {
        launch(bound = false)
        composeRule.onNodeWithTag("HomePlanButton").performClick()
        composeRule.onNodeWithTag("TodayPlanReportButton").performClick()

        composeRule.onNodeWithTag("LearningReportScreen").assertIsDisplayed()
        composeRule.onNodeWithTag("LearningReportAccuracy").assertTextContains("0%")
        composeRule.onNodeWithTag("LearningReportAccuracySub").assertTextContains("已答 0 / 0 题")
        composeRule.onNodeWithTag("LearningReportMastered").assertTextContains("0")
        composeRule.onNodeWithTag("LearningReportFamiliar").assertTextContains("0")
        composeRule.onNodeWithTag("LearningReportLearning").assertTextContains("0")
        composeRule.onNodeWithTag("LearningReportNewCount").assertTextContains("25")
        composeRule.onNodeWithTag("LearningReportReviewCount").assertTextContains("0 / 0")
        composeRule.onNodeWithTag("LearningReportReviewPct").assertTextContains("0% 完成")
    }

    @Test
    fun battleWrongAnswerHpAndComboBurstMatchHarmony() {
        launch(bound = false)
        composeRule.onNodeWithTag("HomeStartButton").performClick()
        composeRule.onNodeWithTag("BattleScreen").assertIsDisplayed()

        composeRule.onNodeWithText("Combo 0").assertIsDisplayed()
        assertTrue(composeRule.onAllNodesWithText("HP 5 / 5").fetchSemanticsNodes().isNotEmpty())
        composeRule.onNodeWithText("banana").performClick()
        composeRule.onNodeWithText("Correct: apple").assertIsDisplayed()
        composeRule.onNodeWithText("HP 4 / 5").assertIsDisplayed()
        waitForBattleFeedbackToClear()

        tapCorrect("banana")
        waitForBattleFeedbackToClear()
        tapCorrect("pear")
        waitForBattleFeedbackToClear()
        tapCorrect("orange")
        composeRule.onNodeWithText("Combo 3! Magic Burst x2").assertIsDisplayed()
        composeRule.onNodeWithText("Combo 0").assertIsDisplayed()
    }

    @Test
    fun battleSpellRejectsWrongLettersLikeHarmony() {
        launch(bound = false)
        configureOneHitMonsters()
        composeRule.onNodeWithTag("HomeStartButton").performClick()
        composeRule.onNodeWithTag("BattleScreen").assertIsDisplayed()

        answerVisibleText("apple")
        waitForBattleFeedbackToClear()
        answerVisibleText("banana")
        waitForBattleFeedbackToClear()
        answerVisibleText("pear")
        waitForBattleFeedbackToClear()
        answerVisibleText("orange")
        composeRule.waitUntil(timeoutMillis = 2_000) { hasTag("BattleSpellArea") }
        composeRule.onNodeWithTag("BattleSpellSlotText_1").assertTextContains("_")
        tapFirstSpellPoolTextNot("r")
        composeRule.onNodeWithTag("BattleSpellSlotText_1").assertTextContains("_")
        composeRule.mainClock.advanceTimeBy(300)
        composeRule.onNodeWithContentDescription("BattleSpellCorrectPool").performClick()
        composeRule.waitUntil(timeoutMillis = 2_000) { slotText("BattleSpellSlotText_1") != "_" }
    }

    private fun launch(bound: Boolean) {
        clearLocalState()
        if (bound) seedCloudBinding()
        scenario = ActivityScenario.launch(MainActivity::class.java)
        composeRule.onNodeWithTag("HomeScreen").assertIsDisplayed()
    }

    private fun openConfig() {
        composeRule.onNodeWithTag("HomeConfigButton").performClick()
        composeRule.onNodeWithTag("ConfigScreen").assertIsDisplayed()
    }

    private fun setParentPinFromConfig() {
        openConfig()
        composeRule.onNodeWithTag("ConfigParentPinButton").performScrollTo().performClick()
        composeRule.onNodeWithTag("ParentPinScreen").assertIsDisplayed()
        composeRule.onNodeWithTag("ParentPinInput").performTextInput("123456")
        composeRule.waitUntil(timeoutMillis = 2_000) { hasTag("ParentAdminScreen") }
        composeRule.onNodeWithText("返回").performClick()
        composeRule.waitUntil(timeoutMillis = 2_000) { hasTag("ConfigScreen") }
    }

    private fun hasTag(tag: String): Boolean =
        composeRule.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty()

    private fun tapCorrect(text: String) {
        composeRule.waitUntil(timeoutMillis = 2_000) {
            composeRule.onAllNodesWithText(text).fetchSemanticsNodes().isNotEmpty()
        }
        composeRule.onNodeWithText(text).performClick()
    }

    private fun waitForBattleFeedbackToClear() {
        composeRule.waitUntil(timeoutMillis = 3_000) {
            composeRule.onAllNodesWithText("Correct: apple").fetchSemanticsNodes().isEmpty() &&
                composeRule.onAllNodesWithText("Hit! -1").fetchSemanticsNodes().isEmpty() &&
                composeRule.onAllNodesWithText("Combo 3! Magic Burst x2").fetchSemanticsNodes().isEmpty()
        }
    }

    private fun configureOneHitMonsters() {
        openConfig()
        composeRule.onNodeWithTag("ConfigQuestionType_fill-letter").performScrollTo().performClick()
        composeRule.onNodeWithTag("ConfigQuestionType_fill-letter-medium").performScrollTo().performClick()
        repeat(20) {
            composeRule.onNodeWithTag("ConfigMonsterHpDecrement").performScrollTo().performClick()
        }
        composeRule.onNodeWithTag("ConfigBackButton").performClick()
        composeRule.waitUntil(timeoutMillis = 2_000) { hasTag("HomeScreen") }
    }

    private fun answerVisibleText(text: String) {
        composeRule.waitUntil(timeoutMillis = 2_000) {
            enabledClickableTextExists(text)
        }
        composeRule.onNode(hasText(text) and hasClickAction() and isEnabled()).performClick()
    }

    private fun answerFirstVisibleText(candidates: List<String>) {
        composeRule.waitUntil(timeoutMillis = 2_000) {
            candidates.any(::enabledClickableTextExists)
        }
        val text = candidates.first(::enabledClickableTextExists)
        composeRule.onNode(hasText(text) and hasClickAction() and isEnabled()).performClick()
    }

    private fun tapFirstSpellPoolTextNot(text: String) {
        for (candidate in listOf("g", "a", "p", "e")) {
            if (candidate != text && enabledClickableTextExists(candidate)) {
                composeRule.onNode(hasText(candidate) and hasClickAction() and isEnabled()).performClick()
                return
            }
        }
        throw AssertionError("No wrong spell pool letter found")
    }

    private fun enabledClickableTextExists(text: String): Boolean =
        composeRule.onAllNodes(hasText(text) and hasClickAction() and isEnabled()).fetchSemanticsNodes().isNotEmpty()

    private fun slotText(tag: String): String =
        composeRule.onNodeWithTag(tag).fetchSemanticsNode().config[SemanticsProperties.Text].joinToString("") { it.text }

    private fun clearLocalState() {
        targetContext.getSharedPreferences("wordmagic-local-progress", Context.MODE_PRIVATE).edit().clear().commit()
        targetContext.getSharedPreferences("wordmagic-cloud", Context.MODE_PRIVATE).edit().clear().commit()
        targetContext.getSharedPreferences("wordmagic-debug-routing", Context.MODE_PRIVATE).edit().clear().commit()
        File(targetContext.filesDir, "cloud_device_token.secure").delete()
    }

    private fun seedCloudBinding() {
        targetContext.getSharedPreferences("wordmagic-cloud", Context.MODE_PRIVATE)
            .edit()
            .putString("device_id", "device-parity-0001")
            .putString("binding_id", "bind-parity-0001")
            .putString("child_nickname", "星星")
            .putString("avatar_emoji", "🦄")
            .putString("family_label", "fam-parity")
            .putString("child_profile_id", "child-parity-0001")
            .putString("paired_at_ms", "1715526545000")
            .putString("device_id_source", "preferences_fallback")
            .commit()
        File(targetContext.filesDir, "cloud_device_token.secure").apply {
            parentFile?.mkdirs()
            writeText("device.jwt.token")
        }
    }
}
