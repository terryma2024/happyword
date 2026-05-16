package cool.happyword.wordmagic.ui.navigation

import android.app.Activity
import android.content.pm.ActivityInfo
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.ui.platform.LocalContext

@Composable
internal fun ApplyOrientation(route: AppRoute) {
    val activity = LocalContext.current as? Activity
    DisposableEffect(route) {
        activity?.requestedOrientation = when (route) {
            AppRoute.ParentPin,
            AppRoute.ParentAdmin,
            AppRoute.LessonDraftReview -> ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
            else -> ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
        }
        onDispose {}
    }
}
