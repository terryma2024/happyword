package cool.happyword.wordmagic.ui

import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Test

class PageChromeInsetPolicyTest {
    @Test
    fun topChromeConsumesAndroidCutoutAndStatusInsets() {
        assertTrue(PageChromeInsets.topChromeUsesDisplayCutoutInsets)
        assertTrue(PageChromeInsets.topChromeUsesStatusBarInsets)
    }

    @Test
    fun everyPhonePortraitPageAppliesTopChromeSafeInsets() {
        val portraitPages = listOf(
            PortraitPageSource("ConfigScreen", "src/main/java/cool/happyword/wordmagic/ui/config/ConfigUi.kt"),
            PortraitPageSource("TodayPlanScreen", "src/main/java/cool/happyword/wordmagic/ui/LocalGrowthScreens.kt"),
            PortraitPageSource("CheckInCalendarScreen", "src/main/java/cool/happyword/wordmagic/ui/LocalGrowthScreens.kt"),
            PortraitPageSource("PackManagerScreen", "src/main/java/cool/happyword/wordmagic/ui/LocalGrowthScreens.kt"),
            PortraitPageSource("LearningReportScreen", "src/main/java/cool/happyword/wordmagic/ui/LocalGrowthScreens.kt"),
            PortraitPageSource("RedemptionHistoryScreen", "src/main/java/cool/happyword/wordmagic/ui/LocalGrowthScreens.kt"),
            PortraitPageSource("ParentPinScreen", "src/main/java/cool/happyword/wordmagic/ui/parent/ParentScreens.kt"),
            PortraitPageSource("ScanBindingScreen", "src/main/java/cool/happyword/wordmagic/ui/CloudBindingScreens.kt"),
            PortraitPageSource("BoundDeviceInfoScreen", "src/main/java/cool/happyword/wordmagic/ui/CloudBindingScreens.kt"),
            PortraitPageSource("ParentAdminScreen", "src/main/java/cool/happyword/wordmagic/ui/parent/ParentScreens.kt"),
            PortraitPageSource("LessonDraftReviewScreen", "src/main/java/cool/happyword/wordmagic/ui/parent/ParentScreens.kt"),
        )

        portraitPages.forEach { page ->
            val body = sourceFunctionBody(page)
            assertTrue(
                "${page.functionName} must call topChromeSafeInsets() or shared PageTopChrome to avoid cutout overlap",
                body.contains(".topChromeSafeInsets()") || body.contains("PageTopChrome("),
            )
        }
    }

    private fun sourceFunctionBody(page: PortraitPageSource): String {
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

    private data class PortraitPageSource(val functionName: String, val path: String)
}
