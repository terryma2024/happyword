import SwiftUI

struct MonsterCodexView: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var currentIndex = 0

    private var entries: [MonsterCodexEntry] { MonsterCodex.entries }
    private var current: MonsterCodexEntry { entries[currentIndex] }
    private var currentCatalogIndex: Int { currentIndex + 1 }
    private var currentProgress: MonsterProgressRecord {
        coordinator.monsterProgressStore.record(for: currentCatalogIndex)
    }
    private var currentEncountered: Bool { currentProgress.encountered }
    private var currentAssetName: String {
        currentEncountered ? current.assetName : MonsterProgressStore.mysteryAssetName
    }
    private var currentDisplayName: String {
        currentEncountered ? current.nameEn : MonsterProgressStore.maskedQuestionMarks(current.nameEn)
    }
    private var currentKindLabel: String {
        currentEncountered ? current.kindLabelZh : MonsterProgressStore.maskedQuestionMarks(current.kindLabelZh)
    }
    private var currentDescription: String {
        currentEncountered ? current.descriptionZh : MonsterProgressStore.maskedQuestionMarks(current.descriptionZh)
    }
    private var hasPrevious: Bool { currentIndex > 0 }
    private var hasNext: Bool { currentIndex < entries.count - 1 }

    var body: some View {
        GeometryReader { proxy in
            let compactHeight = proxy.size.height < 460
            VStack(spacing: compactHeight ? 8 : 14) {
                topBar(compactHeight: compactHeight)

                ScrollView {
                    VStack(spacing: compactHeight ? 7 : 12) {
                        avatarRow(compactHeight: compactHeight)
                            .frame(maxWidth: .infinity)

                        nameBlock(compactHeight: compactHeight)

                        Text(currentDescription)
                            .font(.system(size: compactHeight ? 14 : 22, weight: .regular, design: .rounded))
                            .foregroundStyle(Color(red: 0.20, green: 0.20, blue: 0.21))
                            .lineSpacing(compactHeight ? 2 : 6)
                            .multilineTextAlignment(.center)
                            .lineLimit(compactHeight ? 2 : 3)
                            .minimumScaleFactor(0.65)
                            .frame(maxWidth: min(proxy.size.width - 80, 980))
                            .accessibilityIdentifier("CodexDescription")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, compactHeight ? 2 : 12)
                    .padding(.bottom, compactHeight ? 8 : 14)
                }
            }
            .padding(.horizontal, AppTheme.pageHorizontalPadding)
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
                Image(currentAssetName)
                    .resizable()
                    .scaledToFit()
                    .padding(compactHeight ? 20 : 28)
            }
            .frame(width: compactHeight ? 158 : 220, height: compactHeight ? 136 : 204)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(currentEncountered ? current.nameEn : "未知怪物")
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

    private func nameBlock(compactHeight: Bool) -> some View {
        VStack(spacing: compactHeight ? 4 : 7) {
            HStack(spacing: 8) {
                Text(currentDisplayName)
                    .font(.system(size: compactHeight ? 22 : 44, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppTheme.navy)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .accessibilityIdentifier("CodexName")

                Text(current.levelBadgeZh)
                    .font(.system(size: compactHeight ? 11 : 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, compactHeight ? 8 : 16)
                    .padding(.vertical, compactHeight ? 3 : 6)
                    .background(AppTheme.red, in: Capsule())
                    .accessibilityIdentifier("MonsterCodexLevelBadge_\(current.key)")
            }

            Text("「\(currentKindLabel)」")
                .font(.system(size: compactHeight ? 13 : 20, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.23, green: 0.45, blue: 0.61))
                .padding(.horizontal, 20)
                .padding(.vertical, compactHeight ? 4 : 7)
                .background(AppTheme.paleBlue, in: Capsule())
                .accessibilityIdentifier("CodexKindLabel")

            Text("\(currentIndex + 1) / \(entries.count)")
                .font(.system(size: compactHeight ? 12 : 18, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .accessibilityIdentifier("CodexPositionIndicator")

            if currentEncountered {
                Text("击败 \(currentProgress.defeatCount) 次")
                    .font(.system(size: compactHeight ? 12 : 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.navy)
                    .accessibilityIdentifier("CodexDefeatCount")

                rewardRow(compactHeight: compactHeight)
            }
        }
    }

    private func rewardRow(compactHeight: Bool) -> some View {
        HStack(spacing: compactHeight ? 8 : 10) {
            rewardButton(milestone: 50, identifier: "CodexReward50Button", compactHeight: compactHeight)
            rewardButton(milestone: 100, identifier: "CodexReward100Button", compactHeight: compactHeight)
        }
    }

    private func rewardButton(milestone: Int, identifier: String, compactHeight: Bool) -> some View {
        let state = coordinator.monsterProgressStore.rewardState(catalogIndex: currentCatalogIndex, milestone: milestone)
        return Button {
            coordinator.claimMonsterCodexReward(catalogIndex: currentCatalogIndex, milestone: milestone)
        } label: {
            Text(state.label)
                .font(.system(size: compactHeight ? 12 : 15, weight: .heavy, design: .rounded))
                .foregroundStyle(state.enabled ? Color(red: 0.31, green: 0.23, blue: 0.00) : Color(red: 0.48, green: 0.53, blue: 0.58))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, compactHeight ? 12 : 16)
                .frame(height: compactHeight ? 28 : 38)
                .background(state.enabled ? AppTheme.gold : Color(red: 0.93, green: 0.94, blue: 0.96), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!state.enabled)
        .accessibilityIdentifier(identifier)
    }
}
