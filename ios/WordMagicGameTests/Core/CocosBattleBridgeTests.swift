@testable import WordMagicGame
import XCTest

@MainActor
final class CocosBattleBridgeTests: XCTestCase {
    private final class MockCocosRuntime: CocosRuntime {
        var sent: [String] = []
        var handler: ((String) -> Void)?
        var presented = false
        var isEngineBooted = false

        func present() -> Bool { presented = true; return true }
        func dismiss() { presented = false }
        func send(json: String) { sent.append(json) }
        func setScriptMessageHandler(_ handler: ((String) -> Void)?) { self.handler = handler }

        func inject(_ json: String) { handler?(json) }

        var sentTypes: [String] {
            sent.compactMap { json in
                (try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])?["type"] as? String
            }
        }

        func lastPayload(ofType type: String) -> [String: Any]? {
            for json in sent.reversed() {
                guard let envelope = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
                      envelope["type"] as? String == type
                else { continue }
                return envelope["payload"] as? [String: Any]
            }
            return nil
        }
    }

    /// Keeps coordinator + bridge alive together: the bridge holds the
    /// coordinator weakly and the runtime calls the bridge weakly, so a
    /// discarded tuple element silently kills the chain.
    private struct BattleContext {
        let coordinator: AppCoordinator
        let runtime: MockCocosRuntime
        let bridge: CocosBattleBridge
    }

    private func makeBattle(monstersTotal: Int = 2) -> BattleContext {
        let coordinator = AppCoordinator(
            configStore: GameConfigStore(defaults: UserDefaults(suiteName: "CocosBattleBridgeTests-\(UUID().uuidString)")!),
            pronunciationService: SilentPronunciationService(),
            battleRandomSeed: 1
        )
        var config = coordinator.configStore.config
        config.monstersTotal = monstersTotal
        config.monsterMaxHp = 1
        coordinator.configStore.save(config)
        coordinator.startBattle()

        let runtime = MockCocosRuntime()
        let bridge = CocosBattleBridge(coordinator: coordinator, runtime: runtime)
        return BattleContext(coordinator: coordinator, runtime: runtime, bridge: bridge)
    }

    func testReadySendsInitStateQuestion() throws {
        let ctx = makeBattle()
        let runtime = ctx.runtime
        let bridge = ctx.bridge

        runtime.inject(#"{"v":1,"type":"battle/ready","payload":{}}"#)

        XCTAssertTrue(bridge.isReady)
        XCTAssertEqual(Array(runtime.sentTypes.prefix(3)), ["battle/init", "battle/state", "battle/question"])
        // First monster encounter sends its intro too.
        XCTAssertTrue(runtime.sentTypes.contains("battle/bossIntro"))
    }

    func testSubmitCorrectOptionSendsAnimationStateQuestion() throws {
        let ctx = makeBattle(monstersTotal: 5)
        let coordinator = ctx.coordinator
        let runtime = ctx.runtime
        runtime.inject(#"{"v":1,"type":"battle/ready","payload":{}}"#)
        let answer = try XCTUnwrap(coordinator.battleEngine?.state.currentQuestion?.answer)
        let answersBefore = try XCTUnwrap(coordinator.battleEngine?.state.totalAnswers)
        runtime.sent.removeAll()

        runtime.inject(#"{"v":1,"type":"battle/submitOption","payload":{"option":"\#(answer)"}}"#)

        XCTAssertEqual(coordinator.battleEngine?.state.totalAnswers, answersBefore + 1)
        XCTAssertEqual(Array(runtime.sentTypes.prefix(3)), ["battle/animation", "battle/state", "battle/question"])
        let animation = try XCTUnwrap(runtime.lastPayload(ofType: "battle/animation"))
        XCTAssertEqual(animation["correct"] as? Bool, true)
    }

    func testWinningFinalMonsterSendsEndAndRoutesToResult() throws {
        let ctx = makeBattle(monstersTotal: 1)
        let coordinator = ctx.coordinator
        let runtime = ctx.runtime
        runtime.inject(#"{"v":1,"type":"battle/ready","payload":{}}"#)
        let answer = try XCTUnwrap(coordinator.battleEngine?.state.currentQuestion?.answer)

        runtime.inject(#"{"v":1,"type":"battle/submitOption","payload":{"option":"\#(answer)"}}"#)

        XCTAssertTrue(runtime.sentTypes.contains("battle/end"))
        let end = try XCTUnwrap(runtime.lastPayload(ofType: "battle/end"))
        XCTAssertEqual(end["status"] as? String, "won")

        let routed = expectation(description: "routes to result after feedback hold")
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            routed.fulfill()
        }
        wait(for: [routed], timeout: 3)
        XCTAssertEqual(coordinator.route, .result)
    }

    func testSpellWrongTapSendsPenaltyAnimationAndState() throws {
        let ctx = makeBattle()
        let coordinator = ctx.coordinator
        let runtime = ctx.runtime
        runtime.inject(#"{"v":1,"type":"battle/ready","payload":{}}"#)
        let hpBefore = try XCTUnwrap(coordinator.battleEngine?.state.playerHp)
        runtime.sent.removeAll()

        runtime.inject(#"{"v":1,"type":"battle/spellWrongTap","payload":{}}"#)

        XCTAssertEqual(coordinator.battleEngine?.state.playerHp, hpBefore - 1)
        XCTAssertEqual(Array(runtime.sentTypes.prefix(2)), ["battle/animation", "battle/state"])
        let animation = try XCTUnwrap(runtime.lastPayload(ofType: "battle/animation"))
        XCTAssertEqual(animation["feedbackText"] as? String, "Try again")
    }

    func testEscapeRoutesToResult() throws {
        let ctx = makeBattle()
        let coordinator = ctx.coordinator
        let runtime = ctx.runtime
        runtime.inject(#"{"v":1,"type":"battle/ready","payload":{}}"#)

        runtime.inject(#"{"v":1,"type":"battle/escape","payload":{}}"#)

        XCTAssertEqual(coordinator.route, .result)
    }

    func testGarbageMessageIsIgnored() throws {
        let ctx = makeBattle()
        let runtime = ctx.runtime
        let bridge = ctx.bridge

        runtime.inject("not json at all")
        runtime.inject(#"{"v":1,"type":"battle/unknown","payload":{}}"#)

        XCTAssertFalse(bridge.isReady)
        XCTAssertTrue(runtime.sent.isEmpty)
    }

    private final class SilentPronunciationService: PronunciationSpeaking {
        var isAvailable = true

        func prepare() {}
        func speak(_ word: String) {}
        func dispose() {}
    }
}
