package cool.happyword.wordmagic

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextInput
import org.junit.Rule
import org.junit.Test

class DeveloperRoutingFlowTest {
    @get:Rule
    val composeRule = createAndroidComposeRule<MainActivity>()

    @Test
    fun devMenuSelectPreviewAndSaveBypassSecret() {
        composeRule.onNodeWithTag("HomeConfigButton").performClick()
        composeRule.onNodeWithTag("ConfigDeveloperRow").performScrollTo().performClick()
        composeRule.onNodeWithTag("DevMenuScreen").assertIsDisplayed()
        composeRule.onNodeWithTag("DevMenuRefreshManifestButton").performClick()
        composeRule.onNodeWithTag("DevMenuPreviewRow_preview-main").performClick()
        composeRule.onNodeWithTag("DevMenuRoutingDebug").assertIsDisplayed()
        composeRule.onNodeWithTag("DevMenuBypassSecretButton").performClick()
        composeRule.onNodeWithTag("BypassSecretPageInput").performTextInput("token-123")
        composeRule.onNodeWithTag("BypassSecretPageSaveButton").performClick()
        composeRule.onNodeWithTag("DevMenuScreen").assertIsDisplayed()
    }
}
