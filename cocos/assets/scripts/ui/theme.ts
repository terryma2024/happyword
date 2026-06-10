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
    hpTrack: '#D8DEE6',
    textSecondary: '#6B7280',
    white: '#FFFFFF',
} as const;

// Design resolution is 1280x720 (cocos project settings); the SwiftUI layout
// is authored in iPhone-landscape points (~852x393), so scale ~1.5x.
export const layout = {
    designWidth: 1280,
    designHeight: 720,
    fighterCardWidth: 250,
    fighterCardHeight: 460,
    fighterCardCornerRadius: 33,
    fighterSpriteSize: 220,
    hpBarWidth: 200,
    hpBarHeight: 14,
    answerCapsuleWidth: 320,
    answerCapsuleHeight: 76,
    answerRowY: -300,
    topStatusY: 320,
    fighterCardX: 465,
} as const;
