package cool.happyword.wordmagic.ui.navigation

import android.content.pm.ActivityInfo
import org.junit.Assert.assertEquals
import org.junit.Test

class OrientationPolicyTest {
    @Test
    fun phoneRoutesMatchHarmonyV092OrientationRules() {
        val phoneShortEdge = PAD_SHORT_EDGE_BREAKPOINT_DP - 1

        assertEquals(ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE, requestedOrientationForRoute(AppRoute.Home, phoneShortEdge))
        assertEquals(ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE, requestedOrientationForRoute(AppRoute.Battle, phoneShortEdge))
        assertEquals(ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE, requestedOrientationForRoute(AppRoute.Result, phoneShortEdge))
        assertEquals(ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE, requestedOrientationForRoute(AppRoute.MonsterCodex, phoneShortEdge))
        assertEquals(ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE, requestedOrientationForRoute(AppRoute.DevMenu, phoneShortEdge))
        assertEquals(ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE, requestedOrientationForRoute(AppRoute.BypassSecret, phoneShortEdge))
        assertEquals(ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE, requestedOrientationForRoute(AppRoute.Wishlist, phoneShortEdge))

        assertEquals(ActivityInfo.SCREEN_ORIENTATION_PORTRAIT, requestedOrientationForRoute(AppRoute.Config, phoneShortEdge))
        assertEquals(ActivityInfo.SCREEN_ORIENTATION_PORTRAIT, requestedOrientationForRoute(AppRoute.TodayPlan, phoneShortEdge))
        assertEquals(ActivityInfo.SCREEN_ORIENTATION_PORTRAIT, requestedOrientationForRoute(AppRoute.CheckInCalendar, phoneShortEdge))
        assertEquals(ActivityInfo.SCREEN_ORIENTATION_PORTRAIT, requestedOrientationForRoute(AppRoute.PackManager, phoneShortEdge))
        assertEquals(ActivityInfo.SCREEN_ORIENTATION_PORTRAIT, requestedOrientationForRoute(AppRoute.LearningReport, phoneShortEdge))
        assertEquals(ActivityInfo.SCREEN_ORIENTATION_PORTRAIT, requestedOrientationForRoute(AppRoute.RedemptionHistory, phoneShortEdge))
        assertEquals(ActivityInfo.SCREEN_ORIENTATION_PORTRAIT, requestedOrientationForRoute(AppRoute.ParentPin, phoneShortEdge))
        assertEquals(ActivityInfo.SCREEN_ORIENTATION_PORTRAIT, requestedOrientationForRoute(AppRoute.ScanBinding, phoneShortEdge))
        assertEquals(ActivityInfo.SCREEN_ORIENTATION_PORTRAIT, requestedOrientationForRoute(AppRoute.BoundDeviceInfo, phoneShortEdge))
        assertEquals(ActivityInfo.SCREEN_ORIENTATION_PORTRAIT, requestedOrientationForRoute(AppRoute.ParentAdmin, phoneShortEdge))
        assertEquals(ActivityInfo.SCREEN_ORIENTATION_PORTRAIT, requestedOrientationForRoute(AppRoute.LessonDraftReview, phoneShortEdge))
    }

    @Test
    fun padRoutesReleaseToDeviceRotation() {
        assertEquals(ActivityInfo.SCREEN_ORIENTATION_FULL_SENSOR, requestedOrientationForRoute(AppRoute.Battle, PAD_SHORT_EDGE_BREAKPOINT_DP))
        assertEquals(ActivityInfo.SCREEN_ORIENTATION_FULL_SENSOR, requestedOrientationForRoute(AppRoute.Config, PAD_SHORT_EDGE_BREAKPOINT_DP))
        assertEquals(ActivityInfo.SCREEN_ORIENTATION_FULL_SENSOR, requestedOrientationForRoute(AppRoute.ParentAdmin, PAD_SHORT_EDGE_BREAKPOINT_DP))
    }
}
