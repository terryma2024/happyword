package cool.happyword.wordmagic

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertHeightIsEqualTo
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.dp
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class DeveloperRoutingFlowTest {
    @get:Rule
    val composeRule = createAndroidComposeRule<MainActivity>()

    private fun openDevMenuViaVersionTripleTap() {
        repeat(3) {
            composeRule.onNodeWithTag("HomeVersionLabel").performClick()
        }
    }

    @Test
    fun devMenuAppliesCardsAndPromptsPreviewSecret() {
        openDevMenuViaVersionTripleTap()
        composeRule.onNodeWithTag("DevMenuScreen").assertIsDisplayed()

        composeRule.onNodeWithText("Developer Options").assertIsDisplayed()
        composeRule.onNodeWithText("Backend environment (debug builds only)").assertIsDisplayed()
        composeRule.onNodeWithTag("DevMenuBackButton").assertIsDisplayed()
        composeRule.onNodeWithTag("DevMenuBypassSecretButton").assertIsDisplayed()
        composeRule.onNodeWithTag("DevMenuRefreshManifestButton").assertIsDisplayed()
        composeRule.onNodeWithTag("DevMenuLocalCard").assertHeightIsEqualTo(96.dp)
        composeRule.onNodeWithTag("DevMenuStagingCard").assertHeightIsEqualTo(96.dp)
        composeRule.onNodeWithText("http://10.0.2.2:8000").assertIsDisplayed()
        composeRule.onNodeWithText("https://happyword.cool").assertIsDisplayed()
        assertTrue(composeRule.onAllNodesWithTag("DevMenuPreviewRow_preview-main").fetchSemanticsNodes().isEmpty())
        assertTrue(composeRule.onAllNodesWithTag("DevMenuPreviewRow_preview-e2e").fetchSemanticsNodes().isEmpty())

        composeRule.onNodeWithTag("DevMenuBypassSecretButton").performClick()
        composeRule.onNodeWithTag("BypassSecretPageClearButton").performClick()
        composeRule.onNodeWithTag("DevMenuScreen").assertIsDisplayed()
        composeRule.onNodeWithTag("DevMenuLocalCard").performClick()
        composeRule.waitUntil(timeoutMillis = 2_000) {
            composeRule.onAllNodesWithTag("HomeScreen").fetchSemanticsNodes().isNotEmpty()
        }

        openDevMenuViaVersionTripleTap()
        composeRule.onNodeWithTag("DevMenuScreen").assertIsDisplayed()
        composeRule.onNodeWithTag("DevMenuRefreshManifestButton").assertIsDisplayed()
    }
}
