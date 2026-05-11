package cool.happyword.wordmagic

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextInput
import org.junit.Rule
import org.junit.Test

class CloudBindingFlowTest {
    @get:Rule
    val composeRule = createAndroidComposeRule<MainActivity>()

    @Test
    fun manualBindingSyncAndUnbindFlow() {
        composeRule.onNodeWithTag("HomeConfigButton").performClick()
        composeRule.onNodeWithTag("ConfigCloudBindingButton").performScrollTo().performClick()
        composeRule.waitUntil(timeoutMillis = 2_000) {
            hasNode("ScanBindingScreen") || hasNode("BoundDeviceInfoScreen")
        }
        if (hasNode("ScanBindingScreen")) {
            composeRule.onNodeWithTag("ScanBindingScreen").assertIsDisplayed()
            composeRule.onNodeWithTag("ScanBindingManualCodeInput").performTextInput("abc123")
            composeRule.onNodeWithTag("ScanBindingRedeemButton").performClick()
            composeRule.waitUntil(timeoutMillis = 2_000) {
                hasNode("BoundDeviceInfoScreen")
            }
        }

        composeRule.onNodeWithTag("BoundDeviceInfoScreen").assertIsDisplayed()
        composeRule.onNodeWithTag("BoundDeviceInfoNickname").assertIsDisplayed()
        composeRule.onNodeWithTag("BoundDeviceInfoManualSync").performClick()
        composeRule.onNodeWithTag("BoundDeviceInfoSyncStatus").assertIsDisplayed()
        composeRule.onNodeWithTag("BoundDeviceInfoUnbind").performClick()

        composeRule.onNodeWithTag("ParentPinScreen").assertIsDisplayed()
        composeRule.onNodeWithTag("ParentPinInput").performTextInput("123456")
        composeRule.onNodeWithTag("ConfigScreen").assertIsDisplayed()
    }

    private fun hasNode(tag: String): Boolean {
        return composeRule.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty()
    }
}
