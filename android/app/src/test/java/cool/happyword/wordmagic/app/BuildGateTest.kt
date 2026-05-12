package cool.happyword.wordmagic.app

import cool.happyword.wordmagic.core.BackendEnv
import cool.happyword.wordmagic.core.BackendRouteState
import cool.happyword.wordmagic.core.PreviewTarget
import org.junit.Assert.assertFalse
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
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

    @Test
    fun releaseBuildCoercesPreviewRoutingToStaging() {
        val releaseState = BuildGate.coerceBackendRouteForBuild(
            isDebuggable = false,
            state = BackendRouteState(
                env = BackendEnv.Preview,
                selectedPreview = PreviewTarget("p1", "Preview", "https://preview.example.com"),
                instrumentationOverrideUrl = "http://127.0.0.1:8123",
            ),
        )

        assertEquals(BackendEnv.Staging, releaseState.env)
        assertNull(releaseState.selectedPreview)
        assertNull(releaseState.instrumentationOverrideUrl)
    }

    @Test
    fun releaseBuildCoercesLocalRoutingToStaging() {
        val releaseState = BuildGate.coerceBackendRouteForBuild(
            isDebuggable = false,
            state = BackendRouteState(env = BackendEnv.Local),
        )

        assertEquals(BackendEnv.Staging, releaseState.env)
    }

    @Test
    fun releaseBuildMayKeepProductionRouting() {
        val releaseState = BuildGate.coerceBackendRouteForBuild(
            isDebuggable = false,
            state = BackendRouteState(env = BackendEnv.Prod),
        )

        assertEquals(BackendEnv.Prod, releaseState.env)
    }

    @Test
    fun debugBuildKeepsDeveloperRoutingState() {
        val debugState = BackendRouteState(
            env = BackendEnv.Preview,
            selectedPreview = PreviewTarget("p1", "Preview", "https://preview.example.com"),
            instrumentationOverrideUrl = "http://127.0.0.1:8123",
        )

        assertEquals(debugState, BuildGate.coerceBackendRouteForBuild(isDebuggable = true, state = debugState))
    }
}
