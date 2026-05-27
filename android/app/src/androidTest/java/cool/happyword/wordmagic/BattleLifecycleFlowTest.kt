package cool.happyword.wordmagic

import android.content.Context
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createEmptyComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.After
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test

class BattleLifecycleFlowTest {
    @get:Rule
    val composeRule = createEmptyComposeRule()

    private var scenario: ActivityScenario<MainActivity>? = null
    private val targetContext: Context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Before
    fun clearLocalProgress() {
        targetContext
            .getSharedPreferences("wordmagic-local-progress", Context.MODE_PRIVATE)
            .edit()
            .clear()
            .commit()
    }

    @After
    fun cleanup() {
        scenario?.close()
        scenario = null
        clearLocalProgress()
    }

    @Test
    fun unfinishedBattleRestoresAfterFreshLauncherActivity() {
        scenario = ActivityScenario.launch(MainActivity::class.java)
        composeRule.waitUntil(timeoutMillis = 2_000) { hasTag("HomeScreen") }
        composeRule.onNodeWithTag("HomeStartButton").performClick()
        composeRule.waitUntil(timeoutMillis = 2_000) { hasTag("BattleScreen") }
        composeRule.onNodeWithTag("BattleScreen").assertIsDisplayed()

        scenario?.close()
        scenario = ActivityScenario.launch(MainActivity::class.java)

        composeRule.waitUntil(timeoutMillis = 2_000) { hasTag("BattleScreen") }
        composeRule.onNodeWithTag("BattleScreen").assertIsDisplayed()
        assertTrue(composeRule.onAllNodesWithTag("HomeScreen").fetchSemanticsNodes().isEmpty())
    }

    private fun hasTag(tag: String): Boolean =
        composeRule.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty()
}
