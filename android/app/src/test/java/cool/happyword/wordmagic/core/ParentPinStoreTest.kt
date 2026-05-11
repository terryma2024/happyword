package cool.happyword.wordmagic.core

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ParentPinStoreTest {
    @Test
    fun acceptsOnlySixDigitPins() {
        assertTrue(ParentPinStore.isValidPin("123456"))
        assertFalse(ParentPinStore.isValidPin("12345"))
        assertFalse(ParentPinStore.isValidPin("1234567"))
        assertFalse(ParentPinStore.isValidPin("abcdef"))
    }
}
