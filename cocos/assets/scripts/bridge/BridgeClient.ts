// The only TS module that talks to the JSB bridge directly.
// Pure message codecs live in messages.ts (vitest-covered).

import { native, sys } from 'cc';
import { NativeToScriptMessage, ScriptToNativeMessage, parseNativeMessage, serializeScriptMessage } from './messages';

const TO_SCRIPT = 'wmBattleToScript';
const TO_NATIVE = 'wmBattleToNative';

export class BridgeClient {
    onMessage: ((msg: NativeToScriptMessage) => void) | null = null;

    /// Registers the native listener and announces scene readiness.
    start() {
        if (!sys.isNative) { return; }
        native.jsbBridgeWrapper.addNativeEventListener(TO_SCRIPT, (json: string) => {
            const msg = parseNativeMessage(json);
            if (msg && this.onMessage) { this.onMessage(msg); }
        });
        this.send({ type: 'battle/ready', payload: {} });
    }

    send(msg: ScriptToNativeMessage) {
        if (!sys.isNative) { return; }
        native.jsbBridgeWrapper.dispatchEventToNative(TO_NATIVE, serializeScriptMessage(msg));
    }
}
