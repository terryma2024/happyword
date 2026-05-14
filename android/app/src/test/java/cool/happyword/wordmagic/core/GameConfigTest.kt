package cool.happyword.wordmagic.core

import org.junit.Assert.assertEquals
import org.junit.Test

class GameConfigTest {
    @Test
    fun defaultsMatchHarmonyOSBattleDefaults() {
        val config = GameConfig()

        assertEquals(5, config.playerHp)
        assertEquals(3, config.monsterHp)
        assertEquals(5, config.monsterCount)
        assertEquals(300, config.timerSeconds)
        assertEquals(true, config.autoPronunciation)
    }

    @Test
    fun customTimerAllowsThreeSecondsForUiTimeoutTests() {
        val v = GameConfig.validateCustomTimerInput("3")
        assertEquals(true, v.ok)
        assertEquals(3, v.seconds)
        assertEquals(3, GameConfig.sanitizeTimerSeconds(3))
    }

    @Test
    fun customTimerClampsToOneThroughThirtySixHundredSeconds() {
        assertEquals(1, GameConfig.sanitizeTimerSeconds(0))
        assertEquals(3600, GameConfig.sanitizeTimerSeconds(4000))
    }

    @Test
    fun validateCustomTimerRejectsEmptyAndNonDigits() {
        assertEquals(false, GameConfig.validateCustomTimerInput("").ok)
        assertEquals(false, GameConfig.validateCustomTimerInput("   \t  ").ok)
        assertEquals(false, GameConfig.validateCustomTimerInput("3a").ok)
        assertEquals(false, GameConfig.validateCustomTimerInput("-5").ok)
        assertEquals(false, GameConfig.validateCustomTimerInput("3.5").ok)
    }

    @Test
    fun validateCustomTimerRejectsZeroAndAboveMax() {
        val zero = GameConfig.validateCustomTimerInput("0")
        assertEquals(false, zero.ok)
        assertEquals(true, zero.message.contains("${GameConfig.TIMER_CUSTOM_MIN}"))
        val over = GameConfig.validateCustomTimerInput("3601")
        assertEquals(false, over.ok)
        assertEquals(true, over.message.contains("${GameConfig.TIMER_CUSTOM_MAX}"))
    }

    @Test
    fun validateCustomTimerAcceptsTrimmableAndBounds() {
        val spaced = GameConfig.validateCustomTimerInput("  42  ")
        assertEquals(true, spaced.ok)
        assertEquals(42, spaced.seconds)
        assertEquals(true, GameConfig.validateCustomTimerInput("${GameConfig.TIMER_CUSTOM_MIN}").ok)
        assertEquals(true, GameConfig.validateCustomTimerInput("${GameConfig.TIMER_CUSTOM_MAX}").ok)
    }
}
