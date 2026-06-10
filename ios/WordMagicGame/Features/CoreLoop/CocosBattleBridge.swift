import Foundation
import os

/// Translates engine state and outcomes into bridge messages for the Cocos
/// battle scene, and routes user intents from the scene back into the
/// existing coordinator battle methods. Battle logic stays in BattleEngine;
/// this type only mirrors what the native BattleView does around it
/// (see BattleView.handleOptionTap / triggerAnimation / presentBossIntroIfNeeded).
@MainActor
final class CocosBattleBridge {
    private static let logger = Logger(subsystem: "com.terryma.wordmagicgame", category: "cocosBattle")
    /// Mirrors BattleView.clearFeedbackAfterDelay (650 ms feedback hold).
    private static let feedbackHoldNs: UInt64 = 650_000_000

    private weak var coordinator: AppCoordinator?
    private let runtime: CocosRuntime
    private(set) var isReady = false
    private var shownBossIntroCatalogIndices: Set<Int> = []
    private var lastBossIntroMonsterIndex = 0

    init(coordinator: AppCoordinator, runtime: CocosRuntime) {
        self.coordinator = coordinator
        self.runtime = runtime
        runtime.setScriptMessageHandler { [weak self] json in
            // The shim delivers on the main queue; mocks call from MainActor tests.
            MainActor.assumeIsolated {
                self?.handleScriptMessage(json)
            }
        }
    }

    func start() -> Bool {
        let resuming = runtime.isEngineBooted
        guard runtime.present() else { return false }
        if resuming {
            // The scene is already alive and won't send battle/ready again;
            // battle/init acts as a full scene reset (see contract README).
            handleReady()
        }
        return true
    }

    func stop() {
        runtime.setScriptMessageHandler(nil)
        runtime.dismiss()
    }

    /// Called by the hosting view's countdown timer after tickBattleCountdown().
    func sendStateTick() {
        sendState()
    }

    func handleScriptMessage(_ json: String) {
        guard let message = try? CocosBridgeInbound.decode(from: Data(json.utf8)) else {
            Self.logger.warning("ignoring unknown bridge message")
            return
        }
        switch message {
        case .ready:
            handleReady()
        case .submitOption(let option):
            handleSubmit(option)
        case .spellWrongTap:
            handleSpellWrongTap()
        case .speakAnswer:
            coordinator?.speakCurrentBattleAnswer()
        case .escape:
            coordinator?.escapeBattle()
        case .pong:
            break
        }
    }

    // MARK: - Inbound handlers

    private func handleReady() {
        isReady = true
        sendInit()
        sendState()
        sendQuestion()
        maybeSendBossIntro()
        coordinator?.autoSpeakCurrentBattleAnswer(isRevealing: false)
    }

    /// Mirrors BattleView.handleOptionTap (BattleView.swift:709-726).
    private func handleSubmit(_ option: String) {
        guard let coordinator, let engine = coordinator.battleEngine else { return }
        let word = engine.state.currentQuestion?.answer ?? ""
        guard let outcome = coordinator.submitBattleOptionForAnimation(option) else { return }

        if outcome.advancedStep {
            // fill-letter-medium step advance: no damage, no animation.
            sendState()
            sendQuestion()
            return
        }

        let event = BattleAnimationEvent(outcome: outcome, word: word)
        coordinator.playBattleSfx(BattleSfx.cue(for: event))
        if event.playsMonsterDefeatCue {
            coordinator.playBattleSfx(.monsterDefeat)
        }
        send(.animation(BattleAnimationPayload(event: event, outcome: outcome)))
        sendState()

        if outcome.battleEnded {
            finishAfterFeedbackHold(status: outcome.endStatus)
        } else {
            sendQuestion()
            maybeSendBossIntro()
            coordinator.autoSpeakCurrentBattleAnswer(isRevealing: false)
        }
    }

    /// Mirrors the spell wrong-tap path (BattleView spell pool handling).
    private func handleSpellWrongTap() {
        guard let coordinator, let engine = coordinator.battleEngine else { return }
        let damage = engine.applySpellLetterPenalty()
        guard damage > 0 else { return }

        let event = BattleAnimationEvent.spellWrongTapPenalty(damage: damage)
        coordinator.playBattleSfx(BattleSfx.cue(for: event))
        let lost = engine.state.status == .lost
        send(.animation(BattleAnimationPayload(event: event, battleEnded: lost)))
        sendState()
        if lost {
            finishAfterFeedbackHold(status: .lost)
        }
    }

    private func finishAfterFeedbackHold(status: BattleStatus?) {
        send(.end(BattleEndPayload(status: status == .won ? "won" : "lost")))
        Task {
            try? await Task.sleep(nanoseconds: Self.feedbackHoldNs)
            self.coordinator?.finishBattle()
        }
    }

    // MARK: - Outbound

    private func sendInit() {
        guard let engine = coordinator?.battleEngine else { return }
        let state = engine.state
        send(.initialize(BattleInitPayload(
            playerMaxHp: state.playerMaxHp,
            monsterMaxHp: state.monsterMaxHp,
            monstersTotal: state.monstersTotal,
            startingSeconds: state.remainingSeconds,
            playerArt: PlayerArtPayload(
                idle: "CharacterMagician",
                fight: "CharacterMagicianFight",
                hurt: "CharacterMagicianBeaten"
            )
        )))
    }

    private func sendState() {
        guard let engine = coordinator?.battleEngine else { return }
        let state = engine.state
        let entry = MonsterCodex.entry(catalogIndex1Based: state.currentMonsterCatalogIndex)
        send(.state(BattleStatePayload(
            playerHp: state.playerHp,
            playerMaxHp: state.playerMaxHp,
            monsterHp: state.monsterHp,
            monsterMaxHp: state.monsterMaxHp,
            monsterIndex: state.monsterIndex,
            monstersTotal: state.monstersTotal,
            remainingSeconds: state.remainingSeconds,
            comboCount: state.comboCount,
            status: state.status.rawValue,
            monster: MonsterArtPayload(
                catalogIndex: state.currentMonsterCatalogIndex,
                imageKey: entry.assetName,
                name: entry.nameEn,
                levelLabel: entry.level.battleLabel,
                bonus: state.currentMonsterBonus
            )
        )))
    }

    private func sendQuestion() {
        guard let question = coordinator?.battleEngine?.state.currentQuestion else { return }
        send(.question(BattleQuestionPayload(question: question)))
    }

    /// Mirrors BattleView.presentBossIntroIfNeeded (BattleView.swift:1142-1175);
    /// the scene owns the 1.05 s auto-dismiss.
    private func maybeSendBossIntro() {
        guard let engine = coordinator?.battleEngine, engine.state.status == .playing else { return }
        let catalogIndex = engine.state.currentMonsterCatalogIndex
        guard engine.state.monsterIndex != lastBossIntroMonsterIndex,
              !shownBossIntroCatalogIndices.contains(catalogIndex)
        else { return }

        let entry = MonsterCodex.entry(catalogIndex1Based: catalogIndex)
        let dialogue = MonsterDialogueCatalog.resolve(catalogIndex1Based: catalogIndex, monsterName: entry.nameEn)
        send(.bossIntro(BattleBossIntroPayload(
            monsterIndex: engine.state.monsterIndex,
            name: entry.nameEn,
            introLineEn: dialogue.introLine.en,
            introLineZh: dialogue.introLine.zh
        )))
        shownBossIntroCatalogIndices.insert(catalogIndex)
        lastBossIntroMonsterIndex = engine.state.monsterIndex
    }

    private func send(_ outbound: CocosBridgeOutbound) {
        do {
            runtime.send(json: try outbound.encodedJSON())
        } catch {
            Self.logger.error("bridge encode failed: \(error.localizedDescription)")
        }
    }
}

extension BattleAnimationPayload {
    init(event: BattleAnimationEvent, outcome: AnswerOutcome) {
        self.init(
            projectileDirection: event.projectileDirection == .forward ? "forward" : "backward",
            projectileIntensity: event.projectileIntensity,
            projectileLabel: event.projectileLabel,
            playerMotion: Self.motionName(event.playerMotion),
            monsterMotion: Self.motionName(event.monsterMotion),
            feedbackText: event.feedbackText,
            showsCritOverlay: event.showsCritOverlay,
            damageLabel: event.damageLabel,
            playsMonsterDefeatCue: event.playsMonsterDefeatCue,
            correct: outcome.correct,
            comboTriggered: outcome.comboTriggered,
            battleEnded: outcome.battleEnded
        )
    }

    init(event: BattleAnimationEvent, battleEnded: Bool) {
        self.init(
            projectileDirection: event.projectileDirection == .forward ? "forward" : "backward",
            projectileIntensity: event.projectileIntensity,
            projectileLabel: event.projectileLabel,
            playerMotion: Self.motionName(event.playerMotion),
            monsterMotion: Self.motionName(event.monsterMotion),
            feedbackText: event.feedbackText,
            showsCritOverlay: event.showsCritOverlay,
            damageLabel: event.damageLabel,
            playsMonsterDefeatCue: event.playsMonsterDefeatCue,
            correct: false,
            comboTriggered: false,
            battleEnded: battleEnded
        )
    }

    private static func motionName(_ motion: FighterMotion) -> String {
        switch motion {
        case .idle: "idle"
        case .nudge: "nudge"
        case .hurt: "hurt"
        case .cast: "cast"
        case .zoom: "zoom"
        }
    }
}
