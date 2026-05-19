package cool.happyword.wordmagic.app

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AppMetadataTest {
    @Test
    fun metadataMatchesAndroidPackage() {
        assertEquals("WordMagicGame Android", AppMetadata.appName)
        assertEquals("cool.happyword.wordmagic", AppMetadata.packageName)
    }

    @Test
    fun launcherLabelUsesChineseAppNameResource() {
        val manifest = File("src/main/AndroidManifest.xml").readText()
        val strings = File("src/main/res/values/strings.xml").readText()

        assertTrue(manifest.contains("""android:label="@string/app_name""""))
        assertTrue(strings.contains("""<string name="app_name">魔法背单词</string>"""))
    }

    @Test
    fun releaseManifestDoesNotAllowCleartextTraffic() {
        val manifest = File("src/main/AndroidManifest.xml").readText()

        assertFalse(manifest.contains("""android:usesCleartextTraffic="true""""))
    }

    @Test
    fun debugManifestKeepsCleartextTrafficForLocalMockServers() {
        val manifest = File("src/debug/AndroidManifest.xml").readText()

        assertTrue(manifest.contains("""android:usesCleartextTraffic="true""""))
    }
}
