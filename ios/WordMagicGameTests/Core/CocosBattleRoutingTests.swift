@testable import WordMagicGame
import XCTest

@MainActor
final class CocosBattleRoutingTests: XCTestCase {
    private func makeCoordinator() -> AppCoordinator {
        AppCoordinator(
            configStore: GameConfigStore(defaults: UserDefaults(suiteName: "CocosRoutingTests-\(UUID().uuidString)")!),
            pronunciationService: SilentPronunciationService(),
            battleRandomSeed: 1
        )
    }

    private func isolatedDefaults() -> UserDefaults {
        UserDefaults(suiteName: "CocosRoutingTests.defaults.\(UUID().uuidString)")!
    }

    func testRuntimeNotLinkedUsesNative() {
        let coordinator = makeCoordinator()
        XCTAssertFalse(coordinator.shouldUseCocosBattleView(
            runtimeLinked: false, arguments: [], defaults: isolatedDefaults()
        ))
    }

    func testLinkedRuntimeUsesCocosByDefault() {
        let coordinator = makeCoordinator()
        XCTAssertTrue(coordinator.shouldUseCocosBattleView(
            runtimeLinked: true, arguments: [], defaults: isolatedDefaults()
        ))
    }

    func testFallbackFlagForcesNative() {
        let coordinator = makeCoordinator()
        coordinator.cocosBattleFallbackActive = true
        XCTAssertFalse(coordinator.shouldUseCocosBattleView(
            runtimeLinked: true, arguments: [], defaults: isolatedDefaults()
        ))
    }

    func testUITestArgumentForcesNative() {
        let coordinator = makeCoordinator()
        XCTAssertFalse(coordinator.shouldUseCocosBattleView(
            runtimeLinked: true, arguments: ["-UITestForceNativeBattle"], defaults: isolatedDefaults()
        ))
    }

    func testDevToggleForcesNativeInDebugBuilds() {
        let coordinator = makeCoordinator()
        let defaults = isolatedDefaults()
        defaults.set(true, forKey: "dev.useNativeBattleView")
        XCTAssertFalse(coordinator.shouldUseCocosBattleView(
            runtimeLinked: true, arguments: [], defaults: defaults
        ))
    }

    func testStartBattleResetsFallbackFlag() {
        let coordinator = makeCoordinator()
        coordinator.cocosBattleFallbackActive = true

        coordinator.startBattle()

        XCTAssertFalse(coordinator.cocosBattleFallbackActive)
        XCTAssertTrue(coordinator.shouldUseCocosBattleView(
            runtimeLinked: true, arguments: [], defaults: isolatedDefaults()
        ))
    }

    private final class SilentPronunciationService: PronunciationSpeaking {
        var isAvailable = true

        func prepare() {}
        func speak(_ word: String) {}
        func dispose() {}
    }
}
