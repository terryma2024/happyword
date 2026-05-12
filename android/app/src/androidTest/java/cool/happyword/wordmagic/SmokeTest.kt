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
        composeRule.onNodeWithTag("HomeBoundChildBadge").assertIsDisplayed()
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
        composeRule.onNodeWithText("Back").assertIsDisplayed()
        composeRule.onNodeWithTag("BattleSpeakerButton").assertIsDisplayed()

        composeRule.waitUntil(timeoutMillis = 2_500) {
            composeRule.onAllNodesWithText("Time 4:59").fetchSemanticsNodes().isNotEmpty()
        }
        composeRule.onNodeWithText("Time 4:59").assertIsDisplayed()
    }

    @Test
    fun battleAdvancesToNextWordAfterAnswer() {
        composeRule.onNodeWithTag("HomeStartButton").performClick()
        composeRule.onNodeWithTag("BattleScreen").assertIsDisplayed()
        composeRule.onNodeWithText("苹果").assertIsDisplayed()

        composeRule.onNodeWithText("apple").performClick()

        composeRule.waitUntil(timeoutMillis = 1_500) {
            composeRule.onAllNodesWithText("香蕉").fetchSemanticsNodes().isNotEmpty()
        }
        composeRule.onNodeWithText("香蕉").assertIsDisplayed()
    }

    @Test
    fun bossSpellQuestionUsesHarmonyInlineSpellingArea() {
        configureOneHitMonsters()
        composeRule.onNodeWithTag("HomeStartButton").performClick()
        composeRule.onNodeWithTag("BattleScreen").assertIsDisplayed()

        answerVisibleText("apple")
        waitForBattleFeedback()
        answerFirstVisibleText(listOf("a", "n"))
        waitForBattleFeedback()
        answerFirstVisibleText(listOf("e", "a", "r"))
        waitForBattleStepFeedback()
        answerFirstVisibleText(listOf("e", "a", "r"))
        waitForBattleFeedback()
        answerVisibleText("orange")

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

    private fun configureOneHitMonsters() {
        composeRule.onNodeWithTag("HomeConfigButton").performClick()
        repeat(20) {
            composeRule.onNodeWithTag("ConfigMonsterHpDecrement").performScrollTo().performClick()
        }
        repeat(20) {
            composeRule.onNodeWithTag("ConfigMonsterCountDecrement").performScrollTo().performClick()
        }
        repeat(4) {
            composeRule.onNodeWithTag("ConfigMonsterCountIncrement").performScrollTo().performClick()
        }
        composeRule.onNodeWithText("返回首页").performClick()
        composeRule.waitUntil(timeoutMillis = 2_000) {
            composeRule.onAllNodesWithText("Small Magician Word Adventure").fetchSemanticsNodes().isNotEmpty()
        }
        composeRule.onNodeWithTag("RegionChip_fruit-forest").performClick()
    }

    private fun answerFirstVisibleText(candidates: List<String>) {
        composeRule.waitUntil(timeoutMillis = 2_000) {
            candidates.any { text -> enabledClickableTextExists(text) }
        }
        val text = candidates.first { enabledClickableTextExists(it) }
        composeRule.onNode(hasText(text) and hasClickAction() and isEnabled()).performClick()
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

    private fun waitForBattleFeedback() {
        Thread.sleep(750)
        composeRule.waitForIdle()
    }

    private fun waitForBattleStepFeedback() {
        Thread.sleep(750)
        composeRule.waitForIdle()
    }
}
