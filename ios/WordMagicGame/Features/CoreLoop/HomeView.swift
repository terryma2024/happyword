import SwiftUI

struct HomeView: View {
    @ObservedObject var coordinator: AppCoordinator

    private var scenePalette: HomeScenePalette {
        HomeScenePalette(scene: coordinator.selectedPack.scene)
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 9) {
                topBar

                Text("Small Magician Word Adventure")
                    .font(.system(size: min(proxy.size.width * 0.046, 30), weight: .heavy, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                    .accessibilityIdentifier("HomeTitle")

                adventureCard
                    .frame(maxHeight: .infinity)
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 10)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(AppTheme.page)
    }

    private var topBar: some View {
        let childProfileLabel = "孩子档案 \(coordinator.currentChildNickname())"
        return HStack(spacing: 12) {
            Text("v0.7 iOS")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            if coordinator.showsChildProfileShortcut {
                Button {
                    coordinator.openBoundDeviceInfo()
                } label: {
                    badge(
                        "\(coordinator.currentChildAvatarEmoji()) \(coordinator.currentChildNickname())",
                        tint: AppTheme.paleBlue,
                        foreground: Color(red: 0.02, green: 0.42, blue: 0.66)
                    )
                    .accessibilityIdentifier("HomeChildProfileButton")
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(childProfileLabel)
                .accessibilityIdentifier("HomeChildProfileButton")
            }
            badge("金币 \(coordinator.coinAccount.balance)", tint: AppTheme.cream, foreground: AppTheme.gold)
                .accessibilityIdentifier("HomeCoinBalance")
            toolbarButton("ToolbarReview", label: "计划", action: coordinator.openTodayPlan)
            toolbarButton("ToolbarCodex", label: "图鉴", action: coordinator.openMonsterCodex)
            toolbarEmojiButton("📋", label: "学习报告", action: coordinator.openLearningReport)
            toolbarButton("ToolbarWishlist", label: "许愿", action: coordinator.openWishlist)
            Button {
                coordinator.route = .config
            } label: {
                Image("SettingsGear")
                    .resizable()
                    .scaledToFit()
                    .padding(6)
                    .frame(width: 50, height: 50)
                    .background(AppTheme.paleBlue, in: Circle())
            }
            .accessibilityLabel("设置")
            .accessibilityIdentifier("HomeConfigButton")
        }
    }

    private var adventureCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(coordinator.selectedPack.title)
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(red: 0.24, green: 0.18, blue: 0.10))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .accessibilityIdentifier("AdventureCardTitle")
                Spacer()
                Text("已完成")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(Color.gray.opacity(0.15), in: Capsule())
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(coordinator.activePacks) { pack in
                        Button(pack.title) {
                            coordinator.selectPack(pack)
                        }
                        .font(.subheadline.weight(.bold))
                        .padding(.horizontal, 15)
                        .padding(.vertical, 7)
                        .background(
                            coordinator.selectedPack.id == pack.id ? AppTheme.red : Color.white,
                            in: Capsule()
                        )
                        .overlay {
                            Capsule().stroke(Color.gray.opacity(0.22), lineWidth: 1.5)
                        }
                        .foregroundStyle(coordinator.selectedPack.id == pack.id ? .white : Color(red: 0.24, green: 0.18, blue: 0.10))
                        .accessibilityIdentifier("RegionChip_\(pack.id)")
                    }
                }
            }

            HStack(spacing: 8) {
                tag("常规")
                tag("拼写")
                tag("复习")
                tag("精英")
                tag("首领")
            }

            Text(adventureSummary)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(red: 0.35, green: 0.29, blue: 0.22))
                .frame(maxWidth: .infinity, alignment: .center)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Button {
                coordinator.startBattle()
            } label: {
                Text("开始冒险")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(AppTheme.red)
            .accessibilityIdentifier("HomeStartButton")
        }
        .padding(14)
        .background(scenePalette.primary, in: RoundedRectangle(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .stroke(scenePalette.accent.opacity(0.72), lineWidth: 1.5)
        }
        .accessibilityIdentifier("AdventureCard")
    }

    private var adventureSummary: String {
        let levelCount = coordinator.selectedPack.scene.monsterPlan.isEmpty
            ? coordinator.configStore.config.monstersTotal
            : coordinator.selectedPack.scene.monsterPlan.count
        return "今天的冒险包含 \(levelCount) 关卡，含拼写、复习与首领关"
    }

    private func badge(_ text: String, tint: Color, foreground: Color) -> some View {
        Text(text)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(tint, in: Capsule())
    }

    private func toolbarButton(_ imageName: String, label: String, action: (() -> Void)? = nil) -> some View {
        Button {
            action?()
        } label: {
            Image(imageName)
                .resizable()
                .scaledToFit()
                .padding(6)
                .frame(width: 50, height: 50)
                .background(Color(red: 0.99, green: 0.90, blue: 0.90), in: Circle())
        }
        .accessibilityLabel(label)
        .disabled(action == nil)
    }

    private func toolbarEmojiButton(_ emoji: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(emoji)
                .font(.system(size: 28))
                .frame(width: 50, height: 50)
                .background(Color(red: 0.99, green: 0.90, blue: 0.90), in: Circle())
        }
        .accessibilityLabel(label)
        .accessibilityIdentifier("HomeLearningReportButton")
    }

    private func tag(_ label: String) -> some View {
        Text(label)
            .font(.caption.weight(.bold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(AppTheme.gold.opacity(0.25), in: Capsule())
    }
}

struct HomeScenePalette: Equatable {
    static let fallbackPrimaryHex = "#FFF6E5"
    static let fallbackAccentHex = "#FFD49A"

    let primaryHex: String
    let accentHex: String

    init(scene: SceneMetadata) {
        primaryHex = Self.normalizedHex(scene.bgPrimary) ?? Self.fallbackPrimaryHex
        accentHex = Self.normalizedHex(scene.bgAccent) ?? Self.fallbackAccentHex
    }

    var primary: Color {
        Color(hexRGB: primaryHex) ?? AppTheme.cream
    }

    var accent: Color {
        Color(hexRGB: accentHex) ?? AppTheme.gold
    }

    private static func normalizedHex(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard value.count == 6,
              value.allSatisfy(\.isHexDigit)
        else { return nil }
        return "#\(value.uppercased())"
    }
}

private extension Color {
    init?(hexRGB: String) {
        let value = hexRGB.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = value.hasPrefix("#") ? String(value.dropFirst()) : value
        guard digits.count == 6,
              digits.allSatisfy(\.isHexDigit),
              let rgb = UInt32(digits, radix: 16)
        else { return nil }

        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}
