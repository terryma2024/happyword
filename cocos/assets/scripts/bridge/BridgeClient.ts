// The only TS module that talks to the JSB bridge directly.
// Platform mechanics live in transport.ts; pure message codecs live in
// messages.ts (vitest-covered).

import { sys } from 'cc';
import { NativeToScriptMessage, ScriptToNativeMessage, parseNativeMessage, serializeScriptMessage } from './messages';
import { BridgeTransport, selectTransport } from './transport';

export class BridgeClient {
    onMessage: ((msg: NativeToScriptMessage) => void) | null = null;
    private transport: BridgeTransport | null = null;

    /// Selects the platform transport, registers the inbound listener and
    /// announces scene readiness.
    start() {
        if (!sys.isNative) { return; }
        this.transport = selectTransport();
        if (!this.transport) {
            console.warn('[bridge] no JSB transport available on this platform');
            return;
        }
        this.transport.onReceive((json: string) => {
            const msg = parseNativeMessage(json);
            if (msg && this.onMessage) { this.onMessage(msg); }
        });
        this.send({ type: 'battle/ready', payload: {} });
    }

    send(msg: ScriptToNativeMessage) {
        if (!this.transport) { return; }
        this.transport.send(serializeScriptMessage(msg));
    }
}
