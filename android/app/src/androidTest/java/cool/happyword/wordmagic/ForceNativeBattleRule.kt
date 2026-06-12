package cool.happyword.wordmagic

import cool.happyword.wordmagic.cocos.forceNativeBattle
import org.junit.rules.TestWatcher
import org.junit.runner.Description

/**
 * JUnit4 TestRule that sets [forceNativeBattle] = true for the duration of any
 * test class that drives the battle screen.
 *
 * The flag is set in [starting] and deliberately NOT reset in [finished].
 * Leaving the flag true for the entire instrumentation process is intentional:
 * it protects every test in the suite from accidentally routing to
 * CocosBattleActivity, which requires real Cocos native libs and is not
 * suitable for in-process Compose tests.
 *
 * Apply with `@get:Rule val forceNative = ForceNativeBattleRule()` in any
 * test class that starts a battle.
 */
class ForceNativeBattleRule : TestWatcher() {
    override fun starting(description: Description) {
        forceNativeBattle = true
    }
    // Deliberately NO reset in finished(): leaving the flag true keeps the whole
    // instrumentation process protected; each battle-driving class applies the rule.
}
