package cool.happyword.wordmagic

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import org.junit.Rule
import org.junit.Test

class SmokeTest {
    @get:Rule
    val composeRule = createAndroidComposeRule<MainActivity>()

    @Test
    fun homeScreenRendersAndCanOpenBattle() {
        composeRule.onNodeWithTag("HomeScreen").assertIsDisplayed()
        composeRule.onNodeWithText("Small Magician Word Adventure").assertIsDisplayed()
        composeRule.onNodeWithText("开始今日冒险").assertIsDisplayed()
        composeRule.onNodeWithTag("HomeStartButton").assertIsDisplayed()
    }

    @Test
    fun battleScreenUsesEnglishLabelsAndCountsDown() {
        composeRule.onNodeWithTag("HomeStartButton").performClick()
        composeRule.onNodeWithTag("BattleScreen").assertIsDisplayed()

        composeRule.onNodeWithText("Battle").assertIsDisplayed()
        composeRule.onNodeWithText("Combo 0").assertIsDisplayed()
        composeRule.waitUntil(timeoutMillis = 1_500) {
            composeRule.onAllNodesWithText("Time 5:00").fetchSemanticsNodes().isNotEmpty() ||
                composeRule.onAllNodesWithText("Time 4:59").fetchSemanticsNodes().isNotEmpty()
        }
        composeRule.onNodeWithText("Question").assertIsDisplayed()
        composeRule.onNodeWithText("Small Magician").assertIsDisplayed()
        composeRule.onNodeWithText("Word Monster").assertIsDisplayed()
        composeRule.onNodeWithText("Back").assertIsDisplayed()
        composeRule.onNodeWithTag("BattleSpeakerButton").assertIsDisplayed()

        composeRule.waitUntil(timeoutMillis = 2_500) {
            composeRule.onAllNodesWithText("Time 4:59").fetchSemanticsNodes().isNotEmpty()
        }
        composeRule.onNodeWithText("Time 4:59").assertIsDisplayed()
    }

    @Test
    fun battleAdvancesToNextWordAfterAnswer() {
        composeRule.onNodeWithTag("HomeStartButton").performClick()
        composeRule.onNodeWithTag("BattleScreen").assertIsDisplayed()
        composeRule.onNodeWithText("苹果").assertIsDisplayed()

        composeRule.onNodeWithText("apple").performClick()

        composeRule.waitUntil(timeoutMillis = 1_500) {
            composeRule.onAllNodesWithText("香蕉").fetchSemanticsNodes().isNotEmpty()
        }
        composeRule.onNodeWithText("香蕉").assertIsDisplayed()
    }
}
