import SwiftUI

struct ConfigView: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var draft: GameConfig
    @State private var showCustomTimerSheet = false
    @State private var customTimerText = ""
    @State private var customTimerError = ""
    @State private var questionTypeHint = ""

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        _draft = State(initialValue: coordinator.configStore.config)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Text("游戏设置")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .accessibilityIdentifier("ConfigTitle")

                settingStepper("玩家血量", value: $draft.playerMaxHp, range: GameConfig.hpRange)
                settingStepper("怪物血量", value: $draft.monsterMaxHp, range: GameConfig.hpRange)
                settingStepper("怪物数量", value: $draft.monstersTotal, range: GameConfig.monsterCountRange)

                timerRow
                autoSpeakRow
                questionTypeSection
                packPickerSection
                parentPinRow
                parentAccountSection
                cloudSyncSection
                adminRow

                HStack(spacing: 16) {
                    Button("取消") { coordinator.route = .home }
                        .buttonStyle(.bordered)
                        .frame(minWidth: 160, minHeight: 48)
                        .accessibilityIdentifier("ConfigCancelButton")
                    Button("保存") { coordinator.saveConfig(draft) }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red: 0.18, green: 0.8, blue: 0.44))
                        .frame(minWidth: 160, minHeight: 48)
                        .accessibilityIdentifier("ConfigSaveButton")
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 22)
        }
        .background(Color.white)
        .sheet(isPresented: $showCustomTimerSheet) {
            customTimerSheetContent
        }
        .onAppear {
            draft = coordinator.configStore.config
            questionTypeHint = ""
        }
    }

    private var timerRow: some View {
        HStack(spacing: 12) {
            Text("倒计时")
                .font(.title2.weight(.bold))
                .frame(width: 120, alignment: .trailing)
            HStack(spacing: 8) {
                ForEach(GameConfig.timerChoices, id: \.self) { seconds in
                    timerChoiceButton(seconds)
                }
                Button {
                    openCustomTimerSheet()
                } label: {
                    Text(customTimerChipTitle)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.horizontal, 12)
                        .frame(height: 40)
                        .background(isCustomTimer ? AppTheme.gold : AppTheme.paleBlue, in: Capsule())
                        .foregroundStyle(isCustomTimer ? Color.white : Color(red: 0.23, green: 0.45, blue: 0.61))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ConfigTimerCustom")
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: 560)
    }

    private var customTimerChipTitle: String {
        if isCustomTimer {
            return "✓自定义 (\(timerChipShortLabel(draft.startingSeconds)))"
        }
        return "自定义"
    }

    private func isCustomTimerValue(_ seconds: Int) -> Bool {
        !GameConfig.timerChoices.contains(seconds)
    }

    private var isCustomTimer: Bool { isCustomTimerValue(draft.startingSeconds) }

    private func timerChipShortLabel(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        return "\(seconds / 60)m"
    }

    private func timerChipDisplayLabel(seconds: Int) -> String {
        let base = timerChipShortLabel(seconds)
        return draft.startingSeconds == seconds ? "✓\(base)" : base
    }

    private func openCustomTimerSheet() {
        customTimerText = "\(draft.startingSeconds)"
        customTimerError = ""
        showCustomTimerSheet = true
    }

    private var customTimerSheetContent: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("自定义倒计时")
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(red: 0.11, green: 0.21, blue: 0.34))
                    .accessibilityIdentifier("CustomTimerDialogTitle")
                Text(
                    "请输入倒计时秒数（\(GameConfig.timerCustomRange.lowerBound) - \(GameConfig.timerCustomRange.upperBound)）",
                )
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(red: 0.42, green: 0.45, blue: 0.5))
                .accessibilityIdentifier("CustomTimerDialogHint")
                TextField("秒", text: $customTimerText)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("CustomTimerDialogInput")
                    .onChange(of: customTimerText) { _, newValue in
                        let filtered = String(newValue.filter(\.isNumber).prefix(4))
                        if filtered != newValue {
                            customTimerText = filtered
                        }
                        customTimerError = ""
                    }
                if !customTimerError.isEmpty {
                    Text(customTimerError)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(red: 0.9, green: 0.22, blue: 0.27))
                        .accessibilityIdentifier("CustomTimerDialogError")
                }
                Spacer()
            }
            .padding()
            .navigationTitle("自定义")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        customTimerError = ""
                        showCustomTimerSheet = false
                    }
                    .accessibilityIdentifier("CustomTimerDialogCancelButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确定") {
                        confirmCustomTimerSheet()
                    }
                    .accessibilityIdentifier("CustomTimerDialogConfirmButton")
                }
            }
        }
        .presentationDetents([.medium])
    }

    /// Harmony `CustomTimerDialog.handleConfirm`: validate first; only dismiss on success.
    private func confirmCustomTimerSheet() {
        let v = GameConfig.validateCustomTimerInput(customTimerText)
        guard v.ok else {
            customTimerError = v.message
            return
        }
        draft.startingSeconds = v.seconds
        customTimerError = ""
        showCustomTimerSheet = false
    }

    private func timerChoiceButton(_ seconds: Int) -> some View {
        let isSelected = draft.startingSeconds == seconds
        return Button {
            draft.startingSeconds = seconds
        } label: {
            Text(timerChipDisplayLabel(seconds: seconds))
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 12)
                .frame(height: 40)
                .background(isSelected ? AppTheme.gold : AppTheme.paleBlue, in: Capsule())
                .foregroundStyle(isSelected ? Color.white : Color(red: 0.23, green: 0.45, blue: 0.61))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("ConfigTimer\(seconds)s")
    }

    private var autoSpeakRow: some View {
        HStack(spacing: 12) {
            Text("发音播放")
                .font(.title2.weight(.bold))
                .frame(width: 120, alignment: .trailing)
            Button {
                draft.autoSpeak.toggle()
            } label: {
                Text(draft.autoSpeak ? "✓ 自动朗读" : "自动朗读")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .frame(width: 140, height: 40)
                    .background(draft.autoSpeak ? Color(red: 1, green: 0.96, blue: 0.82) : Color(red: 0.94, green: 0.94, blue: 0.94))
                    .foregroundStyle(draft.autoSpeak ? Color(red: 0.72, green: 0.53, blue: 0.04) : Color(red: 0.4, green: 0.4, blue: 0.4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(red: 1, green: 0.71, blue: 0), lineWidth: draft.autoSpeak ? 2 : 0)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("ConfigAutoSpeakToggle")
            Spacer(minLength: 0)
        }
        .frame(maxWidth: 560)
    }

    /// Parity with Harmony `ConfigPage.questionTypeRow` — two chip rows + last-type hint.
    private var questionTypeSection: some View {
        let ordered = BattleQuestionTypePolicy.defaultOrderedTypeIds
        let row0 = Array(ordered.prefix(2))
        let row1 = Array(ordered.dropFirst(2))
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 12) {
                Text("题型选择")
                    .font(.title2.weight(.bold))
                    .frame(width: 120, alignment: .trailing)
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach(row0, id: \.self) { typeId in
                            questionTypeChip(typeId: typeId)
                        }
                    }
                    HStack(spacing: 8) {
                        ForEach(row1, id: \.self) { typeId in
                            questionTypeChip(typeId: typeId)
                        }
                    }
                }
                .frame(width: 260, alignment: .center)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: 560)
            Text("至少保留一种题型")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(
                    questionTypeHint.isEmpty
                        ? Color.clear
                        : Color(red: 0.71, green: 0.33, blue: 0.04),
                )
                .padding(.leading, 132)
                .accessibilityIdentifier("ConfigQuestionTypeLastEnabledHint")
        }
    }

    private func isQuestionTypeEnabled(_ typeId: String) -> Bool {
        let safe = BattleQuestionTypePolicy.sanitizeEnabledQuestionTypes(draft.enabledQuestionTypes)
        return safe.contains(typeId)
    }

    private func toggleQuestionType(_ typeId: String) {
        var safe = BattleQuestionTypePolicy.sanitizeEnabledQuestionTypes(draft.enabledQuestionTypes)
        if let idx = safe.firstIndex(of: typeId) {
            if safe.count <= 1 {
                questionTypeHint = "至少保留一种题型"
                return
            }
            safe.remove(at: idx)
        } else {
            safe.append(typeId)
        }
        questionTypeHint = ""
        draft.enabledQuestionTypes = BattleQuestionTypePolicy.sanitizeEnabledQuestionTypes(safe)
    }

    private func questionTypeChip(typeId: String) -> some View {
        let on = isQuestionTypeEnabled(typeId)
        return Button {
            toggleQuestionType(typeId)
        } label: {
            Text(chipLabel(typeId: typeId, selected: on))
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 12)
                .frame(height: 40)
                .background(on ? Color(red: 1, green: 0.96, blue: 0.82) : Color(red: 0.94, green: 0.94, blue: 0.94))
                .foregroundStyle(on ? Color(red: 0.72, green: 0.53, blue: 0.04) : Color(red: 0.4, green: 0.4, blue: 0.4))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(red: 1, green: 0.71, blue: 0), lineWidth: on ? 2 : 0)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("ConfigQuestionType_\(typeId)")
    }

    private func chipLabel(typeId: String, selected: Bool) -> String {
        let base = BattleQuestionTypePolicy.displayLabel(forTypeId: typeId)
        return selected ? "✓ \(base)" : base
    }

    private var packPickerSection: some View {
        let active = coordinator.packSelectionStore.activePackIds.count
        let limit = PackSelectionStore.maxActivePacks
        return HStack(spacing: 12) {
            Text("我的词包")
                .font(.title2.weight(.bold))
                .frame(width: 120, alignment: .trailing)
            Button {
                coordinator.route = .packManager
            } label: {
                HStack {
                    Text("已激活 \(active) / \(limit)")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(red: 0.12, green: 0.16, blue: 0.23))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("ConfigPackPickerStatus")
                    Text("管理 ›")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(red: 0.27, green: 0.48, blue: 0.62))
                }
                .padding(.horizontal, 12)
                .frame(width: 220, height: 40)
                .background(AppTheme.paleBlue, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("ConfigPackManagerEntry")
            .accessibilityLabel("我的词包")
            Spacer(minLength: 0)
        }
        .frame(maxWidth: 560)
    }

    private var parentPinRow: some View {
        let pinReady = coordinator.configStore.config.parentPin.count == 6
        return HStack(spacing: 12) {
            Text("家长密码")
                .font(.title2.weight(.bold))
                .frame(width: 120, alignment: .trailing)
            Button {
                coordinator.route = .pinSetup
            } label: {
                Text(pinReady ? "修改 (•••••• 已设置)" : "设置")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .frame(width: 220, height: 40)
                    .background(pinReady ? Color(red: 1, green: 0.96, blue: 0.82) : AppTheme.paleBlue, in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(pinReady ? Color(red: 0.72, green: 0.53, blue: 0.04) : Color(red: 0.27, green: 0.48, blue: 0.62))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(red: 1, green: 0.71, blue: 0), lineWidth: pinReady ? 2 : 0)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("ConfigParentPinButton")
            Spacer(minLength: 0)
        }
        .frame(maxWidth: 560)
    }

    private var parentAccountSection: some View {
        HStack(spacing: 12) {
            Text("家长账户")
                .font(.title2.weight(.bold))
                .frame(width: 120, alignment: .trailing)
            if let credentials = coordinator.cloudCredentialsStore.credentials {
                Button {
                    coordinator.openBoundDeviceInfo()
                } label: {
                    Text("孩子档案：\(credentials.nickname)")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .frame(width: 220, height: 40)
                        .background(Color(red: 0.88, green: 0.95, blue: 0.99), in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(Color(red: 0.01, green: 0.41, blue: 0.63))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(red: 0.05, green: 0.65, blue: 0.91), lineWidth: 2)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ConfigBoundDeviceInfoButton")
            } else {
                Button("绑定家长账号") { coordinator.openBinding() }
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .frame(width: 220, height: 40)
                    .background(Color(red: 1, green: 0.96, blue: 0.82), in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(Color(red: 0.72, green: 0.53, blue: 0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(red: 1, green: 0.71, blue: 0), lineWidth: 2)
                    )
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("ConfigBindParentButton")
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: 560)
    }

    @ViewBuilder
    private var cloudSyncSection: some View {
        if coordinator.cloudCredentialsStore.credentials != nil {
            HStack(spacing: 12) {
                Text("学习记录")
                    .font(.title2.weight(.bold))
                    .frame(width: 120, alignment: .trailing)
                Button {
                    Task { await coordinator.syncWordStatsExplicitly() }
                } label: {
                    Text("立即同步学习记录")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .frame(width: 220, height: 40)
                        .background(Color(red: 0.88, green: 0.95, blue: 0.99), in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(Color(red: 0.01, green: 0.41, blue: 0.63))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(red: 0.05, green: 0.65, blue: 0.91), lineWidth: 2)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ConfigCloudSyncButton")
                Spacer(minLength: 0)
            }
            .frame(maxWidth: 560)
        }
    }

    private var adminRow: some View {
        HStack(spacing: 12) {
            Text("管理后台")
                .font(.title2.weight(.bold))
                .frame(width: 120, alignment: .trailing)
            Button("家长管理后台") { coordinator.openParentAdmin() }
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .frame(width: 220, height: 40)
                .background(Color(red: 1, green: 0.96, blue: 0.82), in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(Color(red: 0.72, green: 0.53, blue: 0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(red: 1, green: 0.71, blue: 0), lineWidth: 2)
                )
                .buttonStyle(.plain)
                .accessibilityIdentifier("ConfigParentAdminButton")
            Spacer(minLength: 0)
        }
        .frame(maxWidth: 560)
    }

    private func settingStepper(_ title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack(spacing: 22) {
            Text(title)
                .font(.title2.weight(.bold))
                .frame(width: 120, alignment: .trailing)
            roundControl("−") { value.wrappedValue = max(range.lowerBound, value.wrappedValue - 1) }
            Text("\(value.wrappedValue)")
                .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                .frame(width: 54)
            roundControl("+") { value.wrappedValue = min(range.upperBound, value.wrappedValue + 1) }
            Spacer()
        }
        .frame(maxWidth: 560)
    }

    private func roundControl(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(AppTheme.blue, in: Circle())
        }
    }
}

struct DevMenuView: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject private var viewModel: DeveloperMenuViewModel
    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        viewModel = coordinator.developerMenuViewModel
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header

                Text("Backend environment (debug builds only)")
                    .font(.system(size: DeveloperMenuLayoutSpec.sectionFontSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 12)

                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    ForEach(viewModel.cards) { card in
                        devMenuCard(card)
                    }
                }
                .padding(.bottom, 16)

                if viewModel.manifest.previews.isEmpty {
                    Text(viewModel.statusMessage.isEmpty ? "No manifest available" : viewModel.statusMessage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 16)
                }

                if viewModel.lastProbeStatus != "未检测" {
                    Text("Last health probe")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 16)
                        .padding(.bottom, 4)
                    Text(viewModel.lastProbeStatus)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(red: 0.26, green: 0.26, blue: 0.26))
                        .accessibilityIdentifier("DevMenuLastProbeStatus")
                }

                if !viewModel.routingDebug.isEmpty {
                    Text(viewModel.routingDebug.replacingOccurrences(of: "环境 \(viewModel.environment.title) · ", with: "API base: "))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 16)
                        .accessibilityIdentifier("DevMenuRoutingDebug")
                }
                Spacer()
            }
            .padding(16)
        }
        .background(Color.white)
        .onAppear {
            switch coordinator.takeDevMenuRoutePreset()?.lowercased() {
            case DevMenuRouteParams.presetPreview:
                Task { await viewModel.refreshManifest() }
            default:
                break
            }
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            headerButton("Back", minWidth: DeveloperMenuLayoutSpec.backButtonMinWidth) {
                coordinator.route = .home
            }
            Text("Developer Options")
                .font(.system(size: DeveloperMenuLayoutSpec.titleFontSize, weight: .heavy, design: .rounded))
                .foregroundStyle(Color(red: 0.13, green: 0.13, blue: 0.13))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Spacer()
            headerButton(
                "Bypass Secret",
                minWidth: DeveloperMenuLayoutSpec.bypassButtonMinWidth,
                accessibilityIdentifier: "DevMenuBypassSecretButton",
                isDisabled: viewModel.isApplying
            ) {
                coordinator.openBypassSecret()
            }
            headerButton(
                viewModel.statusMessage == "Refreshing..." ? "Refreshing..." : "Refresh Manifest",
                minWidth: DeveloperMenuLayoutSpec.refreshButtonMinWidth,
                accessibilityIdentifier: "DevMenuRefreshManifestButton",
                isDisabled: viewModel.isApplying
            ) {
                Task { await viewModel.refreshManifest() }
            }
        }
        .padding(.bottom, 16)
    }

    private func headerButton(
        _ title: String,
        minWidth: CGFloat,
        accessibilityIdentifier: String? = nil,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: DeveloperMenuLayoutSpec.headerButtonFontSize, weight: .semibold, design: .rounded))
                .lineLimit(DeveloperMenuLayoutSpec.headerButtonLineLimit)
                .minimumScaleFactor(0.86)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .frame(minWidth: minWidth, minHeight: DeveloperMenuLayoutSpec.headerButtonHeight)
                .background(AppTheme.blue, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.6 : 1)
        .accessibilityIdentifier(accessibilityIdentifier ?? "")
    }

    private func devMenuCard(_ card: DeveloperMenuCard) -> some View {
        Button {
            Task { await coordinator.activateDeveloperMenuCard(card) }
        } label: {
            VStack(alignment: .leading) {
                Text(card.title)
                    .font(.system(size: DeveloperMenuLayoutSpec.cardTitleFontSize, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(red: 0.13, green: 0.13, blue: 0.13))
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
                Text(card.footer)
                    .font(.system(size: DeveloperMenuLayoutSpec.cardFooterFontSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 0.34, green: 0.34, blue: 0.34))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(12)
            .frame(height: DeveloperMenuLayoutSpec.cardHeight)
            .frame(maxWidth: .infinity)
            .background(card.isSelected ? Color(red: 0.74, green: 0.9, blue: 0.98) : Color(red: 0.96, green: 0.96, blue: 0.96))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(card.isSelected ? Color(red: 0.27, green: 0.48, blue: 0.62) : Color(red: 0.88, green: 0.88, blue: 0.88), lineWidth: 1)
            )
            .opacity(viewModel.isApplying ? 0.6 : 1)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isApplying)
        .accessibilityIdentifier(card.id)
    }
}

enum DeveloperMenuLayoutSpec {
    static let titleFontSize: CGFloat = 20
    static let sectionFontSize: CGFloat = 14
    static let headerButtonFontSize: CGFloat = 13
    static let headerButtonHeight: CGFloat = 36
    static let headerButtonLineLimit = 1
    static let backButtonMinWidth: CGFloat = 72
    static let bypassButtonMinWidth: CGFloat = 142
    static let refreshButtonMinWidth: CGFloat = 156
    static let cardTitleFontSize: CGFloat = 14
    static let cardFooterFontSize: CGFloat = 13
    static let cardHeight: CGFloat = 96
}

struct BypassSecretView: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject private var viewModel: DeveloperMenuViewModel
    @State private var secret: String

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        viewModel = coordinator.developerMenuViewModel
        _secret = State(initialValue: coordinator.developerMenuViewModel.bypassSecret)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Bypass Secret")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .accessibilityIdentifier("BypassSecretPageTitle")
            SecureField("Vercel protection bypass", text: $secret)
                .textFieldStyle(.roundedBorder)
                .font(.title3.weight(.bold))
                .accessibilityIdentifier("BypassSecretPageInput")
            Text(viewModel.statusMessage)
                .font(.headline.weight(.bold))
                .foregroundStyle(AppTheme.red)
                .frame(height: 24, alignment: .leading)
                .accessibilityIdentifier("BypassSecretPageError")
            HStack {
                Button("取消") { coordinator.cancelBypassSecret() }
                    .accessibilityIdentifier("BypassSecretPageCancel")
                Button("清除") {
                    secret = ""
                    viewModel.clearBypassSecret()
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("BypassSecretPageClear")
                Spacer()
                Button("保存") {
                    Task {
                        await coordinator.saveBypassSecretAndContinue(secret)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.red)
                .accessibilityIdentifier("BypassSecretPageSave")
            }
        }
        .padding(32)
        .frame(width: 520)
        .background(AppTheme.cream, in: RoundedRectangle(cornerRadius: 22))
    }
}

struct ParentPinSetupView: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var pin = ""
    @State private var confirmation = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("家长 PIN")
                .font(.system(size: 30, weight: .heavy, design: .rounded))
            SecureField("6 位数字", text: $pin)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("ParentPinInput")
                .onChange(of: pin) { _, newValue in
                    pin = GameConfig.sanitizePinInput(newValue)
                }
            SecureField("再次输入 PIN", text: $confirmation)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("ParentPinConfirmInput")
                .onChange(of: confirmation) { _, newValue in
                    confirmation = GameConfig.sanitizePinInput(newValue)
                }
            Text(coordinator.pinMessage)
                .foregroundStyle(AppTheme.red)
            HStack {
                Button("取消") { coordinator.route = .config }
                Button("保存 PIN") { coordinator.saveParentPin(pin, confirmation: confirmation) }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.red)
                    .accessibilityIdentifier("ParentPinSaveButton")
            }
        }
        .frame(width: 380)
        .padding(26)
        .background(AppTheme.cream, in: RoundedRectangle(cornerRadius: 22))
    }
}

struct ParentPinGateView: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var pin = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("输入家长 PIN")
                .font(.system(size: 30, weight: .heavy, design: .rounded))
            SecureField("6 位数字", text: $pin)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("ParentPinGateInput")
                .onChange(of: pin) { _, newValue in
                    pin = GameConfig.sanitizePinInput(newValue)
                }
            Text(coordinator.pinMessage)
                .foregroundStyle(AppTheme.red)
            HStack {
                Button("取消") { coordinator.route = .config }
                Button("打开") { coordinator.verifyParentPin(pin) }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.red)
                    .accessibilityIdentifier("ParentPinGateSubmit")
            }
        }
        .frame(width: 380)
        .padding(26)
        .background(AppTheme.cream, in: RoundedRectangle(cornerRadius: 22))
    }
}
