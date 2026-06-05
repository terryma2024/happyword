package cool.happyword.wordmagic.ui

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import cool.happyword.wordmagic.R
import cool.happyword.wordmagic.core.WordPack
import cool.happyword.wordmagic.data.SpellbookCoverCache
import cool.happyword.wordmagic.data.SpellbookCoverSourceKind
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

@Composable
internal fun SpellbookCoverImage(
    pack: WordPack,
    cacheVersion: Int,
    modifier: Modifier = Modifier,
    contentDescription: String? = pack.nameZh,
    contentScale: ContentScale = ContentScale.Fit,
) {
    val context = LocalContext.current.applicationContext
    val cache = remember(context) { SpellbookCoverCache.forContext(context) }
    val source = remember(pack.id, pack.source, pack.scene.spellbookCoverUrl, cacheVersion) {
        cache.sourceForPack(pack)
    }
    var bitmap by remember(pack.id, pack.source, pack.scene.spellbookCoverUrl, cacheVersion) {
        mutableStateOf<Bitmap?>(null)
    }

    LaunchedEffect(source) {
        bitmap = null
        bitmap = withContext(Dispatchers.IO) {
            when (source.kind) {
                SpellbookCoverSourceKind.LocalFile -> BitmapFactory.decodeFile(source.value)
                SpellbookCoverSourceKind.RemoteUrl -> cache.resolve(source.value)?.absolutePath?.let(BitmapFactory::decodeFile)
                SpellbookCoverSourceKind.Drawable -> null
            }
        }
    }

    val loadedBitmap = bitmap
    if (loadedBitmap != null) {
        Image(
            bitmap = loadedBitmap.asImageBitmap(),
            contentDescription = contentDescription,
            modifier = modifier,
            contentScale = contentScale,
        )
    } else {
        Image(
            painter = painterResource(source.drawableResId ?: R.drawable.spellbook_cover_default),
            contentDescription = contentDescription,
            modifier = modifier,
            contentScale = contentScale,
        )
    }
}
