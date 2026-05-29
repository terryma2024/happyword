package cool.happyword.wordmagic.ui.home

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertTextContains
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import cool.happyword.wordmagic.core.BuiltinPacks
import cool.happyword.wordmagic.core.DailyHomeStatus
import org.junit.Rule
import org.junit.Test

class HomeDailyLearningUiTest {
    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun homeShowsPackStoryLineAndReviewCountBadge() {
        composeRule.setContent {
            HomeScreen(
                activePacks = BuiltinPacks.all.take(1),
                selectedPack = BuiltinPacks.all.first(),
                coins = 12,
                cloudCredentials = null,
                showDeveloperTools = false,
                homeVersionLabel = "",
                dailyStatus = DailyHomeStatus(
                    label = "请点击复习加战斗(2)",
                    remainingReviewCount = 2,
                    showReviewCountBadge = true,
                    reviewAvailable = true,
                ),
                onDeveloperVersionTripleTap = {},
                onSelectPack = {},
                onBoundChild = {},
                onStart = {},
                onReview = { true },
                onPackManager = {},
                onWishlist = {},
                onMonsterCodex = {},
                onTodayPlan = {},
                onConfig = {},
            )
        }

        composeRule.onNodeWithTag("AdventureCardStoryLine")
            .assertIsDisplayed()
            .assertTextContains("Tiny lanterns glow as fruit friends guide each new word.")
        composeRule.onNodeWithTag("HomeReviewCountBadge")
            .assertIsDisplayed()
            .assertTextContains("2")
        composeRule.onAllNodesWithText("常规").assertCountEquals(0)
        composeRule.onAllNodesWithText("拼写").assertCountEquals(0)
        composeRule.onAllNodesWithText("复习").assertCountEquals(0)
        composeRule.onAllNodesWithText("精英").assertCountEquals(0)
        composeRule.onAllNodesWithText("首领").assertCountEquals(0)
    }

    @Test
    fun adventureCardTopBadgeUsesDailyStatusInsteadOfFixedTodayText() {
        composeRule.setContent {
            HomeScreen(
                activePacks = BuiltinPacks.all.take(1),
                selectedPack = BuiltinPacks.all.first(),
                coins = 12,
                cloudCredentials = null,
                showDeveloperTools = false,
                homeVersionLabel = "",
                dailyStatus = DailyHomeStatus(
                    label = "已完成",
                    remainingReviewCount = 0,
                    showReviewCountBadge = false,
                    reviewAvailable = false,
                ),
                onDeveloperVersionTripleTap = {},
                onSelectPack = {},
                onBoundChild = {},
                onStart = {},
                onReview = { false },
                onPackManager = {},
                onWishlist = {},
                onMonsterCodex = {},
                onTodayPlan = {},
                onConfig = {},
            )
        }

        composeRule.onNodeWithTag("AdventureCardDailyStatusBadge")
            .assertIsDisplayed()
            .assertTextContains("已完成")
        composeRule.onAllNodesWithText("今日").assertCountEquals(0)
    }

    @Test
    fun unavailableReviewShowsEmptyToastWithParityTag() {
        composeRule.setContent {
            HomeScreen(
                activePacks = BuiltinPacks.all.take(1),
                selectedPack = BuiltinPacks.all.first(),
                coins = 12,
                cloudCredentials = null,
                showDeveloperTools = false,
                homeVersionLabel = "",
                dailyStatus = DailyHomeStatus(
                    label = "请选择一个场景加战斗",
                    remainingReviewCount = 0,
                    showReviewCountBadge = false,
                    reviewAvailable = false,
                ),
                onDeveloperVersionTripleTap = {},
                onSelectPack = {},
                onBoundChild = {},
                onStart = {},
                onReview = { false },
                onPackManager = {},
                onWishlist = {},
                onMonsterCodex = {},
                onTodayPlan = {},
                onConfig = {},
            )
        }

        composeRule.onNodeWithTag("HomeReviewButton").performClick()
        composeRule.onNodeWithTag("HomeReviewEmptyToast")
            .assertIsDisplayed()
    }
}
