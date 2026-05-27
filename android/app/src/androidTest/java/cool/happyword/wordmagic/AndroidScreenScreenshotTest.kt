package cool.happyword.wordmagic

import android.content.Context
import android.graphics.Bitmap
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextInput
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.io.FileOutputStream
import org.junit.Before
import org.junit.Rule
import org.junit.Test

class AndroidScreenScreenshotTest {
    @get:Rule
    val composeRule = createAndroidComposeRule<MainActivity>()

    @Before
    fun resetLocalState() {
        val targetContext = InstrumentationRegistry.getInstrumentation().targetContext
        targetContext.getSharedPreferences("wordmagic-local-progress", Context.MODE_PRIVATE).edit().clear().commit()
        targetContext.getSharedPreferences("wordmagic-cloud", Context.MODE_PRIVATE).edit().clear().commit()
        targetContext.getSharedPreferences("wordmagic-debug-routing", Context.MODE_PRIVATE).edit().clear().commit()
        composeRule.runOnUiThread {
            composeRule.activity.recreate()
        }
        composeRule.waitUntil(timeoutMillis = 2_000) { hasNode("HomeScreen") }
    }

    @Test
    fun captureLearningReportScreen() {
        composeRule.onNodeWithTag("HomePlanButton").performClick()
        composeRule.onNodeWithTag("TodayPlanReportButton").performClick()
        composeRule.waitUntil(timeoutMillis = 5_000) {
            composeRule.onAllNodesWithTag("LearningReportScreen").fetchSemanticsNodes().isNotEmpty()
        }
        capture("learning-report.png")
        composeRule.onNodeWithTag("LearningReportBackButton").performClick()
        composeRule.onNodeWithTag("TodayPlanBackButton").performClick()
    }

    @Test
    fun captureGrowthAndCloudScreens() {
        capture("local-growth-home.png")

        composeRule.onNodeWithTag("HomeConfigButton").performClick()
        composeRule.onNodeWithTag("ConfigPackManagerButton").performScrollTo().performClick()
        capture("pack-manager.png")
        composeRule.onNodeWithTag("PackManagerBack").performClick()
        composeRule.waitUntil(timeoutMillis = 2_000) { hasNode("HomeScreen") }

        composeRule.onNodeWithTag("HomeWishlistButton").performClick()
        composeRule.waitUntil(timeoutMillis = 2_000) { hasNode("WishlistScreen") && hasNode("WishlistHistoryButton") }
        capture("wishlist.png")
        composeRule.onNodeWithTag("WishlistHistoryButton").performClick()
        capture("redemption-history.png")
        composeRule.onNodeWithTag("RedemptionHistoryBackButton").performClick()
        composeRule.onNodeWithTag("WishlistBackButton").performClick()

        composeRule.onNodeWithTag("HomeCodexButton").performClick()
        capture("monster-codex.png")
        composeRule.onNodeWithTag("MonsterCodexBack").performClick()

        composeRule.onNodeWithTag("HomePlanButton").performClick()
        capture("today-plan.png")
        composeRule.onNodeWithTag("TodayPlanBackButton").performClick()

        composeRule.onNodeWithTag("HomeConfigButton").performClick()
        composeRule.onNodeWithTag("ConfigCloudBindingButton").performScrollTo().performClick()
        composeRule.waitUntil(timeoutMillis = 2_000) {
            hasNode("ScanBindingScreen") || hasNode("BoundDeviceInfoScreen")
        }
        if (hasNode("ScanBindingScreen")) {
            capture("scan-binding.png")
            composeRule.onNodeWithTag("ScanBindingManualToggle").performClick()
            composeRule.onNodeWithTag("ScanBindingManualInput").performTextInput("000001")
            composeRule.onNodeWithTag("ScanBindingManualSubmit").performClick()
            composeRule.waitUntil(timeoutMillis = 2_000) {
                hasNode("ScanBindingFailureHint")
            }
            capture("scan-binding-error.png")
        } else {
            capture("bound-device-info.png")
        }
    }

    @Test
    fun captureConfigScreenOnly() {
        composeRule.onNodeWithTag("HomeConfigButton").performClick()
        composeRule.waitUntil(timeoutMillis = 2_000) { hasNode("ConfigQuestionType_sentence-cloze") }
        composeRule.onNodeWithTag("ConfigQuestionType_sentence-cloze").performScrollTo()
        capture("config-landscape.png")
    }

    @Test
    fun captureSentenceClozeBattleScreen() {
        composeRule.onNodeWithTag("HomeConfigButton").performClick()
        composeRule.onNodeWithTag("ConfigQuestionType_choice").performScrollTo().performClick()
        composeRule.onNodeWithTag("ConfigQuestionType_fill-letter").performScrollTo().performClick()
        composeRule.onNodeWithTag("ConfigQuestionType_fill-letter-medium").performScrollTo().performClick()
        composeRule.onNodeWithTag("ConfigQuestionType_spell").performScrollTo().performClick()
        composeRule.onNodeWithTag("ConfigBackButton").performClick()
        composeRule.waitUntil(timeoutMillis = 2_000) { hasNode("HomeScreen") }

        composeRule.onNodeWithTag("HomeStartButton").performClick()
        composeRule.waitUntil(timeoutMillis = 2_000) { hasNode("BattleSentenceClozePrompt") }
        capture("sentence-cloze-battle.png")
    }

    @Test
    fun captureCoreParentAndDebugScreens() {
        seedCloudBindingPrefs()
        composeRule.runOnUiThread {
            composeRule.activity.recreate()
        }
        composeRule.waitForIdle()

        composeRule.onNodeWithTag("HomeConfigButton").performClick()
        capture("config-landscape.png")

        composeRule.onNodeWithTag("ConfigParentPinButton").performScrollTo().performClick()
        capture("parent-pin-portrait.png")
        composeRule.onNodeWithTag("ParentPinInput").performTextInput("123456")
        composeRule.waitUntil(timeoutMillis = 2_000) { hasNode("ParentAdminScreen") }
        capture("parent-admin.png")

        composeRule.onAllNodesWithText("审核")[0].performClick()
        composeRule.waitUntil(timeoutMillis = 2_000) { hasNode("LessonDraftReviewScreen") }
        capture("lesson-review-portrait.png")
        composeRule.onNodeWithTag("LessonDraftReviewBackButton").performClick()
        composeRule.waitUntil(timeoutMillis = 2_000) { hasNode("ParentAdminScreen") }
        composeRule.onNodeWithTag("ParentAdminBackButton").performClick()
        composeRule.waitUntil(timeoutMillis = 2_000) { hasNode("ConfigScreen") }

        composeRule.onNodeWithTag("ConfigBackButton").performClick()
        composeRule.waitUntil(timeoutMillis = 2_000) { hasNode("HomeScreen") }
        repeat(3) { composeRule.onNodeWithTag("HomeVersionLabel").performClick() }
        composeRule.waitUntil(timeoutMillis = 2_000) { hasNode("DevMenuScreen") }
        capture("dev-menu-debug.png")
        composeRule.onNodeWithTag("DevMenuBypassSecretButton").performClick()
        composeRule.waitUntil(timeoutMillis = 2_000) { hasNode("BypassSecretPageInput") }
        capture("bypass-secret-debug.png")
    }

    @Test
    fun captureResultScreen() {
        composeRule.onNodeWithTag("HomeConfigButton").performClick()
        composeRule.onNodeWithTag("ConfigQuestionType_fill-letter").performScrollTo().performClick()
        composeRule.onNodeWithTag("ConfigQuestionType_fill-letter-medium").performScrollTo().performClick()
        composeRule.onNodeWithTag("ConfigQuestionType_spell").performScrollTo().performClick()
        composeRule.onNodeWithTag("ConfigQuestionType_sentence-cloze").performScrollTo().performClick()
        repeat(2) { composeRule.onNodeWithTag("ConfigMonsterHpDecrement").performScrollTo().performClick() }
        repeat(4) { composeRule.onNodeWithTag("ConfigMonsterCountDecrement").performScrollTo().performClick() }
        composeRule.onNodeWithTag("ConfigBackButton").performClick()
        composeRule.waitUntil(timeoutMillis = 2_000) { hasNode("HomeScreen") }

        composeRule.onNodeWithTag("HomeStartButton").performClick()
        composeRule.waitUntil(timeoutMillis = 2_000) { hasNode("BattleScreen") }
        composeRule.onNodeWithTag("BattleEscapeButton").performClick()
        composeRule.waitUntil(timeoutMillis = 2_000) { hasNode("ResultScreen") }
        capture("result.png")
    }

    private fun capture(fileName: String) {
        composeRule.waitForIdle()
        val bitmap = composeRule.onRoot().captureToImage().asAndroidBitmap()
        val targetContext = InstrumentationRegistry.getInstrumentation().targetContext
        val dir = File(targetContext.filesDir, "screenshots").also { it.mkdirs() }
        FileOutputStream(File(dir, fileName)).use { out ->
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
        }
    }

    private fun hasNode(tag: String): Boolean {
        return composeRule.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty()
    }

    private fun seedCloudBindingPrefs() {
        val targetContext = InstrumentationRegistry.getInstrumentation().targetContext
        targetContext.getSharedPreferences("wordmagic-cloud", Context.MODE_PRIVATE).edit().clear().apply()
        File(targetContext.filesDir, "cloud_device_token.secure").delete()
        targetContext.getSharedPreferences("wordmagic-cloud", Context.MODE_PRIVATE)
            .edit()
            .putString("device_id", "device-screenshot-0001")
            .putString("binding_id", "bind-screenshot-0001")
            .putString("child_nickname", "星星")
            .putString("avatar_emoji", "🦄")
            .putString("family_label", "fam-shot")
            .apply()
        File(targetContext.filesDir, "cloud_device_token.secure").apply {
            parentFile?.mkdirs()
            writeText("device.jwt.token")
        }
    }

}
