import SwiftUI

/// Circular white back control matching `MonsterCodexView` top navigation.
struct MonsterCodexStyleBackButton: View {
    let action: () -> Void
    /// When `true`, uses the compact Codex metrics (54×54, 24pt icon). When `false`, 70×70 / 32pt.
    var compact: Bool = true
    var accessibilityIdentifier: String

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.left")
                .font(.system(size: compact ? 24 : 32, weight: .bold))
                .foregroundStyle(AppTheme.navy)
                .frame(width: compact ? 54 : 70, height: compact ? 54 : 70)
                .background(Color.white, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("返回")
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
