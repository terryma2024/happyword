import SwiftUI

struct MonsterCodexView: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var currentIndex = 0

    private var entries: [MonsterCodexEntry] { MonsterCodex.entries }
    private var current: MonsterCodexEntry { entries[currentIndex] }
    private var hasPrevious: Bool { currentIndex > 0 }
    private var hasNext: Bool { currentIndex < entries.count - 1 }

    var body: some View {
        GeometryReader { proxy in
            let compactHeight = proxy.size.height < 460
            VStack(spacing: compactHeight ? 8 : 14) {
                topBar(compactHeight: compactHeight)

                Spacer(minLength: 0)

                avatarRow(compactHeight: compactHeight)
                    .frame(maxWidth: .infinity)

                VStack(spacing: compactHeight ? 5 : 8) {
                    Text(current.nameEn)
                        .font(.system(size: compactHeight ? 32 : 44, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppTheme.navy)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .accessibilityIdentifier("CodexName")

                    Text("「\(current.kindLabelZh)」")
                        .font(.system(size: compactHeight ? 16 : 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.23, green: 0.45, blue: 0.61))
                        .padding(.horizontal, 20)
                        .padding(.vertical, compactHeight ? 5 : 7)
                        .background(AppTheme.paleBlue, in: Capsule())
                        .accessibilityIdentifier("CodexKindLabel")

                    Text("\(currentIndex + 1) / \(entries.count)")
                        .font(.system(size: compactHeight ? 15 : 18, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .accessibilityIdentifier("CodexPositionIndicator")
                }

                Text(current.descriptionZh)
                    .font(.system(size: compactHeight ? 17 : 22, weight: .regular, design: .rounded))
                    .foregroundStyle(Color(red: 0.20, green: 0.20, blue: 0.21))
                    .lineSpacing(compactHeight ? 3 : 6)
                    .multilineTextAlignment(.center)
                    .lineLimit(compactHeight ? 2 : 3)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: min(proxy.size.width - 80, 980))
                    .accessibilityIdentifier("CodexDescription")

                Spacer(minLength: 0)
            }
            .padding(.horizontal, compactHeight ? 18 : 28)
            .padding(.top, compactHeight ? 10 : 18)
            .padding(.bottom, compactHeight ? 8 : 14)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(AppTheme.page)
    }

    private func topBar(compactHeight: Bool) -> some View {
        ZStack {
            HStack {
                MonsterCodexStyleBackButton(
                    action: { coordinator.route = .home },
                    compact: compactHeight,
                    accessibilityIdentifier: "CodexBackButton"
                )
                Spacer()
            }

            Text("怪物图鉴")
                .font(.system(size: compactHeight ? 34 : 42, weight: .heavy, design: .rounded))
                .foregroundStyle(AppTheme.navy)
                .accessibilityIdentifier("CodexTitle")
        }
    }

    private func avatarRow(compactHeight: Bool) -> some View {
        HStack(spacing: compactHeight ? 28 : 56) {
            navButton(
                systemName: "arrow.left",
                accessibilityLabel: "上一只",
                isEnabled: hasPrevious,
                compactHeight: compactHeight
            ) {
                guard hasPrevious else { return }
                currentIndex -= 1
            }
            .accessibilityIdentifier("CodexPrev")

            ZStack {
                RoundedRectangle(cornerRadius: compactHeight ? 22 : 28)
                    .fill(Color.white)
                    .overlay {
                        RoundedRectangle(cornerRadius: compactHeight ? 22 : 28)
                            .stroke(Color.gray.opacity(0.25), lineWidth: 1.5)
                    }
                Image(current.assetName)
                    .resizable()
                    .scaledToFit()
                    .padding(compactHeight ? 20 : 28)
            }
            .frame(width: compactHeight ? 158 : 220, height: compactHeight ? 136 : 204)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(current.nameEn)
            .accessibilityIdentifier("CodexAvatar")

            navButton(
                systemName: "arrow.right",
                accessibilityLabel: "下一只",
                isEnabled: hasNext,
                compactHeight: compactHeight
            ) {
                guard hasNext else { return }
                currentIndex += 1
            }
            .accessibilityIdentifier("CodexNext")
        }
    }

    private func navButton(
        systemName: String,
        accessibilityLabel: String,
        isEnabled: Bool,
        compactHeight: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: compactHeight ? 26 : 34, weight: .bold))
                .foregroundStyle(isEnabled ? .white : Color.gray)
                .frame(width: compactHeight ? 58 : 72, height: compactHeight ? 58 : 72)
                .background(isEnabled ? Color(red: 0.28, green: 0.51, blue: 0.68) : Color.gray.opacity(0.18), in: RoundedRectangle(cornerRadius: 14))
                .shadow(color: isEnabled ? AppTheme.navy.opacity(0.25) : .clear, radius: 3, y: 2)
        }
        .padding(compactHeight ? 18 : 24)
        .background((isEnabled ? AppTheme.red.opacity(0.10) : Color.white.opacity(0.55)), in: Circle())
        .disabled(!isEnabled)
        .accessibilityLabel(accessibilityLabel)
    }
}
