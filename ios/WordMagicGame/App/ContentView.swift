import SwiftUI

struct ContentView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.09, green: 0.18, blue: 0.29),
                    Color(red: 0.13, green: 0.34, blue: 0.45),
                    Color(red: 0.93, green: 0.65, blue: 0.29),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 16) {
                Text(AppMetadata.displayName)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("AppTitle")

                Text(AppMetadata.scaffoldLabel)
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.86))
                    .accessibilityIdentifier("ScaffoldLabel")

                HStack(spacing: 12) {
                    phaseChip("Home")
                    phaseChip("Battle")
                    phaseChip("ParentAdmin")
                }
            }
            .padding(28)
        }
        .accessibilityIdentifier("RootView")
    }

    private func phaseChip(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color(red: 0.09, green: 0.18, blue: 0.29))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.white.opacity(0.92), in: Capsule())
            .accessibilityIdentifier("PhaseChip_\(title)")
    }
}

#Preview {
    ContentView()
}
