package cool.happyword.wordmagic.data

import android.content.Context
import androidx.annotation.DrawableRes
import cool.happyword.wordmagic.R
import cool.happyword.wordmagic.core.PackSource
import cool.happyword.wordmagic.core.WordPack
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest

enum class SpellbookCoverSourceKind {
    Drawable,
    LocalFile,
    RemoteUrl,
}

data class SpellbookCoverSource(
    val kind: SpellbookCoverSourceKind,
    val value: String,
    val imageUri: String,
    @param:DrawableRes val drawableResId: Int? = null,
)

class SpellbookCoverCache(
    private val rootDir: File,
    private val fetcher: (String) -> ByteArray? = ::fetchUrlBytes,
) {
    fun sourceForPack(pack: WordPack): SpellbookCoverSource {
        val bundledDrawable = bundledDrawableId(pack)
        if (bundledDrawable != null) {
            return drawableSource(bundledDrawable)
        }
        val remoteUrl = pack.scene.spellbookCoverUrl.trim()
        if (remoteUrl.isBlank()) {
            return drawableSource(R.drawable.spellbook_cover_default)
        }
        val cached = cachedFileForUrl(remoteUrl)
        if (cached != null) {
            return SpellbookCoverSource(
                kind = SpellbookCoverSourceKind.LocalFile,
                value = cached.absolutePath,
                imageUri = fileUriForPath(cached.absolutePath),
            )
        }
        return SpellbookCoverSource(
            kind = SpellbookCoverSourceKind.RemoteUrl,
            value = remoteUrl,
            imageUri = remoteUrl,
            drawableResId = R.drawable.spellbook_cover_default,
        )
    }

    fun refresh(packs: List<WordPack>) {
        packs.asSequence()
            .map { it.scene.spellbookCoverUrl.trim() }
            .filter { it.isNotBlank() }
            .distinct()
            .forEach { url ->
                runCatching { resolve(url) }
            }
    }

    fun resolve(url: String): File? {
        val cached = cachedFileForUrl(url)
        if (cached != null) return cached
        val bytes = fetcher(url) ?: return null
        val file = cacheFileForUrl(url)
        file.parentFile?.mkdirs()
        val tmp = File(file.parentFile ?: rootDir, "${file.name}.tmp")
        tmp.writeBytes(bytes)
        if (file.exists()) file.delete()
        if (!tmp.renameTo(file)) {
            tmp.copyTo(file, overwrite = true)
            tmp.delete()
        }
        return file.takeIf { it.exists() && it.length() > 0L }
    }

    fun cachedFileForUrl(url: String): File? =
        cacheFileForUrl(url).takeIf { it.exists() && it.length() > 0L }

    fun cacheFileForUrl(url: String): File =
        File(rootDir, "${sha256(url)}${extensionForUrl(url)}")

    companion object {
        fun forContext(context: Context): SpellbookCoverCache =
            SpellbookCoverCache(File(context.applicationContext.filesDir, "asset-cache/covers"))

        fun fileUriForPath(path: String): String =
            if (path.startsWith("file://")) path else "file://$path"

        private fun drawableSource(@DrawableRes drawableId: Int): SpellbookCoverSource =
            SpellbookCoverSource(
                kind = SpellbookCoverSourceKind.Drawable,
                value = drawableId.toString(),
                imageUri = "",
                drawableResId = drawableId,
            )

        @DrawableRes
        private fun bundledDrawableId(pack: WordPack): Int? {
            if (pack.source != PackSource.Builtin) return null
            return when (pack.id) {
                "fruit-forest" -> R.drawable.spellbook_cover_fruit_forest
                "school-castle" -> R.drawable.spellbook_cover_school_castle
                "home-cottage" -> R.drawable.spellbook_cover_home_cottage
                "animal-safari" -> R.drawable.spellbook_cover_animal_safari
                "ocean-realm" -> R.drawable.spellbook_cover_ocean_realm
                else -> null
            }
        }

        private fun sha256(value: String): String =
            MessageDigest.getInstance("SHA-256")
                .digest(value.toByteArray(Charsets.UTF_8))
                .joinToString("") { "%02x".format(it) }

        private fun extensionForUrl(rawUrl: String): String {
            val path = runCatching { URL(rawUrl).path }.getOrDefault("")
            val ext = path.substringAfterLast('.', missingDelimiterValue = "")
                .takeIf { it.length in 2..5 && it.all { ch -> ch.isLetterOrDigit() } }
                ?: "img"
            return ".$ext"
        }
    }
}

private fun fetchUrlBytes(rawUrl: String): ByteArray? {
    val connection = (URL(rawUrl).openConnection() as HttpURLConnection).apply {
        connectTimeout = 6_000
        readTimeout = 6_000
        requestMethod = "GET"
        doInput = true
    }
    return try {
        if (connection.responseCode !in 200..299) return null
        connection.inputStream.use { it.readBytes() }
    } finally {
        connection.disconnect()
    }
}
