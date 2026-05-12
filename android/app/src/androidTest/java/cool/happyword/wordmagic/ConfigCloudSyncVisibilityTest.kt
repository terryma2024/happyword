package cool.happyword.wordmagic

import android.content.Context
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createEmptyComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import org.junit.After
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class ConfigCloudSyncVisibilityTest {
    @get:Rule
    val composeRule = createEmptyComposeRule()

    private var scenario: ActivityScenario<MainActivity>? = null
    private val targetContext: Context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    @After
    fun cleanup() {
        scenario?.close()
        scenario = null
        targetContext.getSharedPreferences("wordmagic-cloud", Context.MODE_PRIVATE)
            .edit()
            .clear()
            .apply()
        File(targetContext.filesDir, "cloud_device_token.secure").delete()
    }

    @Test
    fun configNeverShowsSeparateCloudPackSyncEntry() {
        launchWithBinding(bound = false)
        openConfig()
        assertTrue(composeRule.onAllNodesWithTag("ConfigCloudPackSyncButton").fetchSemanticsNodes().isEmpty())
        assertTrue(composeRule.onAllNodesWithTag("ConfigCloudSyncButton").fetchSemanticsNodes().isEmpty())
        composeRule.onNodeWithTag("ConfigPackManagerButton").performScrollTo().performClick()
        composeRule.onNodeWithTag("PackManagerSyncButton").assertExists()
        scenario?.close()

        launchWithBinding(bound = true)
        openConfig()
        assertTrue(composeRule.onAllNodesWithTag("ConfigCloudPackSyncButton").fetchSemanticsNodes().isEmpty())
        assertTrue(composeRule.onAllNodesWithTag("ConfigCloudPackSyncRow").fetchSemanticsNodes().isEmpty())
        composeRule.onNodeWithTag("ConfigCloudSyncButton").performScrollTo().assertIsDisplayed()
        composeRule.onNodeWithTag("ConfigPackManagerButton").performScrollTo().performClick()
        composeRule.onNodeWithTag("PackManagerSyncButton").assertExists()
    }

    private fun launchWithBinding(bound: Boolean) {
        targetContext.getSharedPreferences("wordmagic-cloud", Context.MODE_PRIVATE)
            .edit()
            .clear()
            .apply()
        File(targetContext.filesDir, "cloud_device_token.secure").delete()
        if (bound) {
            targetContext.getSharedPreferences("wordmagic-cloud", Context.MODE_PRIVATE)
                .edit()
                .putString("device_id", "device-config-child-0001")
                .putString("binding_id", "bind-config-child-0001")
                .putString("child_nickname", "星星")
                .putString("avatar_emoji", "🦄")
                .putString("family_label", "fam-config")
                .apply()
            File(targetContext.filesDir, "cloud_device_token.secure").apply {
                parentFile?.mkdirs()
                writeText("device.jwt.token")
            }
        }
        scenario = ActivityScenario.launch(MainActivity::class.java)
    }

    private fun openConfig() {
        composeRule.onNodeWithTag("HomeConfigButton").performClick()
        composeRule.onNodeWithTag("ConfigScreen").assertIsDisplayed()
    }
}
