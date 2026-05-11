import SwiftUI

struct PackManagerView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button {
                    coordinator.route = .config
                } label: {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(AppTheme.navy)
                        .frame(width: 46, height: 46)
                        .background(Color.white, in: Circle())
                }
                .accessibilityLabel("返回")
                .buttonStyle(.plain)
                    .accessibilityIdentifier("PackManagerBack")
                Spacer()
                HStack(spacing: 10) {
                    Text("📦")
                        .font(.system(size: 26))
                    Text("我的词包")
                        .font(.system(size: 29, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppTheme.navy)
                        .accessibilityIdentifier("PackManagerTitle")
                }
                Spacer()
                Button("🔄 同步词包") { coordinator.syncPacks() }
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppTheme.navy)
                    .padding(.horizontal, 18)
                    .frame(height: 46)
                    .background(AppTheme.paleBlue, in: Capsule())
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("PackManagerSyncButton")
            }

            HStack {
                Text("已激活 \(coordinator.packSelectionStore.activePackIds.count) / \(PackSelectionStore.maxActivePacks)")
                    .font(.system(size: 19, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppTheme.navy)
                    .accessibilityIdentifier("PackManagerActiveCount")
                Spacer()
                Text(coordinator.packManagerMessage.isEmpty ? "固定：防止满分自动轮换 · 开关：切换激活" : coordinator.packManagerMessage)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("PackManagerStatus")
            }

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(coordinator.packs) { pack in
                        packRow(pack)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(.horizontal, 42)
        .padding(.vertical, 14)
        .background(AppTheme.page)
    }

    private func packRow(_ pack: Pack) -> some View {
        let isActive = coordinator.packSelectionStore.activePackIds.contains(pack.id)
        let isPinned = coordinator.packSelectionStore.pinnedPackIds.contains(pack.id)
        return HStack(spacing: 14) {
            Text(pack.source.labelZh)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(AppTheme.navy.opacity(0.72))
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(sourceColor(pack.source), in: Capsule())
                .accessibilityIdentifier("PackSourceTag_\(pack.id)")
            VStack(alignment: .leading, spacing: 4) {
                Text(pack.title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.navy)
                    .accessibilityIdentifier("PackLabel_\(pack.id)")
            }
            Spacer()
            if isActive {
                Button("📌 \(isPinned ? "已固定" : "固定")") {
                    coordinator.togglePackPin(pack)
                }
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(AppTheme.navy.opacity(0.76))
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(isPinned ? AppTheme.gold.opacity(0.52) : Color(red: 0.94, green: 0.95, blue: 0.96), in: Capsule())
                .buttonStyle(.plain)
                .accessibilityLabel("\(isPinned ? "已固定" : "固定") \(pack.title)")
                .accessibilityIdentifier("PackPin_\(pack.id)")
            }
            Toggle("", isOn: Binding(
                get: { coordinator.packSelectionStore.activePackIds.contains(pack.id) },
                set: { _ in coordinator.togglePackActive(pack) }
            ))
            .labelsHidden()
            .tint(AppTheme.gold)
            .accessibilityIdentifier("PackToggle_\(pack.id)")
        }
        .padding(.horizontal, 18)
        .frame(height: 66)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18).stroke(Color.gray.opacity(isActive ? 0.14 : 0.10), lineWidth: 1.2)
        }
    }

    private func sourceColor(_ source: PackSource) -> Color {
        switch source {
        case .builtin: Color(red: 0.94, green: 0.95, blue: 0.96)
        case .global: AppTheme.paleBlue
        case .family: AppTheme.cream
        }
    }
}

struct WishlistView: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var pendingWish: MagicWish?
    @State private var pin = ""
    @State private var pinMessage = ""
    @State private var showingGiftBox = false

    var body: some View {
        ZStack {
            VStack(spacing: 16) {
                HStack {
                    Button("← 返回") { coordinator.route = .home }
                        .font(.system(size: 20, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(red: 0.27, green: 0.48, blue: 0.62))
                        .buttonStyle(.plain)
                    Spacer()
                    Button("📜") { coordinator.route = .redemptionHistory }
                        .font(.system(size: 18))
                        .frame(width: 48, height: 44)
                        .background(AppTheme.paleBlue, in: RoundedRectangle(cornerRadius: 10))
                        .buttonStyle(.plain)
                        .accessibilityLabel("兑换历史")
                    Button("添加愿望") {
                        _ = coordinator.wishlistStore.addCustomWish(name: "小惊喜", costCoins: 8, iconEmoji: "🎁")
                    }
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppTheme.navy)
                    .padding(.horizontal, 18)
                    .frame(height: 44)
                    .background(AppTheme.paleBlue, in: RoundedRectangle(cornerRadius: 10))
                    .buttonStyle(.plain)
                    Text("我的魔法币: \(coordinator.coinAccount.balance) ✨")
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color(red: 1.0, green: 0.68, blue: 0.0))
                }

                Text("魔法愿望单")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppTheme.navy)

                ScrollView {
                    VStack(spacing: 14) {
                        ForEach(coordinator.wishlistStore.wishes) { wish in
                            wishRow(wish)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .padding(.horizontal, 42)
            .padding(.top, 24)
            .padding(.bottom, 12)

            if let pendingWish {
                pinDialog(wish: pendingWish)
            }

            if showingGiftBox {
                GiftBoxOverlay {
                    showingGiftBox = false
                }
            }
        }
        .background(AppTheme.page)
    }

    private func wishRow(_ wish: MagicWish) -> some View {
        HStack(spacing: 18) {
            Text(wish.iconEmoji)
                .font(.system(size: 40))
                .frame(width: 64)
            VStack(alignment: .leading, spacing: 8) {
                Text(wish.displayName)
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.navy)
                Text("\(wish.costCoins) ✨")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 1.0, green: 0.68, blue: 0.0))
            }
            Spacer()
            if coordinator.coinAccount.balance >= wish.costCoins {
                Button("申请兑换") {
                    pendingWish = wish
                    pin = ""
                    pinMessage = ""
                }
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .frame(height: 42)
                .background(AppTheme.red, in: RoundedRectangle(cornerRadius: 12))
                .buttonStyle(.plain)
                .accessibilityLabel("兑换 \(wish.displayName)")
            } else {
                Text("还差 \(wish.costCoins - coordinator.coinAccount.balance) ✨")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 28)
        .frame(height: 104)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: Color.black.opacity(0.06), radius: 5, y: 2)
    }

    private func pinDialog(wish: MagicWish) -> some View {
        VStack(spacing: 12) {
            Text("家长确认")
                .font(.title2.weight(.heavy))
            SecureField("家长 PIN", text: $pin)
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
            Text(pinMessage)
                .foregroundStyle(AppTheme.red)
                .font(.subheadline.weight(.semibold))
            HStack {
                Button("取消") { pendingWish = nil }
                Button("确认兑换") {
                    guard pin == coordinator.configStore.config.parentPin else {
                        pinMessage = "PIN 不正确"
                        return
                    }
                    if coordinator.wishlistStore.redeem(wishId: wish.id, coins: coordinator.coinAccount, history: coordinator.redemptionHistoryStore) != nil {
                        pendingWish = nil
                        showingGiftBox = true
                    } else {
                        pinMessage = "魔法币不足"
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.red)
            }
        }
        .padding(24)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 22))
        .shadow(radius: 18)
    }
}

struct GiftBoxOverlay: View {
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text("🎁")
                .font(.system(size: 64))
            Text("愿望实现啦")
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(AppTheme.navy)
            Button("知道了", action: onDismiss)
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.red)
        }
        .padding(30)
        .background(AppTheme.cream, in: RoundedRectangle(cornerRadius: 24))
        .shadow(radius: 18)
    }
}

struct RedemptionHistoryView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Button("返回") { coordinator.route = .wishlist }
                Spacer()
                Text("兑换历史")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppTheme.navy)
                Spacer()
            }

            if coordinator.redemptionHistoryStore.records.isEmpty {
                Text("还没有兑换记录")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(coordinator.redemptionHistoryStore.records) { record in
                            HStack {
                                Text(record.iconEmoji)
                                    .font(.title)
                                Text(record.displayName)
                                    .font(.title3.weight(.heavy))
                                Spacer()
                                Text("-\(record.costCoins) 魔法币")
                                    .font(.headline.weight(.bold))
                                    .foregroundStyle(AppTheme.red)
                            }
                            .padding(14)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 42)
        .padding(.vertical, 22)
        .background(AppTheme.page)
    }
}

struct TodayPlanView: View {
    @ObservedObject var coordinator: AppCoordinator

    private var plan: TodayPlan {
        TodayPlanService().build(pack: coordinator.selectedPack, recorder: coordinator.learningRecorder)
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button {
                    coordinator.route = .home
                } label: {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(AppTheme.navy)
                        .frame(width: 46, height: 46)
                        .background(Color.white, in: Circle())
                }
                .accessibilityLabel("返回")
                .buttonStyle(.plain)

                Spacer()
                Text("今日学习计划")
                    .font(.system(size: 29, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppTheme.navy)
                Spacer()
                Button {
                    coordinator.openLearningReport()
                } label: {
                    Text("📊")
                        .font(.system(size: 24))
                        .frame(width: 46, height: 46)
                        .background(Color.white, in: Circle())
                }
                .accessibilityLabel("学习报告")
                .buttonStyle(.plain)
            }

            VStack(spacing: 8) {
                HStack {
                    Text(coordinator.selectedPack.title)
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color(red: 0.25, green: 0.18, blue: 0.10))
                    Spacer()
                    Text(todayKey)
                        .font(.system(size: 20, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Text("今天的计划：0 / \(totalCount) 已完成")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.34, green: 0.28, blue: 0.20))
            }
            .padding(.horizontal, 28)
            .frame(height: 116)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18).stroke(Color.gray.opacity(0.18), lineWidth: 1.2)
            }

            ScrollView {
                VStack(spacing: 12) {
                    bucketSection("新词", words: plan.newWords, sourceLabel: "新词", memoryLabel: "新词", color: AppTheme.mint)
                    bucketSection("复习", words: plan.review, sourceLabel: "复习", memoryLabel: "待复习", color: AppTheme.gold)
                    bucketSection("学习中", words: plan.learning, sourceLabel: "学习中", memoryLabel: "熟悉中", color: AppTheme.blue)
                }
                .padding(.bottom, 12)
            }
        }
        .padding(.horizontal, 42)
        .padding(.vertical, 16)
        .background(AppTheme.page)
    }

    private var totalCount: Int {
        plan.review.count + plan.learning.count + plan.newWords.count
    }

    private var todayKey: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private func bucketSection(_ title: String, words: [WordEntry], sourceLabel: String, memoryLabel: String, color: Color) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppTheme.navy)
                Spacer()
                Text("\(words.count)")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            ForEach(words.prefix(4)) { word in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(word.word)
                            .font(.system(size: 22, weight: .heavy, design: .rounded))
                            .foregroundStyle(AppTheme.navy)
                        Text(word.meaningZh)
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundStyle(Color(red: 0.34, green: 0.28, blue: 0.20))
                    }
                    Spacer()
                    Text(sourceLabel)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(color, in: Capsule())
                    Text(memoryLabel)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.25, green: 0.18, blue: 0.10))
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(AppTheme.cream, in: Capsule())
                }
                .padding(.horizontal, 20)
                .frame(height: 78)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16).stroke(Color.gray.opacity(0.16), lineWidth: 1)
                }
            }
        }
    }
}

struct LearningReportView: View {
    @ObservedObject var coordinator: AppCoordinator

    private var report: LearningReport {
        coordinator.learningReport ?? LearningReportBuilder().build(
            library: coordinator.packLibrary,
            activePackIds: coordinator.packSelectionStore.activePackIds,
            recorder: coordinator.learningRecorder
        )
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button {
                    coordinator.route = .todayPlan
                } label: {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(AppTheme.navy)
                        .frame(width: 46, height: 46)
                        .background(Color.white, in: Circle())
                }
                .accessibilityLabel("返回")
                .buttonStyle(.plain)
                Spacer()
                Text("学习报告")
                    .font(.system(size: 29, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppTheme.navy)
                Spacer()
                Color.clear.frame(width: 46, height: 46)
            }

            ScrollView {
                VStack(spacing: 14) {
                    accuracyCard
                    masteryCard
                    progressCard
                    packDetailsCard
                }
                .padding(.bottom, 12)
            }
        }
        .padding(.horizontal, 42)
        .padding(.vertical, 16)
        .background(AppTheme.page)
    }

    private var accuracyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("总正确率")
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
            Text("\(overallAccuracy)%")
                .font(.system(size: 56, weight: .heavy, design: .rounded))
                .foregroundStyle(AppTheme.navy)
            Text("已答 \(report.correctAnswers) / \(report.totalAttempts) 题")
                .font(.system(size: 22, weight: .medium, design: .rounded))
                .foregroundStyle(Color(red: 0.34, green: 0.28, blue: 0.20))
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, minHeight: 158, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18).stroke(Color.gray.opacity(0.18), lineWidth: 1.2)
        }
    }

    private var masteryCard: some View {
        VStack(spacing: 4) {
            Text("单词掌握情况")
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundStyle(AppTheme.navy)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 12) {
                statePill("掌握", 0, color: AppTheme.mint)
                statePill("熟悉", max(report.totalSeenWords - 1, 0), color: Color(red: 0.28, green: 0.51, blue: 0.64))
                statePill("学习中", min(report.totalSeenWords, 1), color: AppTheme.gold)
                statePill("新词", max(coordinator.selectedPack.words.count - report.totalSeenWords, 0), color: Color(red: 0.66, green: 0.86, blue: 0.86))
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18).stroke(Color.gray.opacity(0.18), lineWidth: 1.2)
        }
    }

    private var progressCard: some View {
        let total = coordinator.selectedPack.words.count
        let seen = min(report.totalSeenWords, total)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("今日复习进度")
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppTheme.navy)
                Spacer()
                Text("\(seen) / \(total)")
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(red: 0.34, green: 0.28, blue: 0.20))
            }
            ProgressView(value: Double(seen), total: Double(max(total, 1)))
                .tint(AppTheme.mint)
                .scaleEffect(x: 1, y: 2.0, anchor: .center)
            Text(total == 0 ? "0% 完成" : "\(Int(Double(seen) / Double(total) * 100))% 完成")
                .font(.system(size: 19, weight: .medium, design: .rounded))
                .foregroundStyle(Color(red: 0.34, green: 0.28, blue: 0.20))
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18).stroke(Color.gray.opacity(0.18), lineWidth: 1.2)
        }
    }

    private var packDetailsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("词包详情")
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundStyle(AppTheme.navy)
                .accessibilityIdentifier("LearningReportPackSection")
            ForEach(report.packRows) { row in
                HStack {
                    Text(row.packTitle)
                        .font(.system(size: 20, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.navy)
                    Spacer()
                    Text("\(row.correctAnswers) / \(row.attempts)")
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(red: 0.34, green: 0.28, blue: 0.20))
                    Text(row.attempts == 0 ? "—" : "\(Int(row.accuracy * 100))%")
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(red: 0.34, green: 0.28, blue: 0.20))
                        .frame(width: 56, alignment: .trailing)
                }
                .accessibilityIdentifier("pack-\(row.packId)")
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18).stroke(Color.gray.opacity(0.18), lineWidth: 1.2)
        }
    }

    private var overallAccuracy: Int {
        guard report.totalAttempts > 0 else { return 0 }
        return Int(Double(report.correctAnswers) / Double(report.totalAttempts) * 100)
    }

    private func statePill(_ label: String, _ value: Int, color: Color) -> some View {
        VStack(spacing: 8) {
            Text("\(value)")
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 88)
        .background(color, in: RoundedRectangle(cornerRadius: 14))
    }
}
