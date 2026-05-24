package cool.happyword.wordmagic.ui

import java.io.File
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PageBackButtonPolicyTest {
    @Test
    fun pageLevelBackControlsUseHarmonyPageTopBackButton() {
        val pages = listOf(
            PageSource("ConfigScreen", "src/main/java/cool/happyword/wordmagic/ui/config/ConfigUi.kt"),
            PageSource("TodayPlanScreen", "src/main/java/cool/happyword/wordmagic/ui/LocalGrowthScreens.kt"),
            PageSource("CheckInCalendarScreen", "src/main/java/cool/happyword/wordmagic/ui/LocalGrowthScreens.kt"),
            PageSource("PackManagerScreen", "src/main/java/cool/happyword/wordmagic/ui/LocalGrowthScreens.kt"),
            PageSource("LearningReportScreen", "src/main/java/cool/happyword/wordmagic/ui/LocalGrowthScreens.kt"),
            PageSource("RedemptionHistoryScreen", "src/main/java/cool/happyword/wordmagic/ui/LocalGrowthScreens.kt"),
            PageSource("MonsterCodexScreen", "src/main/java/cool/happyword/wordmagic/ui/LocalGrowthScreens.kt"),
            PageSource("WishlistScreen", "src/main/java/cool/happyword/wordmagic/ui/LocalGrowthScreens.kt"),
            PageSource("ParentPinScreen", "src/main/java/cool/happyword/wordmagic/ui/parent/ParentScreens.kt"),
            PageSource("ParentAdminScreen", "src/main/java/cool/happyword/wordmagic/ui/parent/ParentScreens.kt"),
            PageSource("LessonDraftReviewScreen", "src/main/java/cool/happyword/wordmagic/ui/parent/ParentScreens.kt"),
            PageSource("ScanBindingScreen", "src/main/java/cool/happyword/wordmagic/ui/CloudBindingScreens.kt"),
            PageSource("BoundDeviceInfoScreen", "src/main/java/cool/happyword/wordmagic/ui/CloudBindingScreens.kt"),
            PageSource("DevMenuScreen", "src/main/java/cool/happyword/wordmagic/ui/DeveloperRoutingScreens.kt"),
            PageSource("BypassSecretScreen", "src/main/java/cool/happyword/wordmagic/ui/DeveloperRoutingScreens.kt"),
        )

        pages.forEach { page ->
            val body = sourceFunctionBody(page)
            assertTrue("${page.functionName} must use HarmonyPageTopBackButton or shared PageTopChrome", hasStandardBack(body))
            assertFalse("${page.functionName} must not use text/outlined/dev-menu page back controls", hasNonStandardPageBack(body))
        }
    }

    private fun hasStandardBack(body: String): Boolean =
        body.contains("HarmonyPageTopBackButton(") || body.contains("PageTopChrome(")

    private fun hasNonStandardPageBack(body: String): Boolean =
        body.contains("Text(\"←") ||
            body.contains("Text(\"返回\")") ||
            body.contains("Text(\"Back\")") ||
            body.contains("HarmonyDevMenuButton(\"Back\"")

    private fun sourceFunctionBody(page: PageSource): String {
        val text = readSource(page.path)
        val start = text.indexOf("fun ${page.functionName}(")
        assertTrue("${page.functionName} source not found", start >= 0)
        val nextComposable = text.indexOf("\n@Composable", start + 1).takeIf { it >= 0 } ?: text.length
        return text.substring(start, nextComposable)
    }

    private fun readSource(path: String): String {
        val cwd = File(requireNotNull(System.getProperty("user.dir")))
        val candidates = listOf(
            File(cwd, path),
            File(cwd, "app/$path"),
            File(cwd.parentFile ?: cwd, path),
        )
        val file = candidates.firstOrNull { it.isFile }
            ?: error("source file not found: $path")
        return file.readText()
    }

    private data class PageSource(val functionName: String, val path: String)
}
