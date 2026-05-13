package cool.happyword.wordmagic.core

/**
 * Stateful triple-tap detector. Matches HarmonyOS [VersionTripleTap.ets] semantics
 * so three deliberate taps within [windowMs] open the developer menu.
 */
class VersionTripleTap(private val windowMs: Long = 1500L) {
    private var count: Int = 0
    private var lastTapMs: Long = 0L

    /** Returns true exactly when this tap completes a triple-tap. */
    fun onTap(nowMs: Long): Boolean {
        if (nowMs - lastTapMs > windowMs) {
            count = 1
        } else {
            count += 1
        }
        lastTapMs = nowMs
        if (count >= 3) {
            count = 0
            lastTapMs = 0L
            return true
        }
        return false
    }
}
