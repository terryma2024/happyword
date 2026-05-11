package cool.happyword.wordmagic.app

import org.junit.Assert.assertEquals
import org.junit.Test

class AppMetadataTest {
    @Test
    fun metadataMatchesAndroidPackage() {
        assertEquals("WordMagicGame Android", AppMetadata.appName)
        assertEquals("cool.happyword.wordmagic", AppMetadata.packageName)
    }
}
