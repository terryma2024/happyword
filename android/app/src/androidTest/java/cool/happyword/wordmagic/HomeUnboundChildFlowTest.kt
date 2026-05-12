package cool.happyword.wordmagic

import android.content.Context
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createEmptyComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import org.junit.Assert.assertTrue
import org.junit.After
import org.junit.Before
import org.junit.Rule
import org.junit.Test

class HomeUnboundChildFlowTest {
    @get:Rule
    val composeRule = createEmptyComposeRule()

    private lateinit var scenario: ActivityScenario<MainActivity>
    private val targetContext: Context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Before
    fun launchUnboundHome() {
        targetContext.getSharedPreferences("wordmagic-cloud", Context.MODE_PRIVATE)
            .edit()
            .clear()
            .apply()
        File(targetContext.filesDir, "cloud_device_token.secure").delete()
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
    fun unboundHomeDoesNotShowChildProfileBadge() {
        composeRule.onNodeWithTag("HomeScreen").assertIsDisplayed()
        assertTrue(composeRule.onAllNodesWithTag("HomeBoundChildBadge").fetchSemanticsNodes().isEmpty())
        composeRule.onNodeWithTag("HomeCoinBalance").assertIsDisplayed()
    }
}
