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
}
