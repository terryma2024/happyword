package cool.happyword.wordmagic.app

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class BuildGateTest {
    @Test
    fun debugBuildMayShowDeveloperTools() {
        assertTrue(BuildGate.showDeveloperTools(isDebuggable = true))
    }

    @Test
    fun releaseBuildHidesDeveloperTools() {
        assertFalse(BuildGate.showDeveloperTools(isDebuggable = false))
    }
}
