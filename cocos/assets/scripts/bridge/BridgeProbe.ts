import { _decorator, Component, native, sys } from 'cc';
const { ccclass } = _decorator;

const TO_SCRIPT = 'wmBattleToScript';
const TO_NATIVE = 'wmBattleToNative';

@ccclass('BridgeProbe')
export class BridgeProbe extends Component {
    onLoad() {
        if (!sys.isNative) return;
        native.jsbBridgeWrapper.addNativeEventListener(TO_SCRIPT, (json: string) => {
            const msg = JSON.parse(json);
            if (msg.type === 'battle/ping') {
                native.jsbBridgeWrapper.dispatchEventToNative(
                    TO_NATIVE,
                    JSON.stringify({ v: 1, type: 'battle/pong', payload: { echo: msg.payload.echo } })
                );
            }
        });
        native.jsbBridgeWrapper.dispatchEventToNative(
            TO_NATIVE,
            JSON.stringify({ v: 1, type: 'battle/ready', payload: {} })
        );
    }
}
