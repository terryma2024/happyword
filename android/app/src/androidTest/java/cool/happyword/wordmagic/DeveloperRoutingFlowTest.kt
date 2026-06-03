package cool.happyword.wordmagic

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertHeightIsEqualTo
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
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
    fun devMenuLaunchesPeerToolsAndDomainSwitchOwnsBackendRouting() {
        openDevMenuViaVersionTripleTap()
        composeRule.onNodeWithTag("DevMenuScreen").assertIsDisplayed()

        composeRule.onNodeWithText("Developer Options").assertIsDisplayed()
        composeRule.onNodeWithTag("DevMenuBackButton").assertIsDisplayed()
        composeRule.onNodeWithTag("DevMenuDomainSwitchButton").assertIsDisplayed()
        composeRule.onNodeWithTag("DevMenuAudioLabButton").assertIsDisplayed()
        composeRule.onNodeWithTag("DevMenuMessageBubbleLabButton").assertIsDisplayed()

        composeRule.onNodeWithTag("DevMenuAudioLabButton").performClick()
        composeRule.onNodeWithTag("PcmAudioLabTitle").assertIsDisplayed()
        composeRule.onNodeWithText("Mix").assertIsDisplayed()
        composeRule.onNodeWithText("Transport").assertIsDisplayed()
        composeRule.onNodeWithText("PCM Voice").assertIsDisplayed()
        composeRule.onNodeWithText("SFX During Voice").assertIsDisplayed()
        composeRule.onNodeWithText("Status").assertIsDisplayed()
        composeRule.onNodeWithText("Speak over BGM").assertIsDisplayed()
        composeRule.onNodeWithText("BGM duck").assertIsDisplayed()
        assertTrue(composeRule.onAllNodesWithText("System TTS").fetchSemanticsNodes().isEmpty())
        composeRule.onNodeWithTag("PcmAudioLabBackButton").performClick()

        composeRule.onNodeWithTag("DevMenuDomainSwitchButton").performClick()
        composeRule.onNodeWithTag("DomainSwitchScreen").assertIsDisplayed()
        composeRule.onNodeWithText("Backend environment (debug builds only)").assertIsDisplayed()
        composeRule.onNodeWithTag("DomainSwitchBackButton").assertIsDisplayed()
        composeRule.onNodeWithTag("DevMenuBypassSecretButton").assertIsDisplayed()
        composeRule.onNodeWithTag("DevMenuRefreshManifestButton").assertIsDisplayed()
        composeRule.onNodeWithTag("DevMenuLocalCard").assertHeightIsEqualTo(96.dp)
        composeRule.onNodeWithTag("DevMenuStagingCard").assertHeightIsEqualTo(96.dp)
        composeRule.onNodeWithText("http://10.0.2.2:8000").assertIsDisplayed()
        composeRule.onNodeWithText("https://happyword.com.cn").assertIsDisplayed()
        assertTrue(composeRule.onAllNodesWithTag("DevMenuPreviewRow_preview-main").fetchSemanticsNodes().isEmpty())
        assertTrue(composeRule.onAllNodesWithTag("DevMenuPreviewRow_preview-e2e").fetchSemanticsNodes().isEmpty())

        composeRule.onNodeWithTag("DevMenuBypassSecretButton").performClick()
        composeRule.onNodeWithTag("BypassSecretPageClearButton").performClick()
        composeRule.onNodeWithTag("DomainSwitchScreen").assertIsDisplayed()
        composeRule.onNodeWithTag("DevMenuLocalCard").performClick()
        composeRule.waitUntil(timeoutMillis = 2_000) {
            composeRule.onAllNodesWithTag("HomeScreen").fetchSemanticsNodes().isNotEmpty()
        }

        openDevMenuViaVersionTripleTap()
        composeRule.onNodeWithTag("DevMenuScreen").assertIsDisplayed()
        composeRule.onNodeWithTag("DevMenuDomainSwitchButton").performClick()
        composeRule.onNodeWithTag("DevMenuRefreshManifestButton").assertIsDisplayed()
    }
}
