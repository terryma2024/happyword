// Mirror of iOS AppTheme (ios/WordMagicGame/App/AppCoordinator.swift:1076-1094)
// plus battle-specific colors from BattleView. Pure TS.

export const theme = {
    ink: '#212630',
    red: '#D62E2E',
    gold: '#F2AD38',
    blue: '#1459F0',
    navy: '#1A3052',
    purple: '#784AA3',
    paleBlue: '#DBEDFA',
    palePink: '#FAD1D1',
    page: '#FAFCFF',
    hpGreen: '#2EBF61',
    feedbackGreen: '#2EA659',
    // Feedback colors are washed out like SwiftUI's disabled buttons
    // (the native row disables all buttons during feedback).
    capsuleCorrect: '#95CBA4',
    capsuleWrong: '#E3A1A7',
    capsuleDisabled: '#D8DCE3',
    hpTrack: '#D8DEE6',
    textSecondary: '#6B7280',
    questionCaption: '#3B739C',
    white: '#FFFFFF',
} as const;

// Design resolution is 1280x720 (cocos project settings); the SwiftUI layout
// is authored in iPhone-landscape points (~852x393), so scale ~1.5x.
export const layout = {
    designWidth: 1280,
    designHeight: 720,
    fighterCardWidth: 330,
    fighterCardHeight: 415,
    fighterCardCornerRadius: 33,
    fighterCardPadding: 21,
    /// Character art fits (aspect-preserving) inside this square box.
    fighterSpriteFit: 185,
    hpBarHeight: 12,
    /// Native answer row: 9px page gutters + 27px spacing, buttons share the rest.
    answerRowContentWidth: 1262,
    answerRowSpacing: 27,
    answerCapsuleHeight: 93,
    answerRowY: -255,
    topStatusY: 308,
    fighterCardX: 465,
    fighterCardY: 42,
} as const;

/// Per-button width when `count` capsules share the answer row (native
/// .frame(maxWidth:.infinity) three-way split).
export function answerCapsuleWidth(count: number): number {
    const n = Math.max(1, count);
    return Math.floor((layout.answerRowContentWidth - (n - 1) * layout.answerRowSpacing) / n);
}
