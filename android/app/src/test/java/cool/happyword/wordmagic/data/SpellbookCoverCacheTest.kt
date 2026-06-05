package cool.happyword.wordmagic.data

import cool.happyword.wordmagic.core.PackSource
import cool.happyword.wordmagic.core.SceneMetadata
import cool.happyword.wordmagic.core.WordEntry
import cool.happyword.wordmagic.core.WordPack
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class SpellbookCoverCacheTest {
    @get:Rule
    val temporaryFolder = TemporaryFolder()

    @Test
    fun cachedRemoteCoverUsesLocalFileBeforeRemoteUrl() {
        val url = "https://blob.example/covers/family-space.png"
        val cache = SpellbookCoverCache(temporaryFolder.newFolder("covers"))
        val cachedFile = cache.cacheFileForUrl(url)
        cachedFile.parentFile?.mkdirs()
        cachedFile.writeBytes(byteArrayOf(1, 2, 3))

        val source = cache.sourceForPack(remotePack(url))

        assertEquals(SpellbookCoverSourceKind.LocalFile, source.kind)
        assertEquals(cachedFile.absolutePath, source.value)
        assertEquals("file://${cachedFile.absolutePath}", source.imageUri)
    }

    @Test
    fun missingRemoteCoverCacheFallsBackToRemoteUrl() {
        val url = "https://blob.example/covers/family-space.png"
        val cache = SpellbookCoverCache(temporaryFolder.newFolder("covers"))

        val source = cache.sourceForPack(remotePack(url))

        assertEquals(SpellbookCoverSourceKind.RemoteUrl, source.kind)
        assertEquals(url, source.value)
        assertEquals(url, source.imageUri)
    }

    private fun remotePack(url: String): WordPack =
        WordPack(
            id = "family-space",
            nameEn = "Family Space",
            nameZh = "家庭太空",
            source = PackSource.Family,
            version = 1,
            publishedAtMs = 3_000L,
            scene = SceneMetadata(
                bgPrimary = "#FFFFFF",
                bgAccent = "#FFFFFF",
                bossName = "",
                monsterPlan = emptyList(),
                bossCandidates = emptyList(),
                storyZh = "星星排成小路。",
                storyEn = "Stars make a path.",
                spellbookCoverUrl = url,
            ),
            words = listOf(
                WordEntry("space-moon", "moon", "月亮"),
                WordEntry("space-star", "star", "星星"),
                WordEntry("space-sun", "sun", "太阳"),
            ),
        )
}
