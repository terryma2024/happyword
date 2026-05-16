import SwiftUI

struct PackManagerView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                MonsterCodexStyleBackButton(
                    action: { coordinator.route = .config },
                    accessibilityIdentifier: "PackManagerBack"
                )
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
                Button("同步词包") { coordinator.syncPacks() }
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppTheme.navy)
                    .padding(.horizontal, 18)
                    .frame(height: 54)
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
        .padding(.horizontal, AppTheme.pageHorizontalPadding)
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
        .padding(.horizontal, AppTheme.pageHorizontalPadding)
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
    @State private var showingGiftBox = false
    @State private var showingAddWish = false
    @State private var wishName = ""
    @State private var wishCost = ""
    @State private var wishEmoji = "🎁"
    @State private var addWishPin = ""
    @State private var addWishMessage = ""
    @State private var pendingRedemptionWish: MagicWish?
    @State private var redemptionPin = ""
    @State private var redemptionMessage = ""

    private var parentPinReady: Bool {
        GameConfig.isValidPin(coordinator.configStore.config.parentPin)
    }

    var body: some View {
        ZStack {
            VStack(spacing: 16) {
                wishlistTopBar

                ScrollView {
                    VStack(spacing: 14) {
                        ForEach(coordinator.wishlistStore.wishes) { wish in
                            wishRow(wish)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .padding(.horizontal, AppTheme.pageHorizontalPadding)
            .padding(.top, 24)
            .padding(.bottom, 12)

            if showingAddWish {
                addWishDialog
            }

            if let wish = pendingRedemptionWish {
                redemptionDialog(wish)
            }

            if showingGiftBox {
                GiftBoxOverlay {
                    showingGiftBox = false
                }
                .accessibilityIdentifier("WishlistGiftBoxModal")
            }
        }
        .background(AppTheme.page)
    }

    private var wishlistTopBar: some View {
        HStack(spacing: 0) {
            HStack(spacing: 12) {
                MonsterCodexStyleBackButton(
                    action: { coordinator.route = .home },
                    accessibilityIdentifier: "WishlistBackButton"
                )
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("魔法愿望单")
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundStyle(AppTheme.navy)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityIdentifier("WishlistTitle")

            HStack(spacing: 12) {
                Spacer(minLength: 0)
                Button("📜") { coordinator.route = .redemptionHistory }
                    .font(.system(size: 18))
                    .frame(width: 48, height: 44)
                    .background(AppTheme.paleBlue, in: RoundedRectangle(cornerRadius: 10))
                    .buttonStyle(.plain)
                    .accessibilityLabel("兑换历史")
                    .accessibilityIdentifier("WishlistHistoryButton")

                if parentPinReady {
                    Button("添加") {
                        wishName = ""
                        wishCost = ""
                        wishEmoji = "🎁"
                        addWishPin = ""
                        addWishMessage = ""
                        showingAddWish = true
                    }
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppTheme.navy)
                    .padding(.horizontal, 18)
                    .frame(height: 44)
                    .background(AppTheme.paleBlue, in: RoundedRectangle(cornerRadius: 10))
                    .buttonStyle(.plain)
                    .accessibilityLabel("添加愿望")
                    .accessibilityIdentifier("WishlistAddCustomButton")
                }

                Text("我的魔法币: \(coordinator.coinAccount.balance) ✨")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(red: 1.0, green: 0.68, blue: 0.0))
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var addWishDialog: some View {
        VStack(spacing: 12) {
            Text("添加愿望")
                .font(.title2.weight(.heavy))
                .foregroundStyle(AppTheme.navy)
            TextField("愿望名称", text: $wishName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
                .accessibilityIdentifier("愿望名称")
            TextField("魔法币", text: $wishCost)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
                .accessibilityIdentifier("魔法币")
                .onChange(of: wishCost) { _, value in
                    wishCost = String(value.filter(\.isNumber).prefix(4))
                }
            TextField("图标", text: $wishEmoji)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
                .accessibilityIdentifier("图标")
            SecureField("家长 PIN", text: $addWishPin)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
                .accessibilityIdentifier("家长 PIN")
                .onChange(of: addWishPin) { _, value in
                    addWishPin = GameConfig.sanitizePinInput(value)
                }
            Text(addWishMessage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.red)
                .frame(height: 20)
            HStack(spacing: 16) {
                Button("取消") { showingAddWish = false }
                Button("保存愿望") {
                    saveCustomWish()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.red)
            }
        }
        .padding(.horizontal, AppTheme.pageHorizontalPadding)
        .padding(.vertical, 24)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 22))
        .shadow(radius: 18)
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
                    redemptionPin = ""
                    redemptionMessage = ""
                    pendingRedemptionWish = wish
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
        .padding(.horizontal, AppTheme.pageHorizontalPadding)
        .frame(height: 104)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: Color.black.opacity(0.06), radius: 5, y: 2)
    }

    private func redemptionDialog(_ wish: MagicWish) -> some View {
        VStack(spacing: 12) {
            Text("家长 PIN")
                .font(.title2.weight(.heavy))
                .foregroundStyle(AppTheme.navy)
            Text("确认兑换 \(wish.displayName)")
                .font(.headline.weight(.bold))
                .foregroundStyle(.secondary)
            SecureField("家长 PIN", text: $redemptionPin)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
                .accessibilityIdentifier("家长 PIN")
                .onChange(of: redemptionPin) { _, value in
                    redemptionPin = GameConfig.sanitizePinInput(value)
                }
            Text(redemptionMessage.isEmpty ? "请输入家长 PIN 后兑换" : redemptionMessage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(redemptionMessage.isEmpty ? .secondary : AppTheme.red)
                .frame(height: 20)
            HStack(spacing: 16) {
                Button("取消") {
                    pendingRedemptionWish = nil
                    redemptionPin = ""
                    redemptionMessage = ""
                }
                Button("确认兑换") {
                    confirmRedemption(wish)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.red)
            }
        }
        .padding(.horizontal, AppTheme.pageHorizontalPadding)
        .padding(.vertical, 24)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 22))
        .shadow(radius: 18)
    }

    private func saveCustomWish() {
        let trimmedName = wishName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmoji = wishEmoji.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              let cost = Int(wishCost),
              cost > 0,
              !trimmedEmoji.isEmpty
        else {
            addWishMessage = "请输入愿望名称、正整数魔法币和图标"
            return
        }
        guard addWishPin == coordinator.configStore.config.parentPin else {
            addWishMessage = "PIN 不正确"
            return
        }

        _ = coordinator.wishlistStore.addCustomWish(name: trimmedName, costCoins: cost, iconEmoji: trimmedEmoji)
        showingAddWish = false
    }

    private func confirmRedemption(_ wish: MagicWish) {
        guard parentPinReady else {
            redemptionMessage = "请先让家长在设置中设置 PIN"
            return
        }
        guard redemptionPin == coordinator.configStore.config.parentPin else {
            redemptionMessage = "PIN 不正确"
            return
        }
        if coordinator.wishlistStore.redeem(wishId: wish.id, coins: coordinator.coinAccount, history: coordinator.redemptionHistoryStore) != nil {
            pendingRedemptionWish = nil
            redemptionPin = ""
            redemptionMessage = ""
            showingGiftBox = true
        }
    }
}

struct GiftBoxOverlay: View {
    var onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .accessibilityElement()
                .accessibilityIdentifier("WishlistGiftBoxModal")
                .accessibilityLabel("WishlistGiftBoxModal")
            GiftBoxView()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + GiftBoxAnimationSpec.modalTotalSeconds) {
                onDismiss()
            }
        }
    }
}

struct GiftBoxRibbonSnapshot: Equatable, Identifiable {
    var id: Int
    var angleDegrees: Double
    var colorHex: String
}

enum GiftBoxAnimationSpec {
    static let ribbonColors = ["#E63946", "#F4C430", "#457B9D", "#F78DA7"]
    static let ribbonFlyRadius: Double = 90
    static let ribbonUpwardBias: Double = 25
    static let ribbonCount = 10
    static let ribbonGravityDrop: Double = 120
    static let ribbonPhase1Ms = 300
    static let ribbonPhase2Ms = 600
    static let ribbonClearDelayMs = 900
    static let autoCloseDelayMs = 1500
    static let modalTotalMs = 3180

    static var modalTotalSeconds: TimeInterval {
        TimeInterval(modalTotalMs) / 1000
    }

    static func ribbonFlyTarget(angleDegrees: Double) -> CGSize {
        let angle = angleDegrees * .pi / 180
        return CGSize(
            width: cos(angle) * ribbonFlyRadius,
            height: sin(angle) * ribbonFlyRadius - ribbonUpwardBias
        )
    }

    static func generateRibbons(count: Int) -> [GiftBoxRibbonSnapshot] {
        guard count > 0 else { return [] }
        let step = 360.0 / Double(count)
        return (0..<count).map { index in
            let jitter = Double(((index * 37) % 21) - 10)
            return GiftBoxRibbonSnapshot(
                id: index,
                angleDegrees: Double(index) * step + jitter,
                colorHex: ribbonColors[index % ribbonColors.count]
            )
        }
    }
}

private struct GiftBoxView: View {
    @State private var isOpen = false
    @State private var lidOffset: CGFloat = 0
    @State private var lidRotation: Double = 0
    @State private var boxScale: CGFloat = 1
    @State private var ribbons: [GiftBoxRibbonSnapshot] = []

    var body: some View {
        ZStack {
            boxBody
            lid

            if isOpen {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 1, height: 1)
                    .accessibilityElement()
                    .accessibilityIdentifier("GiftBoxOpenMarker")
                    .accessibilityLabel("GiftBoxOpenMarker")
            }

            ForEach(ribbons) { ribbon in
                GiftBoxRibbonView(ribbon: ribbon)
            }
        }
        .frame(width: 132, height: 120)
        .scaleEffect(boxScale)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("GiftBoxContainer")
        .onAppear(perform: startCycle)
    }

    private var boxBody: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(hexRGB: "#E63946") ?? AppTheme.red)
                .frame(width: 120, height: 80)
            Rectangle()
                .fill(Color(hexRGB: "#F4C430") ?? AppTheme.gold)
                .frame(width: 8, height: 80)
        }
        .frame(width: 120, height: 80, alignment: .bottom)
        .offset(y: 20)
    }

    private var lid: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(hexRGB: "#E63946") ?? AppTheme.red)
                .frame(width: 132, height: 32)
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(hexRGB: "#F4C430") ?? AppTheme.gold)
                    .frame(width: 24, height: 10)
                    .rotationEffect(.degrees(25))
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(hexRGB: "#F4C430") ?? AppTheme.gold)
                    .frame(width: 24, height: 10)
                    .rotationEffect(.degrees(-25))
            }
            .frame(width: 56)
        }
        .frame(width: 132, height: 32)
        .offset(y: -44 + lidOffset)
        .rotationEffect(.degrees(lidRotation))
        .accessibilityIdentifier("GiftBoxLid")
    }

    private func startCycle() {
        isOpen = true
        ribbons = GiftBoxAnimationSpec.generateRibbons(count: GiftBoxAnimationSpec.ribbonCount)

        withAnimation(.easeOut(duration: 0.1)) {
            boxScale = 1.08
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeIn(duration: 0.1)) {
                boxScale = 1
            }
        }

        withAnimation(.easeOut(duration: 0.2)) {
            lidOffset = -40
            lidRotation = -15
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + TimeInterval(GiftBoxAnimationSpec.ribbonClearDelayMs) / 1000) {
            ribbons = []
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + TimeInterval(GiftBoxAnimationSpec.autoCloseDelayMs) / 1000) {
            isOpen = false
            withAnimation(.easeInOut(duration: 0.18)) {
                lidOffset = 0
                lidRotation = 0
            }
        }
    }
}

private struct GiftBoxRibbonView: View {
    let ribbon: GiftBoxRibbonSnapshot
    @State private var offset: CGSize = .zero
    @State private var opacity = 1.0

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color(hexRGB: ribbon.colorHex) ?? AppTheme.red)
            .frame(width: 10, height: 18)
            .offset(offset)
            .opacity(opacity)
            .accessibilityHidden(true)
            .onAppear(perform: animate)
    }

    private func animate() {
        let target = GiftBoxAnimationSpec.ribbonFlyTarget(angleDegrees: ribbon.angleDegrees)
        withAnimation(.easeOut(duration: TimeInterval(GiftBoxAnimationSpec.ribbonPhase1Ms) / 1000)) {
            offset = target
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + TimeInterval(GiftBoxAnimationSpec.ribbonPhase1Ms) / 1000) {
            withAnimation(.easeIn(duration: TimeInterval(GiftBoxAnimationSpec.ribbonPhase2Ms) / 1000)) {
                offset = CGSize(width: target.width, height: target.height + GiftBoxAnimationSpec.ribbonGravityDrop)
                opacity = 0
            }
        }
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

struct RedemptionHistoryView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                MonsterCodexStyleBackButton(
                    action: { coordinator.route = .wishlist },
                    accessibilityIdentifier: "RedemptionHistoryBackButton"
                )
                Spacer()
                Text("兑换历史")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppTheme.navy)
                Spacer()
                Color.clear.frame(width: 54, height: 54)
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
        .padding(.horizontal, AppTheme.pageHorizontalPadding)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
                MonsterCodexStyleBackButton(
                    action: { coordinator.route = .home },
                    accessibilityIdentifier: "TodayPlanBackButton"
                )

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
                        .frame(width: 54, height: 54)
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
            .padding(.horizontal, AppTheme.pageHorizontalPadding)
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
        .padding(.horizontal, AppTheme.pageHorizontalPadding)
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
                .padding(.horizontal, AppTheme.pageHorizontalPadding)
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
                MonsterCodexStyleBackButton(
                    action: { coordinator.route = .todayPlan },
                    accessibilityIdentifier: "LearningReportBackButton"
                )
                Spacer()
                Text("学习报告")
                    .font(.system(size: 29, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppTheme.navy)
                Spacer()
                Color.clear.frame(width: 54, height: 54)
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
        .padding(.horizontal, AppTheme.pageHorizontalPadding)
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
        .padding(.horizontal, AppTheme.pageHorizontalPadding)
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
        .padding(.horizontal, AppTheme.pageHorizontalPadding)
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
        .padding(.horizontal, AppTheme.pageHorizontalPadding)
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
        .padding(.horizontal, AppTheme.pageHorizontalPadding)
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
