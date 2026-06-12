package cool.happyword.wordmagic.cocos

import android.os.Bundle
import android.util.Log
import com.cocos.lib.CocosActivity

/**
 * Hosts the Cocos battle scene as a separate Activity.
 *
 * Task 0.2 — minimal first version: starts the engine, renders the scene.
 * The scene sends `battle/ready` when the JS boots; this activity does not
 * yet send a `battle/init` (unanswered ready is expected at this stage).
 *
 * Task 0.3 will add the JsbBridgeWrapper ping/pong probe and re-entry checks.
 * Task 1.4 will wire the full BattleEngine + bridge + result flow.
 *
 * Launch mechanism (dev entry — Task 0.2 Step 5): DevMenu → "CocosLab" button
 * in DeveloperRoutingScreens / DevMenuScreen.  The activity is not exported
 * (no intent-filter) so it can only be launched from within the process or
 * via `adb shell am start` on a debuggable build.
 */
class CocosBattleActivity : CocosActivity() {

    private val tag = "WMCocosBattle"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Log.i(tag, "CocosBattleActivity onCreate")
    }

    override fun onResume() {
        super.onResume()
        Log.i(tag, "CocosBattleActivity onResume")
    }

    override fun onPause() {
        super.onPause()
        Log.i(tag, "CocosBattleActivity onPause")
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.i(tag, "CocosBattleActivity onDestroy")
    }
}
