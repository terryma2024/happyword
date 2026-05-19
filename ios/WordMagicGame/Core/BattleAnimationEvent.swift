import Foundation

enum ProjectileDirection: Equatable {
    case forward
    case backward
}

enum FighterMotion: Equatable {
    case idle
    case nudge
    case hurt
    case cast
    case zoom
}

struct BattleAnimationEvent: Equatable {
    let projectileDirection: ProjectileDirection
    let projectileIntensity: Int
    let projectileLabel: String
    let playerMotion: FighterMotion
    let monsterMotion: FighterMotion
    let feedbackText: String
    let showsCritOverlay: Bool
    let damageLabel: String
    let playsMonsterDefeatCue: Bool

    /// V0.8.4 — Spell letter-pool wrong tap (player −1 HP, question unchanged).
    static func spellWrongTapPenalty(damage: Int) -> BattleAnimationEvent {
        BattleAnimationEvent(
            projectileDirection: .backward,
            projectileIntensity: damage,
            projectileLabel: "",
            playerMotion: .hurt,
            monsterMotion: .idle,
            feedbackText: "Try again",
            showsCritOverlay: false,
            damageLabel: "-\(damage)",
            playsMonsterDefeatCue: false,
        )
    }

    init(outcome: AnswerOutcome, word: String) {
        projectileLabel = word
        projectileIntensity = max(outcome.damage, 1)
        damageLabel = "-\(max(outcome.damage, 1))!"
        playsMonsterDefeatCue = outcome.monsterDefeated && !outcome.battleEnded

        if outcome.comboTriggered {
            projectileDirection = .forward
            playerMotion = .cast
            monsterMotion = .zoom
            feedbackText = "Combo 3! Magic Burst x\(max(outcome.damage, 1))"
            showsCritOverlay = true
        } else if outcome.correct {
            projectileDirection = .forward
            playerMotion = .nudge
            monsterMotion = .hurt
            feedbackText = "Correct!"
            showsCritOverlay = false
        } else {
            projectileDirection = .backward
            playerMotion = .hurt
            monsterMotion = .idle
            feedbackText = "Correct answer: \(word)"
            showsCritOverlay = false
        }
    }

    private init(
        projectileDirection: ProjectileDirection,
        projectileIntensity: Int,
        projectileLabel: String,
        playerMotion: FighterMotion,
        monsterMotion: FighterMotion,
        feedbackText: String,
        showsCritOverlay: Bool,
        damageLabel: String,
        playsMonsterDefeatCue: Bool,
    ) {
        self.projectileDirection = projectileDirection
        self.projectileIntensity = projectileIntensity
        self.projectileLabel = projectileLabel
        self.playerMotion = playerMotion
        self.monsterMotion = monsterMotion
        self.feedbackText = feedbackText
        self.showsCritOverlay = showsCritOverlay
        self.damageLabel = damageLabel
        self.playsMonsterDefeatCue = playsMonsterDefeatCue
    }
}
