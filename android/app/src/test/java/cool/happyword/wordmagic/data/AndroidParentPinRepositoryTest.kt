package cool.happyword.wordmagic.data

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AndroidParentPinRepositoryTest {
    @Test
    fun setPinPersistsReadyStateAndVerificationAcrossRepositoryInstances() {
        val prefs = FakeSharedPreferences()

        assertTrue(AndroidParentPinRepository(prefs).setPin("123456"))

        val restarted = AndroidParentPinRepository(prefs)
        assertTrue(restarted.hasPin())
        assertTrue(restarted.verifyPin("123456"))
        assertFalse(restarted.verifyPin("654321"))
    }

    @Test
    fun setPinDoesNotStorePlainTextPin() {
        val prefs = FakeSharedPreferences()

        AndroidParentPinRepository(prefs).setPin("123456")

        assertFalse(prefs.all.values.any { it == "123456" })
    }

    @Test
    fun rejectsInvalidPins() {
        val repository = AndroidParentPinRepository(FakeSharedPreferences())

        assertFalse(repository.setPin("12345"))

        assertFalse(repository.hasPin())
    }
}
