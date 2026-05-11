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
        assertEquals(3, GameConfig.sanitizeTimerSeconds(3))
    }

    @Test
    fun customTimerClampsToOneThroughThirtySixHundredSeconds() {
        assertEquals(1, GameConfig.sanitizeTimerSeconds(0))
        assertEquals(3600, GameConfig.sanitizeTimerSeconds(4000))
    }
}
