// Platform JSB transport abstraction (Task 0.3, HarmonyOS bridge spike).
//
// BridgeClient picks the first `available` transport at start(); all JSON
// strings flow through this interface so the scene code never branches on
// platform. Codecs stay in messages.ts (pure TS, vitest-covered).
//
// iOS / Android: native.jsbBridgeWrapper (JsbBridgeWrapper event bus).
// HarmonyOS NEXT (OPENHARMONY): jsbBridgeWrapper is *null* — the engine only
// compiles ScriptNativeBridge for ANDROID/IOS/OSX/OHOS, not OPENHARMONY
// (cocos/native-binding/impl.ts). Instead:
//   * scene -> ArkTS: native.reflection.callStaticMethod(...) backed by
//     JavaScriptArkTsBridge. The engine invokes the host-registered
//     'executeMethodAsync' threadsafe function, which loads the ArkTS module
//     CLS_PATH on the UI thread and calls its exported METHOD with
//     (json, done). NOTE: the engine BLOCKS the game thread on an internal
//     promise until the ArkTS side invokes done() — the receiver must call
//     it immediately.
//   * ArkTS -> scene: the host calls libcocos.so's evalString(), which
//     schedules JS on the game thread; the scene pre-registers
//     globalThis.__wmBattleInbound as the entry point.

import { native } from 'cc';

export interface BridgeTransport {
    readonly available: boolean;
    send(json: string): void;
    onReceive(handler: (json: string) => void): void;
}

const TO_SCRIPT = 'wmBattleToScript';
const TO_NATIVE = 'wmBattleToNative';

/** iOS (and later Android): the engine's JsbBridgeWrapper event bus. */
export class JsbWrapperTransport implements BridgeTransport {
    get available(): boolean {
        return !!(native as { jsbBridgeWrapper?: unknown } | undefined)?.jsbBridgeWrapper;
    }

    send(json: string): void {
        native.jsbBridgeWrapper.dispatchEventToNative(TO_NATIVE, json);
    }

    onReceive(handler: (json: string) => void): void {
        native.jsbBridgeWrapper.addNativeEventListener(TO_SCRIPT, handler);
    }
}

/** Module path loaded via napi_load_module_with_info on the ArkTS UI thread.
 *  Must stay in sync with harmonyos/entry/src/main/ets/services/
 *  CocosBridgeReceiver.ets AND its runtimeOnly registration in
 *  harmonyos/entry/build-profile.json5. */
const ARKTS_RECEIVER_CLS_PATH = 'entry/src/main/ets/services/CocosBridgeReceiver';
/** Top-level exported function (json: string, done: (r: string) => void). */
const ARKTS_RECEIVER_METHOD = 'onSceneMessage';
/** Game-thread global invoked by the host via libcocos.so evalString(). */
const ARKTS_INBOUND_GLOBAL = '__wmBattleInbound';

/** HarmonyOS NEXT: JavaScriptArkTsBridge reflection out, evalString in. */
export class ArkTsReflectionTransport implements BridgeTransport {
    get available(): boolean {
        const g = globalThis as Record<string, unknown>;
        const n = native as { reflection?: unknown } | undefined;
        return !!g.JavaScriptArkTsBridge && !!n?.reflection;
    }

    send(json: string): void {
        // 4th parameter false => async path (executeMethodAsync). The game
        // thread still blocks until the ArkTS receiver calls done().
        native.reflection.callStaticMethod(
            ARKTS_RECEIVER_CLS_PATH, ARKTS_RECEIVER_METHOD, json, false);
    }

    onReceive(handler: (json: string) => void): void {
        (globalThis as Record<string, unknown>)[ARKTS_INBOUND_GLOBAL] = handler;
    }
}

/** Probe order matters: jsbBridgeWrapper is the iOS mechanism and is null on
 *  OpenHarmony; reflection exists only where JavaScriptArkTsBridge is bound. */
export function selectTransport(): BridgeTransport | null {
    const candidates: BridgeTransport[] = [
        new JsbWrapperTransport(),
        new ArkTsReflectionTransport(),
    ];
    for (const transport of candidates) {
        if (transport.available) { return transport; }
    }
    return null;
}
