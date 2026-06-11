import os
import SwiftUI

/// Hosts the Cocos battle: the embedded runtime renders into its own
/// UIWindow above the app, so this view is a backdrop that owns the bridge
/// lifecycle, drives the countdown timer, and arms the ready-timeout
/// fallback to the native BattleView.
struct CocosBattleView: View {
    private static let logger = Logger(subsystem: "com.terryma.wordmagicgame", category: "cocosBattle")
    /// Seconds to wait for battle/ready before falling back to native.
    private static let readyTimeoutNs: UInt64 = 5_000_000_000

    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var engine: BattleEngine
    @State private var bridge: CocosBattleBridge?
    @State private var runtime: CocosRuntime?
    private let countdownTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        AppTheme.page
            .ignoresSafeArea()
            .accessibilityIdentifier("CocosBattleSurface")
            .onAppear(perform: startRuntime)
            .onDisappear(perform: stopRuntime)
            .onReceive(countdownTimer) { _ in
                guard engine.state.status == .playing else { return }
                coordinator.tickBattleCountdown()
                bridge?.sendStateTick()
            }
            .task {
                try? await Task.sleep(nanoseconds: Self.readyTimeoutNs)
                if let bridge, !bridge.isReady {
                    Self.logger.error("battle/ready timeout; falling back to native BattleView")
                    activateFallback()
                }
            }
    }

    private func startRuntime() {
        guard let made = CocosRuntimeFactory.make() else {
            Self.logger.error("cocos runtime unavailable; falling back to native BattleView")
            activateFallback()
            return
        }
        runtime = made
        let newBridge = CocosBattleBridge(coordinator: coordinator, runtime: made)
        bridge = newBridge
        if !newBridge.start() {
            Self.logger.error("cocos runtime failed to present; falling back to native BattleView")
            activateFallback()
        }
    }

    private func stopRuntime() {
        bridge?.stop()
        bridge = nil
        runtime = nil
    }

    private func activateFallback() {
        stopRuntime()
        coordinator.cocosBattleFallbackActive = true
        if DeveloperToolsPolicy.isDeveloperToolsVisible() {
            coordinator.showToast("Cocos 战斗启动失败，已切换原生战斗页")
        }
    }
}
