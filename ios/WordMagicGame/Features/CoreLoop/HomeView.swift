import SwiftUI

struct HomeView: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var versionTripleTap = VersionTripleTapState()

    private var scenePalette: HomeScenePalette {
        HomeScenePalette(scene: coordinator.selectedPack.scene)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
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
                .padding(.horizontal, AppTheme.pageHorizontalPadding)
                .padding(.top, 18)
                .padding(.bottom, 10)
                .frame(width: proxy.size.width, height: proxy.size.height)

                if let versionLabel = HomeVersionLabel.text() {
                    Text(versionLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(red: 0.6, green: 0.6, blue: 0.6))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .frame(maxWidth: proxy.size.width * 0.55, alignment: .leading)
                    .padding(.leading, AppTheme.pageHorizontalPadding)
                    .padding(.top, 16)
                    .padding(.trailing, AppTheme.pageHorizontalPadding)
                        .padding(.bottom, 8)
                        .accessibilityLabel("HomeVersionLabel")
                        .accessibilityIdentifier("HomeVersionLabel")
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard DeveloperToolsPolicy.isDeveloperToolsVisible() else { return }
                            let nowMs = Date().timeIntervalSince1970 * 1000
                            if versionTripleTap.consumeTap(nowMs: nowMs) {
                                coordinator.openDeveloperMenu(presetEnv: DevMenuRouteParams.presetPreview)
                            }
                        }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(AppTheme.page)
        .onAppear {
            coordinator.refreshDailyLearningState()
        }
    }

    private var topBar: some View {
        let childProfileLabel = "学习档案 \(coordinator.currentChildNickname())"
        let status = coordinator.homeDailyStatus
        return HStack(spacing: 12) {
            Spacer(minLength: 0)
            if coordinator.showsChildProfileShortcut {
                Button {
                    coordinator.openBoundDeviceInfo()
                } label: {
                    badge(
                        "\(coordinator.currentChildAvatarEmoji()) \(coordinator.currentChildNickname())",
                        tint: AppTheme.paleBlue,
                        foreground: Color(red: 0.02, green: 0.42, blue: 0.66)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(childProfileLabel)
                .accessibilityIdentifier("HomeChildProfileButton")
            }
            badge("金币 \(coordinator.coinAccount.balance)", tint: AppTheme.cream, foreground: AppTheme.gold)
                .accessibilityIdentifier("HomeCoinBalance")
            ZStack(alignment: .topTrailing) {
                toolbarButton("ToolbarReview", label: "复习", accessibilityIdentifier: "HomeReviewButton", action: coordinator.startReviewBattle)
                if status.remainingReviewCount > 0 && coordinator.dailyLearningState.packBattleWon {
                    Text("\(status.remainingReviewCount)")
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(.white)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(AppTheme.red, in: Circle())
                        .offset(x: 3, y: -3)
                        .accessibilityIdentifier("HomeReviewCountBadge")
                }
            }
            toolbarButton("ToolbarCodex", label: "图鉴", action: coordinator.openMonsterCodex)
            toolbarButton("SpellbookIcon", label: "魔法书", accessibilityIdentifier: "HomeSpellbookButton", action: coordinator.openSpellbook)
            toolbarEmojiButton("📋", label: "今日学习计划", action: coordinator.openTodayPlan)
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
        let status = coordinator.homeDailyStatus
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                SpellbookCoverImage(pack: coordinator.selectedPack)
                    .frame(width: 44, height: 44)
                    .accessibilityIdentifier("HomePackSpellbookCover")
                Text(coordinator.selectedPack.title)
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(red: 0.24, green: 0.18, blue: 0.10))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .accessibilityIdentifier("AdventureCardTitle")
                Spacer()
                Text(status.label)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(Color.gray.opacity(0.15), in: Capsule())
                    .accessibilityIdentifier("AdventureCardDailyStatusLabel")
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

            Text(HomePackStoryLine.text(for: coordinator.selectedPack))
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(red: 0.35, green: 0.29, blue: 0.22))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: HomeAdventureCardStoryStyle.reservedHeight, alignment: .center)
                .lineLimit(HomeAdventureCardStoryStyle.lineLimit)
                .minimumScaleFactor(0.72)

            Button {
                coordinator.startBattle()
            } label: {
                Text("开始今日冒险")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(AppTheme.red)
            .accessibilityIdentifier("HomeStartButton")
        }
        .padding(.horizontal, AppTheme.pageHorizontalPadding)
        .padding(.vertical, 14)
        .background(scenePalette.primary, in: RoundedRectangle(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .stroke(scenePalette.accent.opacity(0.72), lineWidth: 1.5)
        }
        .accessibilityIdentifier("AdventureCard")
    }

    private func badge(_ text: String, tint: Color, foreground: Color) -> some View {
        Text(text)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(tint, in: Capsule())
    }

    private func toolbarButton(_ imageName: String, label: String, accessibilityIdentifier: String? = nil, action: (() -> Void)? = nil) -> some View {
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
        .accessibilityIdentifier(accessibilityIdentifier ?? label)
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
        .accessibilityIdentifier("HomeTodayPlanButton")
    }
}

enum HomeAdventureCardStoryStyle {
    static let lineLimit = 2
    static let reservedHeight: CGFloat = 44
}

enum HomePackStoryLine {
    static func text(for pack: Pack) -> String {
        let storyEn = pack.scene.storyEn?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !storyEn.isEmpty {
            return storyEn
        }

        let low = pack.words.filter { $0.difficulty <= 2 }.count
        let middle = pack.words.filter { $0.difficulty == 3 }.count
        let high = pack.words.filter { $0.difficulty >= 4 }.count
        let buckets = [
            low > 0 ? "\(low) 个低难度" : nil,
            middle > 0 ? "\(middle) 个中难度" : nil,
            high > 0 ? "\(high) 个高难度" : nil,
        ].compactMap { $0 }
        let base = "本词包 \(pack.words.count) 个单词"
        return buckets.isEmpty ? base : "\(base)，其中 \(buckets.joined(separator: "，"))"
    }
}

/// Mirrors HarmonyOS `VersionTripleTap` (1500ms window).
private struct VersionTripleTapState {
    private var count: Int = 0
    private var lastTapMs: Double = 0
    private let windowMs: Double = 1500

    mutating func consumeTap(nowMs: Double) -> Bool {
        if nowMs - lastTapMs > windowMs {
            count = 1
        } else {
            count += 1
        }
        lastTapMs = nowMs
        if count >= 3 {
            count = 0
            lastTapMs = 0
            return true
        }
        return false
    }
}

/// Home version line: `v{CFBundleShortVersionString}({YYMMDDHHmm})`.
/// Release builds keep the label visible for store smoke tests, but the hidden
/// triple-tap DevMenu entry remains gated by `DeveloperToolsPolicy`.
private enum HomeVersionLabel {
    static func text() -> String? {
        let versionName: String
        if let name = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String, !name.isEmpty {
            versionName = name
        } else {
            versionName = "?.?.?"
        }
        let bundleURL = Bundle.main.bundleURL
        let attrs = try? FileManager.default.attributesOfItem(atPath: bundleURL.path)
        let date =
            (attrs?[.modificationDate] as? Date)
            ?? (attrs?[.creationDate] as? Date)
            ?? Date()
        return "v\(versionName)(\(formatBuildTimestamp(date)))"
    }

    private static func formatBuildTimestamp(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let yy = calendar.component(.year, from: date) % 100
        let mm = calendar.component(.month, from: date)
        let dd = calendar.component(.day, from: date)
        let hh = calendar.component(.hour, from: date)
        let mn = calendar.component(.minute, from: date)
        return String(format: "%02d%02d%02d%02d%02d", yy, mm, dd, hh, mn)
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
