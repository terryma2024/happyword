package cool.happyword.wordmagic

import android.content.Context
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertTextContains
import androidx.compose.ui.test.junit4.v2.createEmptyComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextReplacement
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Rule
import org.junit.Test

class HomeBoundChildFlowTest {
    @get:Rule
    val composeRule = createEmptyComposeRule()

    private lateinit var scenario: ActivityScenario<MainActivity>
    private val targetContext: Context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Before
    fun seedBoundChild() {
        targetContext.getSharedPreferences("wordmagic-cloud", Context.MODE_PRIVATE)
            .edit()
            .clear()
            .putString("device_id", "device-home-child-0001")
            .putString("binding_id", "bind-home-child-0001")
            .putString("child_nickname", "星星")
            .putString("avatar_emoji", "🦄")
            .putString("family_label", "fam-home-child")
            .putString("child_profile_id", "child-home-child-0001")
            .putString("paired_at_ms", "1715526545000")
            .putString("device_id_source", "preferences_fallback")
            .apply()
        File(targetContext.filesDir, "cloud_device_token.secure").apply {
            parentFile?.mkdirs()
            writeText("device.jwt.token")
        }
        scenario = ActivityScenario.launch(MainActivity::class.java)
    }

    @After
    fun cleanup() {
        scenario.close()
        targetContext.getSharedPreferences("wordmagic-cloud", Context.MODE_PRIVATE)
            .edit()
            .clear()
            .apply()
        File(targetContext.filesDir, "cloud_device_token.secure").delete()
    }

    @Test
    fun boundChildBadgeShowsStoredNicknameAndOpensEditableProfile() {
        composeRule.onNodeWithTag("HomeBoundChildBadge")
            .assertIsDisplayed()
        composeRule.onNodeWithText("🦄 星星").assertIsDisplayed()

        composeRule.onNodeWithTag("HomeBoundChildBadge").performClick()
        composeRule.onNodeWithTag("BoundDeviceInfoScreen").assertIsDisplayed()
        composeRule.onNodeWithTag("BoundDeviceInfoNicknameValue")
            .assertIsDisplayed()
        composeRule.onNodeWithText("🦄 星星").assertIsDisplayed()
        composeRule.onNodeWithText("家长账户").assertIsDisplayed()
        composeRule.onNodeWithText("Family ID").assertIsDisplayed()
        composeRule.onNodeWithText("fam-home-child").assertIsDisplayed()
        composeRule.onNodeWithText("Binding ID").assertIsDisplayed()
        composeRule.onNodeWithText("bind-home-child-0001").assertIsDisplayed()
        composeRule.onNodeWithText("Device ID 末四位").assertIsDisplayed()
        composeRule.onNodeWithText("0001").assertIsDisplayed()
        composeRule.onNodeWithText("Device ID 来源").assertIsDisplayed()
        composeRule.onNodeWithText("本地 preferences (重装即丢)").assertIsDisplayed()
        composeRule.onNodeWithText("绑定时间").assertIsDisplayed()
        composeRule.onNodeWithTag("BoundDeviceInfoUnbind").performScrollTo().assertIsDisplayed()
        assertEquals(0, composeRule.onAllNodesWithTag("BoundDeviceInfoManualSync").fetchSemanticsNodes().size)
        composeRule.onNodeWithTag("BoundDeviceInfoNicknameEditButton").performClick()
        composeRule.onNodeWithTag("EditChildNicknameDialog").assertIsDisplayed()
        composeRule.onNodeWithTag("EditChildNicknameInput")
            .assertIsDisplayed()
            .performTextReplacement("月亮")
        composeRule.onNodeWithTag("EditChildNicknameInput").assertTextContains("月亮")
        listOf("🐰", "🦄", "🐻", "🦁", "🐼", "🦊", "🐶", "🐱", "🐨", "🐧").forEach { emoji ->
            composeRule.onNodeWithTag("EditChildNicknameEmoji_$emoji").assertIsDisplayed()
        }
        assertEquals(1, composeRule.onAllNodesWithTag("EditChildNicknameEmoji_🦄").fetchSemanticsNodes().size)
    }
}
