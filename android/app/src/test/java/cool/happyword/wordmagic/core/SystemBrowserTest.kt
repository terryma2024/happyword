package cool.happyword.wordmagic.core

import org.junit.Assert.assertEquals
import org.junit.Test

class SystemBrowserTest {
    @Test
    fun launchSpecUsesAndroidCustomTabs() {
        val spec = SystemBrowser.launchSpec("https://happyword.com.cn/family/login")

        assertEquals("https://happyword.com.cn/family/login", spec.url)
        assertEquals(BrowserLaunchMode.AndroidCustomTabs, spec.mode)
    }
}
