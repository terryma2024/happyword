import UIKit

/// Abstraction over the embedded Cocos runtime so battle code is testable
/// without the engine linked (simulator builds, unit tests).
@MainActor
protocol CocosRuntime: AnyObject {
    /// Shows the Cocos window, booting the engine on first call.
    /// Returns false when the runtime is unavailable or failed to boot.
    func present() -> Bool
    /// Pauses the engine and hides the Cocos window.
    func dismiss()
    func send(json: String)
    func setScriptMessageHandler(_ handler: ((String) -> Void)?)
}

enum CocosRuntimeFactory {
    /// True when the Cocos engine is linked into this build (device builds
    /// only; the simulator shim is a stub).
    static var isRuntimeLinked: Bool { WMCocosRuntimeShim.isLinked }

    @MainActor
    static func make() -> CocosRuntime? {
        guard isRuntimeLinked else { return nil }
        return ShimCocosRuntime()
    }
}

@MainActor
private final class ShimCocosRuntime: CocosRuntime {
    func present() -> Bool { WMCocosRuntimeShim.shared().presentCocosWindow() }
    func dismiss() { WMCocosRuntimeShim.shared().dismissCocosWindow() }
    func send(json: String) { WMCocosRuntimeShim.shared().send(toScript: json) }
    func setScriptMessageHandler(_ handler: ((String) -> Void)?) {
        WMCocosRuntimeShim.shared().setScriptHandler(handler)
    }
}
