package cool.happyword.wordmagic.ui.battle

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DamageFloaterTest {
    @Test
    fun pickFloaterStyleForOneIsBright() {
        val style = pickFloaterStyle(1)
        assertEquals("-1", style.text)
        assertEquals(18, style.fontSizeSp)
        assertTrue(style.hasStroke)
    }

    @Test
    fun pickFloaterStyleForTwoIsDeep() {
        val style = pickFloaterStyle(2)
        assertEquals("-2", style.text)
        assertEquals(20, style.fontSizeSp)
        assertFalse(style.hasStroke)
        assertEquals(2f, style.shadowRadius)
    }

    @Test
    fun pushBattleFloaterCapsQueueAtFour() {
        var list = emptyList<FloaterPending>()
        var key = 0
        repeat(5) {
            val pushed = pushBattleFloater(list, key, 1)
            list = pushed.first
            key = pushed.second
        }
        assertEquals(4, list.size)
        assertEquals(1, list.first().id)
    }
}
