import SwiftUI

struct SpellbookView: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject private var rewardStore: SpellbookRewardStore
    @State private var selectedWord: SpellbookWordSelection?
    @State private var showLockedTip = false

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        _rewardStore = ObservedObject(wrappedValue: coordinator.spellbookRewardStore)
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    coordinator.route = .home
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .heavy))
                        .frame(width: 46, height: 46)
                        .background(AppTheme.paleBlue, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("返回")
                .accessibilityIdentifier("SpellbookBackButton")

                Text("魔法书图鉴")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                    .accessibilityIdentifier("SpellbookTitle")

                Spacer()

                Text("金币 \(coordinator.coinAccount.balance)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.gold)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(AppTheme.cream, in: Capsule())
            }
            .padding(.horizontal, AppTheme.pageHorizontalPadding)
            .padding(.top, 18)

            if showLockedTip {
                Text("先在冒险或复习里遇见这个单词，就能点亮它。")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.48, green: 0.28, blue: 0.08))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(AppTheme.cream, in: Capsule())
                    .accessibilityIdentifier("SpellbookLockedTip")
                    .transition(.opacity)
            }

            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(coordinator.packs) { pack in
                        packSection(pack)
                    }
                }
                .padding(.horizontal, AppTheme.pageHorizontalPadding)
                .padding(.bottom, 24)
            }
        }
        .background(AppTheme.page.ignoresSafeArea())
        .accessibilityIdentifier("SpellbookPage")
        .sheet(item: $selectedWord) { selection in
            SpellbookWordDetailSheet(selection: selection)
        }
    }

    private func packSection(_ pack: Pack) -> some View {
        let progress = SpellbookService.progress(words: pack.words, statsByWordId: coordinator.learningRecorder.statsByWordId)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                SpellbookCoverImage(pack: pack)
                    .frame(width: 72, height: 72)
                    .accessibilityIdentifier("SpellbookPackCover_\(pack.id)")

                VStack(alignment: .leading, spacing: 5) {
                    Text(pack.title)
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text("\(progress.masteredCount)/\(progress.totalCount) 已精通")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.secondary)
                        .accessibilityIdentifier("SpellbookPackProgress_\(pack.id)")
                }

                Spacer()

                rewardControl(pack: pack, isComplete: progress.isComplete)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
                ForEach(pack.words) { word in
                    wordCard(pack: pack, word: word)
                }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func rewardControl(pack: Pack, isComplete: Bool) -> some View {
        if rewardStore.isClaimed(packId: pack.id) {
            Text("已领取")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.green)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.green.opacity(0.12), in: Capsule())
                .accessibilityIdentifier("SpellbookPackRewardClaimed_\(pack.id)")
        } else {
            Button {
                guard isComplete else { return }
                _ = rewardStore.claim(packId: pack.id, account: coordinator.coinAccount)
            } label: {
                Text("+50")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(isComplete ? AppTheme.red : Color.gray.opacity(0.35), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!isComplete)
            .accessibilityLabel(isComplete ? "领取 50 魔法币" : "全部精通后可领取 50 魔法币")
            .accessibilityIdentifier("SpellbookPackRewardButton_\(pack.id)")
        }
    }

    private func wordCard(pack: Pack, word: WordEntry) -> some View {
        let state = SpellbookService.cardState(for: word, stat: coordinator.learningRecorder.stat(for: word.id))
        return Button {
            if state == .locked {
                withAnimation(.easeInOut(duration: 0.16)) { showLockedTip = true }
            } else {
                selectedWord = SpellbookWordSelection(pack: pack, word: word, state: state)
            }
        } label: {
            VStack(spacing: 6) {
                Text(state == .locked ? "?" : word.word)
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(state == .locked ? Color.gray : AppTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                Text(stateLabel(state))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(state == .mastered ? Color.green : Color.secondary)
                    .lineLimit(1)
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityIdentifier(stateIdentifier(packId: pack.id, wordId: word.id, state: state))
            }
            .frame(maxWidth: .infinity, minHeight: 78)
            .background(cardBackground(state), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(cardStroke(state), lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("SpellbookCard_\(pack.id)_\(word.id)")
    }

    private func stateLabel(_ state: SpellbookCardState) -> String {
        switch state {
        case .locked: "未点亮"
        case .seen: "已点亮"
        case .mastered: "已精通"
        }
    }

    private func stateIdentifier(packId: String, wordId: String, state: SpellbookCardState) -> String {
        switch state {
        case .locked: "SpellbookCardLocked_\(packId)_\(wordId)"
        case .seen: "SpellbookCardSeen_\(packId)_\(wordId)"
        case .mastered: "SpellbookCardMastered_\(packId)_\(wordId)"
        }
    }

    private func cardBackground(_ state: SpellbookCardState) -> Color {
        switch state {
        case .locked: Color.gray.opacity(0.12)
        case .seen: AppTheme.paleBlue.opacity(0.78)
        case .mastered: Color.green.opacity(0.14)
        }
    }

    private func cardStroke(_ state: SpellbookCardState) -> Color {
        switch state {
        case .locked: Color.gray.opacity(0.22)
        case .seen: Color.blue.opacity(0.18)
        case .mastered: Color.green.opacity(0.32)
        }
    }
}

struct SpellbookCoverImage: View {
    let pack: Pack

    var body: some View {
        Group {
            if let url = pack.scene.spellbookCoverUrl.flatMap(URL.init(string:)) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                    default:
                        Image(SpellbookCoverAsset.assetName(for: pack.id)).resizable().scaledToFit()
                    }
                }
            } else {
                Image(SpellbookCoverAsset.assetName(for: pack.id))
                    .resizable()
                    .scaledToFit()
            }
        }
        .padding(4)
        .background(Color.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

enum SpellbookCoverAsset {
    static func assetName(for packId: String) -> String {
        switch packId {
        case "fruit-forest": "SpellbookCoverFruitForest"
        case "school-castle": "SpellbookCoverSchoolCastle"
        case "home-cottage": "SpellbookCoverHomeCottage"
        case "animal-safari": "SpellbookCoverAnimalSafari"
        case "ocean-realm": "SpellbookCoverOceanRealm"
        default: "SpellbookCoverDefault"
        }
    }
}

private struct SpellbookWordSelection: Identifiable {
    var pack: Pack
    var word: WordEntry
    var state: SpellbookCardState

    var id: String {
        "\(pack.id)::\(word.id)"
    }
}

private struct SpellbookWordDetailSheet: View {
    let selection: SpellbookWordSelection
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Capsule()
                .fill(Color.gray.opacity(0.25))
                .frame(width: 44, height: 5)
                .padding(.top, 12)

            Text(selection.word.word)
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(AppTheme.ink)
                .accessibilityIdentifier("SpellbookWordDetailTitle")

            Text(selection.word.meaningZh)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Color.secondary)

            Text(selection.state == .mastered ? "已精通" : "已点亮")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(selection.state == .mastered ? Color.green : Color.blue)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.white, in: Capsule())
                .accessibilityIdentifier("SpellbookWordDetailState")

            if let example = selection.word.example {
                Text(example.en)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
                    .multilineTextAlignment(.center)
                Text(example.zh)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            Button("关闭") {
                dismiss()
            }
            .font(.system(size: 18, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(AppTheme.red, in: Capsule())
            .buttonStyle(.plain)
            .accessibilityIdentifier("SpellbookWordDetailClose")
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .background(AppTheme.page.ignoresSafeArea())
        .accessibilityIdentifier("SpellbookWordDetailSheet")
    }
}
