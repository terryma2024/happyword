import Foundation

/// Phase 0 spike: boots the embedded Cocos runtime, round-trips a ping/pong
/// over the JSB bridge, then dismisses the Cocos window. Temporary — replaced
/// by the battle integration in Phase 2.
///
/// Triggered from the DevMenu CocosLab button, or automatically at startup
/// with the `-CocosLabAutoRun` launch argument (device debugging).
@MainActor
enum CocosLabSpike {
    static func run(coordinator: AppCoordinator) {
        let shim = WMCocosRuntimeShim.shared()
        guard WMCocosRuntimeShim.isLinked else {
            coordinator.showToast("Cocos runtime not linked (simulator build)")
            return
        }

        shim.setScriptHandler { json in
            NSLog("[CocosLabSpike] received: %@", json)
            guard let data = json.data(using: .utf8),
                  let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = message["type"] as? String
            else { return }

            switch type {
            case "battle/ready":
                NSLog("[CocosLabSpike] ready -> sending ping")
                shim.send(toScript: #"{"v":1,"type":"battle/ping","payload":{"echo":"spike"}}"#)
            case "battle/pong":
                let payload = message["payload"] as? [String: Any]
                let echo = payload?["echo"] as? String ?? "?"
                NSLog("[CocosLabSpike] pong received (echo: %@)", echo)
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    shim.dismissCocosWindow()
                    shim.setScriptHandler(nil)
                    coordinator.showToast("Cocos pong OK (echo: \(echo))")
                }
            default:
                break
            }
        }

        NSLog("[CocosLabSpike] presenting cocos window")
        guard shim.presentCocosWindow() else {
            coordinator.showToast("Cocos runtime failed to boot")
            return
        }

        // Spike diagnostics: check loop/JS state a few seconds after boot.
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            shim.debugProbe()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            shim.debugProbe()
        }

        // Safety net: never leave the Cocos window stuck over the app.
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
            shim.dismissCocosWindow()
        }
    }
}
