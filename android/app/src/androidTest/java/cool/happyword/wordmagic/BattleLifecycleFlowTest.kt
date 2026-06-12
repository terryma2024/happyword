package cool.happyword.wordmagic

import android.content.Context
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createEmptyComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import cool.happyword.wordmagic.core.BuiltinPacks
import cool.happyword.wordmagic.cocos.forceNativeBattle
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
        // Keep the native BattleScreen exercised regardless of the stored Cocos
        // preference — CocosBattleActivity requires a real device with the Cocos
        // native libs loaded and is not suitable for in-process Compose tests.
        forceNativeBattle = true
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
        forceNativeBattle = false
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

    @Test
    fun restoredBattleContinuesToNextWordAfterAnswer() {
        val words = BuiltinPacks.all.first { it.id == "fruit-forest" }.words
        val first = words[0]
        val second = words[1]
        val third = words[2]

        scenario = ActivityScenario.launch(MainActivity::class.java)
        composeRule.waitUntil(timeoutMillis = 2_000) { hasTag("HomeScreen") }
        composeRule.onNodeWithTag("HomeStartButton").performClick()
        composeRule.waitUntil(timeoutMillis = 2_000) { hasTag("BattleScreen") && hasText(first.meaning) }
        composeRule.onNodeWithText(first.word).performClick()
        composeRule.waitUntil(timeoutMillis = 3_000) { hasText(second.meaning) }

        scenario?.close()
        scenario = ActivityScenario.launch(MainActivity::class.java)
        composeRule.waitUntil(timeoutMillis = 2_000) { hasTag("BattleScreen") && hasText(second.meaning) }
        composeRule.onNodeWithText(second.word).performClick()

        composeRule.waitUntil(timeoutMillis = 3_000) { hasText(third.meaning) }
        assertTrue(composeRule.onAllNodesWithText(first.meaning).fetchSemanticsNodes().isEmpty())
    }

    @Test
    fun finishedBattleReturnsHomeAfterAppBackgroundAndResume() {
        scenario = ActivityScenario.launch(MainActivity::class.java)
        composeRule.waitUntil(timeoutMillis = 2_000) { hasTag("HomeScreen") }
        composeRule.onNodeWithTag("HomeStartButton").performClick()
        composeRule.waitUntil(timeoutMillis = 2_000) { hasTag("BattleScreen") }
        composeRule.onNodeWithTag("BattleEscapeButton").performClick()
        composeRule.waitUntil(timeoutMillis = 2_000) { hasTag("ResultScreen") }

        scenario?.moveToState(Lifecycle.State.CREATED)
        scenario?.moveToState(Lifecycle.State.RESUMED)

        composeRule.waitUntil(timeoutMillis = 2_000) { hasTag("HomeScreen") }
        composeRule.onNodeWithTag("HomeScreen").assertIsDisplayed()
        assertTrue(composeRule.onAllNodesWithTag("ResultScreen").fetchSemanticsNodes().isEmpty())
    }

    private fun hasTag(tag: String): Boolean =
        composeRule.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty()

    private fun hasText(text: String): Boolean =
        composeRule.onAllNodesWithText(text).fetchSemanticsNodes().isNotEmpty()
}
