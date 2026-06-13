package cool.happyword.wordmagic.cocos

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Port of harmonyos/entry/src/test/CocosBattlePreference.test.ets, adapted
 * to the Android Kotlin implementation.
 *
 * Tests the pure [decideBattleRoute] function and the raw-string → boolean
 * mapping [cocosBattlePrefEnabledFromRaw].  No Android Context is needed here.
 */
class CocosBattlePreferenceTest {

    // ─── Decision table ───────────────────────────────────────────────────────

    @Test
    fun decisionTable() {
        // All conditions met → COCOS
        assertEquals(
            BattleRoute.COCOS,
            decideBattleRoute(
                runtimeAvailable = true,
                prefEnabled = true,
                fallbackActive = false,
                forceNative = false,
            ),
        )
        // pref off → NATIVE
        assertEquals(
            BattleRoute.NATIVE,
            decideBattleRoute(
                runtimeAvailable = true,
                prefEnabled = false,
                fallbackActive = false,
                forceNative = false,
            ),
        )
        // runtime unavailable → NATIVE
        assertEquals(
            BattleRoute.NATIVE,
            decideBattleRoute(
                runtimeAvailable = false,
                prefEnabled = true,
                fallbackActive = false,
                forceNative = false,
            ),
        )
        // fallback active → NATIVE
        assertEquals(
            BattleRoute.NATIVE,
            decideBattleRoute(
                runtimeAvailable = true,
                prefEnabled = true,
                fallbackActive = true,
                forceNative = false,
            ),
        )
        // force native → NATIVE
        assertEquals(
            BattleRoute.NATIVE,
            decideBattleRoute(
                runtimeAvailable = true,
                prefEnabled = true,
                fallbackActive = false,
                forceNative = true,
            ),
        )
    }

    // ─── Raw-string mapping (default-ON contract) ─────────────────────────────

    @Test
    fun absentKeyMapsToTrue() {
        // Absent key returns "" from SharedPreferences.getString with default "".
        assertEquals(true, cocosBattlePrefEnabledFromRaw(""))
    }

    @Test
    fun explicitFalseMapsToFalse() {
        assertEquals(false, cocosBattlePrefEnabledFromRaw("false"))
    }

    @Test
    fun explicitTrueMapsToTrue() {
        assertEquals(true, cocosBattlePrefEnabledFromRaw("true"))
    }

    @Test
    fun garbageValueMapsToTrue() {
        // Any unrecognised value → ON (same as HOS twin: raw !== 'false' → true).
        assertEquals(true, cocosBattlePrefEnabledFromRaw("garbage"))
        assertEquals(true, cocosBattlePrefEnabledFromRaw("1"))
        assertEquals(true, cocosBattlePrefEnabledFromRaw("yes"))
        assertEquals(true, cocosBattlePrefEnabledFromRaw("FALSE")) // case-sensitive
    }
}
