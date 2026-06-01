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
    fun gradleVersionMatchesV100Release() {
        val buildFile = File("build.gradle.kts").readText()

        assertTrue(buildFile.contains("""versionCode = 1_010_000"""))
        assertTrue(buildFile.contains("""versionName = "1.0.0""""))
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
