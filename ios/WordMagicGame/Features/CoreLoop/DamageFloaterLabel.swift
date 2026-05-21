import SwiftUI

/// Visual tokens for a single HP damage floater (V0.8.3 §6.5).
struct DamageFloaterStyle: Equatable {
    var text: String
    var color: Color
    var fontSize: CGFloat
    var hasStroke: Bool
    var shadowRadius: CGFloat
    var shadowColor: Color
}

func pickFloaterStyle(amount: Int) -> DamageFloaterStyle {
    if amount >= 2 {
        return DamageFloaterStyle(
            text: "-2",
            color: Color(red: 0.50, green: 0.11, blue: 0.11),
            fontSize: 20,
            hasStroke: false,
            shadowRadius: 2,
            shadowColor: Color.black.opacity(0.4),
        )
    }
    return DamageFloaterStyle(
        text: "-1",
        color: Color(red: 0.97, green: 0.44, blue: 0.44),
        fontSize: 18,
        hasStroke: true,
        shadowRadius: 0,
        shadowColor: .clear,
    )
}

struct FloaterPending: Identifiable, Equatable {
    let id: Int
    let amount: Int
    let stackOffset: CGFloat
}

enum BattleFloaterSide {
    case player
    case monster
}

/// Short-lived "-1" / "-2" label that rises above a battle fighter card.
struct DamageFloaterLabel: View {
    let amount: Int
    let stackOffset: CGFloat
    let accessibilityId: String
    let onDispose: () -> Void

    @State private var labelOpacity = 0.0
    @State private var labelTranslateY: CGFloat = 0

    private let duration: TimeInterval = 0.45

    var body: some View {
        let style = pickFloaterStyle(amount: amount)
        Text(style.text)
            .font(.system(size: style.fontSize, weight: .bold, design: .rounded))
            .foregroundStyle(style.color)
            .shadow(
                color: style.hasStroke ? .white : style.shadowColor,
                radius: style.hasStroke ? 1 : style.shadowRadius,
                x: 0,
                y: style.hasStroke ? 0 : 1,
            )
            .opacity(labelOpacity)
            .offset(y: labelTranslateY)
            .accessibilityIdentifier(accessibilityId)
            .onAppear {
                playAnimation()
            }
    }

    private func playAnimation() {
        let half = duration / 2
        labelOpacity = 0
        labelTranslateY = 0

        withAnimation(.easeOut(duration: half)) {
            labelOpacity = 1
            labelTranslateY = -14 - stackOffset
        }

        Task {
            try? await Task.sleep(nanoseconds: UInt64(half * 1_000_000_000))
            await MainActor.run {
                withAnimation(.easeOut(duration: duration - half)) {
                    labelOpacity = 0
                    labelTranslateY = -28 - stackOffset
                }
            }
            try? await Task.sleep(nanoseconds: UInt64((duration - half) * 1_000_000_000))
            await MainActor.run {
                onDispose()
            }
        }
    }
}
