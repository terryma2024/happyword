package cool.happyword.wordmagic

import android.content.Context
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.assertHeightIsEqualTo
import androidx.compose.ui.test.assertWidthIsEqualTo
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isEnabled
import androidx.compose.ui.test.junit4.v2.createEmptyComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.unit.dp
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.After
import org.junit.Before
import org.junit.Rule
import org.junit.Test

class LocalGrowthFlowTest {
    @get:Rule
    val forceNative = ForceNativeBattleRule()

    @get:Rule
    val composeRule = createEmptyComposeRule()

    private var scenario: ActivityScenario<MainActivity>? = null
    private val targetContext: Context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Before
    fun launchWithCleanLocalProgress() {
        clearLocalProgress()
        scenario = ActivityScenario.launch(MainActivity::class.java)
    }

    @After
    fun cleanup() {
        scenario?.close()
        scenario = null
        clearLocalProgress()
    }

    @Test
    fun packManagerCanToggleAndReturnHome() {
        composeRule.onNodeWithTag("HomeConfigButton").performClick()
        composeRule.onNodeWithTag("ConfigPackManagerButton").performScrollTo().performClick()
        composeRule.onNodeWithTag("PackManagerScreen").assertIsDisplayed()
        composeRule.onNodeWithTag("PackManagerActiveCount").assertIsDisplayed()
        composeRule.onNodeWithText("📦 我的词包").assertIsDisplayed()
        composeRule.onNodeWithText("已激活 5 / 10").assertIsDisplayed()
        composeRule.onNodeWithText("固定：防止满分自动轮换 · 开关：切换激活").assertIsDisplayed()
        composeRule.onNodeWithText("🔄 同步词包").assertIsDisplayed()
        composeRule.onNodeWithTag("PackSourceTag_fruit-forest").assertIsDisplayed()
        composeRule.onNodeWithText("Fruit Forest").assertIsDisplayed()
        composeRule.onNodeWithTag("PackPin_fruit-forest").assertIsDisplayed()
        assert(composeRule.onAllNodesWithText("水果森林 · 内置 · 藤蔓和果香里的第一场魔法单词冒险。").fetchSemanticsNodes().isEmpty())
        composeRule.onNodeWithTag("PackToggle_fruit-forest").performClick()
        composeRule.onNodeWithTag("PackToggle_fruit-forest").performClick()
        composeRule.onNodeWithTag("PackManagerBack").performClick()
        composeRule.onNodeWithTag("HomeScreen").assertIsDisplayed()
    }

    @Test
    fun wishlistRedeemWritesHistory() {
        composeRule.onNodeWithTag("HomeWishlistButton").performClick()
        composeRule.onNodeWithTag("WishlistScreen").assertIsDisplayed()
        composeRule.onNodeWithTag("WishRedeem_wish-ipad-20min").performClick()
        composeRule.onNodeWithTag("ParentPinScreen").assertIsDisplayed()
        composeRule.onNodeWithTag("ParentPinInput").performTextInput("123456")
        composeRule.onNodeWithTag("WishlistScreen").assertIsDisplayed()
        composeRule.waitUntil(2_000) {
            composeRule.onAllNodesWithTag("WishlistGiftBoxModal").fetchSemanticsNodes().isNotEmpty()
        }
        composeRule.onNodeWithTag("WishlistGiftBoxModal").assertIsDisplayed()
        composeRule.mainClock.advanceTimeBy(4_000)
        composeRule.waitUntil(2_000) {
            composeRule.onAllNodesWithTag("WishlistGiftBoxModal").fetchSemanticsNodes().isEmpty()
        }
        composeRule.onNodeWithTag("WishlistHistoryButton").performClick()
        composeRule.onNodeWithTag("RedemptionHistoryScreen").assertIsDisplayed()
        composeRule.onNodeWithTag("RedemptionHistoryTitle").assertIsDisplayed()
        composeRule.onNodeWithText("看 iPad 20 分钟").assertIsDisplayed()
    }

    @Test
    fun codexAndTodayPlanAndReportOpen() {
        composeRule.onNodeWithTag("HomeCodexButton").performClick()
        composeRule.onNodeWithTag("MonsterCodexScreen").assertIsDisplayed()
        composeRule.onNodeWithTag("MonsterCodexPrevious")
            .assertWidthIsEqualTo(56.dp)
            .assertHeightIsEqualTo(56.dp)
            .assertIsNotEnabled()
        composeRule.onNodeWithTag("MonsterCodexNext")
            .assertWidthIsEqualTo(56.dp)
            .assertHeightIsEqualTo(56.dp)
            .assertIsEnabled()
        assert(composeRule.onAllNodesWithText("返回").fetchSemanticsNodes().isEmpty())
        composeRule.onNodeWithText("⬅️").assertIsDisplayed()
        composeRule.onNodeWithText("➡️").assertIsDisplayed()
        composeRule.onNodeWithTag("CodexAvatar").assertIsDisplayed()
        composeRule.onNodeWithTag("CodexName").assertIsDisplayed()
        composeRule.onNodeWithText("????").assertIsDisplayed()
        composeRule.onNodeWithTag("CodexKindLabel").assertIsDisplayed()
        composeRule.onNodeWithText("「????」").assertIsDisplayed()
        composeRule.onNodeWithTag("CodexPositionIndicator").assertIsDisplayed()
        composeRule.onNodeWithText("1 / 100").assertIsDisplayed()
        assert(composeRule.onAllNodesWithTag("CodexDefeatCount").fetchSemanticsNodes().isEmpty())
        assert(composeRule.onAllNodesWithTag("CodexReward50Button").fetchSemanticsNodes().isEmpty())
        assert(composeRule.onAllNodesWithTag("CodexReward100Button").fetchSemanticsNodes().isEmpty())
        composeRule.onNodeWithTag("MonsterCodexNext").performClick()
        composeRule.onNodeWithTag("MonsterCodexName").assertIsDisplayed()
        composeRule.onNodeWithTag("MonsterCodexBack").performClick()

        composeRule.onNodeWithTag("HomePlanButton").performClick()
        composeRule.onNodeWithTag("TodayPlanScreen").assertIsDisplayed()
        composeRule.onNodeWithTag("TodayPlanReportButton").performClick()
        composeRule.onNodeWithTag("LearningReportScreen").assertIsDisplayed()
        composeRule.onNodeWithTag("LearningReportAccuracy").assertIsDisplayed()
    }

    @Test
    fun codexShowsEncounteredRewardStatesAndClaimsCapFreeCoins() {
        relaunchWithSeededProgress(
            progressJson = """{"version":1,"records":[{"catalogIndex":1,"encountered":true,"defeatCount":100,"claimedMilestones":[]}]}""",
            coinBalance = 0,
            earnedByDay = "2026-06-05\t20",
        )

        composeRule.onNodeWithTag("HomeCodexButton").performClick()
        composeRule.onNodeWithTag("MonsterCodexScreen").assertIsDisplayed()
        composeRule.onNodeWithTag("CodexName").assertIsDisplayed()
        composeRule.onNodeWithText("软泥小灵").assertIsDisplayed()
        composeRule.onNodeWithText("「普通怪物」").assertIsDisplayed()
        composeRule.onNodeWithTag("CodexDefeatCount").assertIsDisplayed()
        composeRule.onNodeWithText("击败 100 次").assertIsDisplayed()
        composeRule.onNodeWithTag("CodexDescription").assertIsDisplayed()
        composeRule.onNodeWithTag("CodexReward50Button").assertIsEnabled()
        composeRule.onNodeWithTag("CodexReward100Button").assertIsEnabled()

        composeRule.onNodeWithTag("CodexReward50Button").performClick()
        composeRule.onNodeWithTag("CodexReward50Button").assertIsNotEnabled()
        composeRule.onNodeWithText("已领 50 金币").assertIsDisplayed()
        composeRule.onNodeWithTag("CodexReward100Button").performClick()
        composeRule.onNodeWithTag("CodexReward100Button").assertIsNotEnabled()
        composeRule.onNodeWithText("已领 100 金币").assertIsDisplayed()
        composeRule.onNodeWithTag("MonsterCodexBack").performClick()
        composeRule.onNodeWithTag("HomeCoinBalance").assertIsDisplayed()
        composeRule.onNodeWithText("✨ 150").assertIsDisplayed()

        val prefs = targetContext.getSharedPreferences("wordmagic-local-progress", Context.MODE_PRIVATE)
        assert(prefs.getString("coinEarnedByDay", "") == "2026-06-05\t20")
        assert(prefs.getString("coinTransactions", "") == "monster-codex:50:1\t50\t50\nmonster-codex:100:1\t100\t150")
        val persisted = prefs.getString("monster_progress/snapshot_v1", "").orEmpty()
        assert(persisted.contains(""""claimedMilestones":[50,100]"""))
    }

    @Test
    fun reviewToolbarExcludesSameDayWrongWordAndShowsToastWhenEmpty() {
        composeRule.onNodeWithTag("HomeReviewButton").performClick()
        composeRule.onNodeWithTag("HomeReviewEmptyToast").assertIsDisplayed()
        composeRule.onNodeWithTag("HomeScreen").assertIsDisplayed()

        configureChoiceOnly()
        composeRule.onNodeWithTag("HomeStartButton").performClick()
        composeRule.onNodeWithTag("BattleScreen").assertIsDisplayed()
        val seededWrongPrompt = currentFruitPrompt()
        answerVisibleWrongTextForPrompt(seededWrongPrompt)

        composeRule.waitUntil(timeoutMillis = 3_000) {
            runCatching {
                composeRule.onNodeWithTag("BattleEscapeButton").assertIsEnabled()
            }.isSuccess
        }
        composeRule.onNodeWithTag("BattleEscapeButton").performClick()
        composeRule.onNodeWithTag("ResultScreen").assertIsDisplayed()
        composeRule.onNodeWithTag("ResultHomeButton").performClick()
        composeRule.onNodeWithTag("HomeScreen").assertIsDisplayed()

        composeRule.onNodeWithTag("HomeReviewButton").performClick()
        composeRule.onNodeWithTag("HomeReviewEmptyToast").assertIsDisplayed()
        composeRule.onNodeWithTag("HomeScreen").assertIsDisplayed()
        assert(composeRule.onAllNodesWithText(seededWrongPrompt).fetchSemanticsNodes().isEmpty())
    }

    private fun configureChoiceOnly() {
        composeRule.onNodeWithTag("HomeConfigButton").performClick()
        composeRule.onNodeWithTag("ConfigQuestionType_fill-letter").performScrollTo().performClick()
        composeRule.onNodeWithTag("ConfigQuestionType_fill-letter-medium").performScrollTo().performClick()
        composeRule.onNodeWithTag("ConfigQuestionType_spell").performScrollTo().performClick()
        composeRule.onNodeWithTag("ConfigQuestionType_sentence-cloze").performScrollTo().performClick()
        composeRule.onNodeWithTag("ConfigBackButton").performClick()
        composeRule.waitUntil(timeoutMillis = 2_000) {
            composeRule.onAllNodesWithTag("HomeScreen").fetchSemanticsNodes().isNotEmpty()
        }
    }

    private fun currentFruitPrompt(): String {
        composeRule.waitUntil(timeoutMillis = 2_000) {
            fruitPromptToAnswer.keys.any { prompt ->
                composeRule.onAllNodesWithText(prompt).fetchSemanticsNodes().isNotEmpty()
            }
        }
        return fruitPromptToAnswer.keys.first { prompt ->
            composeRule.onAllNodesWithText(prompt).fetchSemanticsNodes().isNotEmpty()
        }
    }

    private fun answerVisibleWrongTextForPrompt(prompt: String) {
        val correct = fruitPromptToAnswer.getValue(prompt)
        composeRule.waitUntil(timeoutMillis = 2_000) {
            fruitPromptToAnswer.values.any { option ->
                option != correct && enabledClickableTextExists(option)
            }
        }
        val wrong = fruitPromptToAnswer.values.first { option ->
            option != correct && enabledClickableTextExists(option)
        }
        composeRule.onNode(hasText(wrong) and hasClickAction() and isEnabled()).performClick()
    }

    private fun enabledClickableTextExists(text: String): Boolean =
        composeRule.onAllNodes(hasText(text) and hasClickAction() and isEnabled())
            .fetchSemanticsNodes()
            .isNotEmpty()

    private fun clearLocalProgress() {
        targetContext.getSharedPreferences("wordmagic-local-progress", Context.MODE_PRIVATE)
            .edit()
            .clear()
            .commit()
    }

    private fun relaunchWithSeededProgress(progressJson: String, coinBalance: Int, earnedByDay: String) {
        scenario?.close()
        clearLocalProgress()
        targetContext.getSharedPreferences("wordmagic-local-progress", Context.MODE_PRIVATE)
            .edit()
            .putString("monster_progress/snapshot_v1", progressJson)
            .putInt("coinBalance", coinBalance)
            .putString("coinEarnedByDay", earnedByDay)
            .commit()
        scenario = ActivityScenario.launch(MainActivity::class.java)
    }

    private companion object {
        val fruitPromptToAnswer = linkedMapOf(
            "苹果" to "apple",
            "香蕉" to "banana",
            "梨" to "pear",
            "橙子" to "orange",
            "葡萄" to "grape",
        )
    }
}
