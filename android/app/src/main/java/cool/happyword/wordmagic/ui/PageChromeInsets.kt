package cool.happyword.wordmagic.ui

import androidx.compose.ui.unit.dp

/**
 * Full-screen page body insets aligned with [MonsterCodexScreen] and HarmonyOS `PAGE_BODY_EDGE_VP`.
 */
object PageChromeInsets {
    val bodyHorizontal = 16.dp
    val bodyTop = 8.dp
    val bodyBottom = 16.dp

    /** Matches [HomeScreen] main column `padding(horizontal = 44.dp)`; also used for wishlist / battle body gutters. */
    val homeAlignedHorizontal = 44.dp
}
