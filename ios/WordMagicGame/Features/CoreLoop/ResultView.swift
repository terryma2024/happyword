import SwiftUI

struct ResultView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        let result = coordinator.lastResult
        VStack(spacing: 14) {
            Text(result?.status == .won ? "胜利" : "继续练习")
                .font(.system(size: 38, weight: .heavy, design: .rounded))
                .foregroundStyle(AppTheme.navy)
                .accessibilityIdentifier("ResultTitle")

            Text(String(repeating: "★", count: result?.stars ?? 0))
                .font(.system(size: 42, weight: .heavy))
                .foregroundStyle(AppTheme.gold)
                .accessibilityIdentifier("ResultStars")

            HStack(spacing: 12) {
                stat("击败怪物", "\(result?.defeatedMonsters ?? 0)/\(result?.monstersTotal ?? 0)")
                stat("正确率", "\(Int((result?.correctRate ?? 0) * 100))%")
                    .accessibilityIdentifier("ResultAccuracy")
                stat("学习单词", "\(result?.learnedWordCount ?? 0)")
                stat("获得金币", "+\(result?.coinsEarned ?? 0)")
                    .accessibilityIdentifier("ResultCoinsEarned")
                stat("金币总数", "\(result?.coinsTotal ?? 0)")
                    .accessibilityIdentifier("ResultCoinsTotal")
            }

            Button("返回主页") {
                coordinator.battleEngine = nil
                coordinator.route = .home
            }
            .font(.title3.weight(.heavy))
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(AppTheme.red)
            .controlSize(.large)
            .accessibilityIdentifier("ResultHomeButton")
        }
        .padding(.horizontal, AppTheme.pageHorizontalPadding)
        .padding(.vertical, 24)
        .frame(maxWidth: 720)
        .background(AppTheme.cream, in: RoundedRectangle(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .stroke(AppTheme.gold.opacity(0.5), lineWidth: 1.5)
        }
        .padding(.horizontal, AppTheme.pageHorizontalPadding)
        .padding(.vertical, 24)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 5) {
            Text(value)
                .font(.title2.weight(.heavy))
                .foregroundStyle(AppTheme.navy)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(width: 104)
        .padding(.vertical, 10)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
    }
}
