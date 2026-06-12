package cool.happyword.wordmagic.cocos

import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.cocos.lib.CocosActivity
import com.cocos.lib.JsbBridgeWrapper

/**
 * Hosts the Cocos battle scene as a separate Activity.
 *
 * Task 0.2 — minimal first version: starts the engine, renders the scene.
 * Task 0.3 — adds a temporary JsbBridgeWrapper ping/pong probe (below) to
 * prove both bridge directions and activity re-entry work.
 * Task 1.4 will wire the full BattleEngine + bridge + result flow.
 *
 * Launch mechanism (dev entry — Task 0.2 Step 5): DevMenu → "CocosLab" button
 * in DeveloperRoutingScreens / DevMenuScreen.  The activity is not exported
 * (no intent-filter) so it can only be launched from within the process or
 * via `adb shell am start` on a debuggable build.
 */
class CocosBattleActivity : CocosActivity() {

    private val tag = "WMCocosBattle"

    // Task 0.3 bridge probe — replaced by the real adapter in Task 1.x.
    // JsbBridgeWrapper is a process-level singleton: listeners registered here
    // survive activity recreation, so we must remove ours in onDestroy or each
    // re-entry would stack another copy (addScriptEventListener does NOT
    // de-duplicate despite its javadoc).
    private val probeHandler = Handler(Looper.getMainLooper())
    private val probeListener = JsbBridgeWrapper.OnScriptEventListener { json ->
        Log.i("WMBridge", "scene->kotlin [${Thread.currentThread().name}] $json")
        // Verified empirically (first-launch boot took ~7.5s on the emulator):
        // anything dispatched before the scene's BridgeClient registers its
        // listener is SILENTLY DROPPED (no crash, no pong). So the probe fires
        // off battle/ready instead of a blind delay — the real adapter must do
        // the same (queue outbound messages until ready).
        if (json.contains("\"battle/ready\"")) {
            probeHandler.post {
                sendProbe(PROBE_INIT)
                sendProbe(PROBE_PING)
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Log.i(tag, "CocosBattleActivity onCreate")

        // Task 0.3 bridge probe — replaced by the real adapter in Task 1.x.
        // Safe here: addScriptEventListener is pure Java (no JNI), and
        // super.onCreate has already loaded libcocos.so for the wrapper's
        // JsbBridge.setCallback side effect.
        JsbBridgeWrapper.getInstance()
            .addScriptEventListener(EVENT_TO_NATIVE, probeListener)
        // The probe itself is sent from probeListener when battle/ready
        // arrives — see the dropped-message note there.
    }

    private fun sendProbe(json: String) {
        Log.i("WMBridge", "kotlin->scene [${Thread.currentThread().name}] $json")
        JsbBridgeWrapper.getInstance().dispatchEventToScript(EVENT_TO_SCRIPT, json)
    }

    private companion object {
        // Task 0.3 bridge probe constants — replaced by the real adapter in Task 1.x.
        const val EVENT_TO_NATIVE = "wmBattleToNative"
        const val EVENT_TO_SCRIPT = "wmBattleToScript"
        // Shape mirrors shared/fixtures/cocos-battle-bridge/init.json with
        // distinctive values (player HP 7, monster HP 9) so the screenshot
        // proves the init was applied rather than scene defaults.
        const val PROBE_INIT =
            """{"v":1,"type":"battle/init","payload":{"monsterMaxHp":9,"monstersTotal":2,""" +
                """"playerArt":{"fight":"CharacterMagicianFight","hurt":"CharacterMagicianBeaten",""" +
                """"idle":"CharacterMagician"},"playerMaxHp":7,"startingSeconds":300}}"""
        const val PROBE_PING = """{"v":1,"type":"battle/ping","payload":{"echo":"spike-0.3"}}"""
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
        // Task 0.3 bridge probe teardown — replaced by the real adapter in Task 1.x.
        probeHandler.removeCallbacksAndMessages(null)
        JsbBridgeWrapper.getInstance()
            .removeScriptEventListener(EVENT_TO_NATIVE, probeListener)
        Log.i(tag, "CocosBattleActivity onDestroy")
    }
}
