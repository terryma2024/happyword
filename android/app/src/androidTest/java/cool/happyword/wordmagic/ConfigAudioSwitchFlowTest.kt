package cool.happyword.wordmagic

import android.content.Context
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsOff
import androidx.compose.ui.test.assertIsOn
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Before
import org.junit.Rule
import org.junit.Test

class ConfigAudioSwitchFlowTest {
    @get:Rule
    val composeRule = createAndroidComposeRule<MainActivity>()

    @Before
    fun resetLocalState() {
        val targetContext = InstrumentationRegistry.getInstrumentation().targetContext
        targetContext.getSharedPreferences("wordmagic-local-progress", Context.MODE_PRIVATE).edit().clear().commit()
        composeRule.runOnUiThread {
            composeRule.activity.recreate()
        }
        composeRule.waitUntil(timeoutMillis = 2_000) {
            composeRule.onAllNodesWithTag("HomeScreen").fetchSemanticsNodes().isNotEmpty()
        }
    }

    @Test
    fun configAudioAndQuestionTypeSwitchesMatchV010DefaultsAndToggleInPlace() {
        composeRule.onNodeWithTag("HomeConfigButton").performClick()
        composeRule.onNodeWithTag("ConfigScreen").assertIsDisplayed()

        composeRule.onNodeWithTag("ConfigAutoSpeakSwitch").performScrollTo().assertIsOn()
        composeRule.onNodeWithTag("ConfigPlayBgmSwitch").performScrollTo().assertIsOff()
        composeRule.onNodeWithTag("ConfigActionSfxSwitch").performScrollTo().assertIsOn()

        composeRule.onNodeWithTag("ConfigPlayBgmSwitch").performScrollTo().performClick()
        composeRule.onNodeWithTag("ConfigActionSfxSwitch").performScrollTo().performClick()
        composeRule.onNodeWithTag("ConfigPlayBgmSwitch").performScrollTo().assertIsOn()
        composeRule.onNodeWithTag("ConfigActionSfxSwitch").performScrollTo().assertIsOff()

        composeRule.onNodeWithTag("ConfigQuestionType_spell").performScrollTo().assertIsOn()
        composeRule.onNodeWithTag("ConfigQuestionType_spell").performClick()
        composeRule.onNodeWithTag("ConfigQuestionType_spell").assertIsOff()
    }
}
