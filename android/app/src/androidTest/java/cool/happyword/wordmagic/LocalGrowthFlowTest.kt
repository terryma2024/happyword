package cool.happyword.wordmagic

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import org.junit.Rule
import org.junit.Test

class LocalGrowthFlowTest {
    @get:Rule
    val composeRule = createAndroidComposeRule<MainActivity>()

    @Test
    fun packManagerCanToggleAndReturnHome() {
        composeRule.onNodeWithTag("HomePackManagerButton").performClick()
        composeRule.onNodeWithTag("PackManagerScreen").assertIsDisplayed()
        composeRule.onNodeWithTag("PackManagerActiveCount").assertIsDisplayed()
        composeRule.onNodeWithTag("PackToggle_fruit-forest").performClick()
        composeRule.onNodeWithTag("PackToggle_fruit-forest").performClick()
        composeRule.onNodeWithTag("PackManagerBack").performClick()
        composeRule.onNodeWithTag("HomeScreen").assertIsDisplayed()
    }

    @Test
    fun wishlistRedeemWritesHistory() {
        composeRule.onNodeWithTag("HomeWishlistButton").performClick()
        composeRule.onNodeWithTag("WishlistScreen").assertIsDisplayed()
        composeRule.onNodeWithTag("WishRedeem_sticker").performClick()
        composeRule.onNodeWithTag("ParentPinScreen").assertIsDisplayed()
        composeRule.onNodeWithTag("ParentPinInput").performTextInput("123456")
        composeRule.onNodeWithTag("WishlistScreen").assertIsDisplayed()
        composeRule.onNodeWithTag("WishlistHistoryButton").performClick()
        composeRule.onNodeWithTag("RedemptionHistoryScreen").assertIsDisplayed()
    }

    @Test
    fun codexAndTodayPlanAndReportOpen() {
        composeRule.onNodeWithTag("HomeCodexButton").performClick()
        composeRule.onNodeWithTag("MonsterCodexScreen").assertIsDisplayed()
        composeRule.onNodeWithTag("MonsterCodexNext").performClick()
        composeRule.onNodeWithTag("MonsterCodexName").assertIsDisplayed()
        composeRule.onNodeWithTag("MonsterCodexBack").performClick()

        composeRule.onNodeWithTag("HomeTodayPlanButton").performClick()
        composeRule.onNodeWithTag("TodayPlanScreen").assertIsDisplayed()
        composeRule.onNodeWithTag("TodayPlanReportButton").performClick()
        composeRule.onNodeWithTag("LearningReportScreen").assertIsDisplayed()
        composeRule.onNodeWithTag("LearningReportTotalWords").assertIsDisplayed()
    }
}
