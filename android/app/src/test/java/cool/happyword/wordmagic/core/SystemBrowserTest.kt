package cool.happyword.wordmagic.core

import org.junit.Assert.assertEquals
import org.junit.Test

class SystemBrowserTest {
    @Test
    fun launchSpecUsesAndroidCustomTabs() {
        val spec = SystemBrowser.launchSpec("https://happyword.cool/family/login")

        assertEquals("https://happyword.cool/family/login", spec.url)
        assertEquals(BrowserLaunchMode.AndroidCustomTabs, spec.mode)
    }
}
