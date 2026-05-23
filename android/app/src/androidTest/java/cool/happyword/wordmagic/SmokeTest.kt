package cool.happyword.wordmagic

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertHeightIsEqualTo
import androidx.compose.ui.test.assertWidthIsEqualTo
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isEnabled
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.printToString
import androidx.compose.ui.unit.dp
import kotlin.math.abs
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class SmokeTest {
    @get:Rule
    val composeRule = createAndroidComposeRule<MainActivity>()

    @Test
    fun homeScreenRendersAndCanOpenBattle() {
        composeRule.onNodeWithTag("HomeScreen").assertIsDisplayed()
        composeRule.onNodeWithText("Small Magician Word Adventure").assertIsDisplayed()
        composeRule.onNodeWithText("开始今日冒险").assertIsDisplayed()
        composeRule.onNodeWithTag("HomeStartButton").assertIsDisplayed()
    }

    @Test
    fun homeToolbarMatchesHarmonyBaseline() {
        composeRule.onNodeWithTag("HomeVersionLabel").assertIsDisplayed()
        composeRule.onNodeWithTag("HomeCoinBalance").assertIsDisplayed()

        composeRule.onNodeWithTag("HomeReviewButton").assertWidthIsEqualTo(56.dp).assertHeightIsEqualTo(56.dp)
        composeRule.onNodeWithTag("HomeCodexButton").assertWidthIsEqualTo(56.dp).assertHeightIsEqualTo(56.dp)
        composeRule.onNodeWithTag("HomePlanButton").assertWidthIsEqualTo(56.dp).assertHeightIsEqualTo(56.dp)
        composeRule.onNodeWithTag("HomeWishlistButton").assertWidthIsEqualTo(56.dp).assertHeightIsEqualTo(56.dp)
        composeRule.onNodeWithTag("HomeConfigButton").assertWidthIsEqualTo(56.dp).assertHeightIsEqualTo(56.dp)

        composeRule.onNodeWithContentDescription("今日计划").assertIsDisplayed()
    }

    @Test
    fun lockedReviewToolbarButtonShowsHarmonyToast() {
        composeRule.onNodeWithTag("HomeReviewButton").performClick()

        composeRule.onNodeWithTag("HomeReviewLockedToast").assertIsDisplayed()
    }

    @Test
    fun homePackChipsAreCenteredLikeHarmony() {
        val rowBounds = composeRule.onNodeWithTag("PackChipRow").fetchSemanticsNode().boundsInRoot
        val chipBounds = listOf(
            "RegionChip_school-castle",
            "RegionChip_ocean-realm",
            "RegionChip_home-cottage",
            "RegionChip_fruit-forest",
            "RegionChip_animal-safari",
        ).map { tag -> composeRule.onNodeWithTag(tag).fetchSemanticsNode().boundsInRoot }

        val leftGap = chipBounds.minOf { it.left } - rowBounds.left
        val rightGap = rowBounds.right - chipBounds.maxOf { it.right }

        assertTrue(
            "Pack chips should be centered: leftGap=$leftGap rightGap=$rightGap",
            abs(leftGap - rightGap) < 32f,
        )
    }

    @Test
    fun battleScreenUsesEnglishLabelsAndCountsDown() {
        composeRule.onNodeWithTag("HomeStartButton").performClick()
        composeRule.onNodeWithTag("BattleScreen").assertIsDisplayed()

        composeRule.onNodeWithText("Battle").assertIsDisplayed()
        composeRule.onNodeWithText("Combo 0").assertIsDisplayed()
        composeRule.waitUntil(timeoutMillis = 1_500) {
            composeRule.onAllNodesWithText("Time 5:00").fetchSemanticsNodes().isNotEmpty() ||
                composeRule.onAllNodesWithText("Time 4:59").fetchSemanticsNodes().isNotEmpty()
        }
        composeRule.onNodeWithText("Question").assertIsDisplayed()
        composeRule.onNodeWithText("Small Magician").assertIsDisplayed()
        composeRule.onNodeWithText("Word Monster").assertIsDisplayed()
        composeRule.onNodeWithText("Escape").assertIsDisplayed()
        composeRule.onNodeWithTag("BattleSpeakerButton").assertIsDisplayed()

        composeRule.waitUntil(timeoutMillis = 2_500) {
            composeRule.onAllNodesWithText("Time 4:59").fetchSemanticsNodes().isNotEmpty()
        }
        composeRule.onNodeWithText("Time 4:59").assertIsDisplayed()
    }

    @Test
    fun battleAdvancesToNextWordAfterAnswer() {
        configureChoiceOnly()
        composeRule.onNodeWithTag("HomeStartButton").performClick()
        composeRule.onNodeWithTag("BattleScreen").assertIsDisplayed()
        val firstPrompt = currentFruitPrompt()
        composeRule.onNodeWithText(firstPrompt).assertIsDisplayed()

        answerVisibleText(fruitPromptToAnswer.getValue(firstPrompt))

        composeRule.waitUntil(timeoutMillis = 1_500) {
            fruitPromptToAnswer.keys.any { prompt ->
                prompt != firstPrompt && composeRule.onAllNodesWithText(prompt).fetchSemanticsNodes().isNotEmpty()
            }
        }
        assertTrue(
            fruitPromptToAnswer.keys.any { prompt ->
                prompt != firstPrompt && composeRule.onAllNodesWithText(prompt).fetchSemanticsNodes().isNotEmpty()
            },
        )
    }

    @Test
    fun bossSpellQuestionUsesHarmonyInlineSpellingArea() {
        configureSpellOnly()
        composeRule.onNodeWithTag("HomeStartButton").performClick()
        composeRule.onNodeWithTag("BattleScreen").assertIsDisplayed()

        composeRule.waitUntil(timeoutMillis = 2_000) {
            composeRule.onAllNodesWithTag("BattleSpellArea").fetchSemanticsNodes().isNotEmpty()
        }
        composeRule.onNodeWithText("Question").assertIsDisplayed()
        assertFalse(composeRule.onAllNodesWithText("Spell").fetchSemanticsNodes().isNotEmpty())
        composeRule.onNodeWithTag("BattleSpellArea").assertIsDisplayed()
        composeRule.onNodeWithTag("BattleSpellSlot_0").assertIsDisplayed()
        composeRule.onNodeWithTag("BattleSpellPool_0").assertIsDisplayed()
        composeRule.onNodeWithTag("BattleOptionsRow_SpellPlaceholder").assertIsDisplayed()
    }

    private fun configureChoiceOnly() {
        composeRule.onNodeWithTag("HomeConfigButton").performClick()
        composeRule.onNodeWithTag("ConfigQuestionType_fill-letter").performScrollTo().performClick()
        composeRule.onNodeWithTag("ConfigQuestionType_fill-letter-medium").performScrollTo().performClick()
        composeRule.onNodeWithTag("ConfigQuestionType_spell").performScrollTo().performClick()
        composeRule.onNodeWithTag("ConfigBackButton").performClick()
        composeRule.waitUntil(timeoutMillis = 2_000) {
            composeRule.onAllNodesWithText("Small Magician Word Adventure").fetchSemanticsNodes().isNotEmpty()
        }
    }

    private fun configureSpellOnly() {
        composeRule.onNodeWithTag("HomeConfigButton").performClick()
        composeRule.onNodeWithTag("ConfigQuestionType_choice").performScrollTo().performClick()
        composeRule.onNodeWithTag("ConfigQuestionType_fill-letter").performScrollTo().performClick()
        composeRule.onNodeWithTag("ConfigQuestionType_fill-letter-medium").performScrollTo().performClick()
        composeRule.onNodeWithTag("ConfigBackButton").performClick()
        composeRule.waitUntil(timeoutMillis = 2_000) {
            composeRule.onAllNodesWithText("Small Magician Word Adventure").fetchSemanticsNodes().isNotEmpty()
        }
    }

    private fun answerVisibleText(text: String) {
        try {
            composeRule.waitUntil(timeoutMillis = 2_000) {
                enabledClickableTextExists(text)
            }
        } catch (error: Throwable) {
            throw AssertionError("Timed out waiting for text <$text>.\n${composeRule.onRoot(useUnmergedTree = true).printToString()}", error)
        }
        composeRule.onNode(hasText(text) and hasClickAction() and isEnabled()).performClick()
    }

    private fun enabledClickableTextExists(text: String): Boolean {
        return composeRule.onAllNodes(hasText(text) and hasClickAction() and isEnabled())
            .fetchSemanticsNodes()
            .isNotEmpty()
    }

    private fun currentFruitPrompt(): String {
        composeRule.waitUntil(timeoutMillis = 2_000) {
            fruitPromptToAnswer.keys.any { prompt -> composeRule.onAllNodesWithText(prompt).fetchSemanticsNodes().isNotEmpty() }
        }
        return fruitPromptToAnswer.keys.first { prompt ->
            composeRule.onAllNodesWithText(prompt).fetchSemanticsNodes().isNotEmpty()
        }
    }

    private companion object {
        val fruitPromptToAnswer = linkedMapOf(
            "苹果" to "apple",
            "香蕉" to "banana",
            "梨" to "pear",
            "橙子" to "orange",
            "葡萄" to "grape",
        )
    }
}
