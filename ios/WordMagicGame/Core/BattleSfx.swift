import Foundation

/// Maps a battle animation event to its sound cue. Shared by the native
/// BattleView and the Cocos battle bridge so both presentation layers play
/// identical audio.
enum BattleSfx {
    static func cue(for event: BattleAnimationEvent) -> BattleSfxCue {
        if event.showsCritOverlay {
            return .comboHit
        }
        switch event.projectileDirection {
        case .forward:
            return .normalHit
        case .backward:
            return event.playerMotion == .hurt ? .hurt : .wrong
        }
    }
}
