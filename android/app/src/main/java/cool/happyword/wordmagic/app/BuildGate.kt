package cool.happyword.wordmagic.app

import cool.happyword.wordmagic.core.BackendEnv
import cool.happyword.wordmagic.core.BackendRouteState

object BuildGate {
    fun showDeveloperTools(isDebuggable: Boolean): Boolean = isDebuggable

    fun coerceBackendRouteForBuild(isDebuggable: Boolean, state: BackendRouteState): BackendRouteState {
        if (isDebuggable) return state
        val env = when (state.env) {
            BackendEnv.Prod -> BackendEnv.Prod
            else -> BackendEnv.Staging
        }
        return BackendRouteState(env = env)
    }
}
