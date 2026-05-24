package cool.happyword.wordmagic.ui.navigation

import android.app.Activity
import android.content.pm.ActivityInfo
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalConfiguration

internal const val PAD_SHORT_EDGE_BREAKPOINT_DP = 600

internal fun requestedOrientationForRoute(route: AppRoute, shortEdgeDp: Int): Int {
    if (shortEdgeDp >= PAD_SHORT_EDGE_BREAKPOINT_DP) {
        return ActivityInfo.SCREEN_ORIENTATION_FULL_SENSOR
    }
    return when (route) {
        AppRoute.Config,
        AppRoute.TodayPlan,
        AppRoute.CheckInCalendar,
        AppRoute.PackManager,
        AppRoute.LearningReport,
        AppRoute.RedemptionHistory,
        AppRoute.ParentPin,
        AppRoute.ScanBinding,
        AppRoute.BoundDeviceInfo,
        AppRoute.ParentAdmin,
        AppRoute.LessonDraftReview -> ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
        else -> ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
    }
}

@Composable
internal fun ApplyOrientation(route: AppRoute) {
    val activity = LocalContext.current as? Activity
    val configuration = LocalConfiguration.current
    val shortEdgeDp = minOf(configuration.screenWidthDp, configuration.screenHeightDp)
    DisposableEffect(route, shortEdgeDp) {
        activity?.requestedOrientation = requestedOrientationForRoute(route, shortEdgeDp)
        onDispose {}
    }
}
