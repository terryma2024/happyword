import SwiftUI

enum ConfigLayoutRules {
    static let labelWidth: CGFloat = 120
    static let controlGap: CGFloat = 12
    static let controlColumnWidth: CGFloat = 220
    static let timerOptionsPerRow = 3
    static let questionTypesLeftAligned = true
    static let settingGroupSpacing: CGFloat = 22
    static let settingOptionSpacing: CGFloat = 8
    static let settingSwitchLabelWidth: CGFloat = 132

    static func questionTypeRows(_ typeIds: [String]) -> [[String]] {
        typeIds.map { [$0] }
    }

    static func timerOptionRows(_ options: [Int]) -> [[Int]] {
        stride(from: 0, to: options.count, by: timerOptionsPerRow).map { start in
            Array(options[start..<min(start + timerOptionsPerRow, options.count)])
        }
    }
}

enum ConfigActionButtonStyle {
    static let background = Color(red: 0.88, green: 0.95, blue: 0.99)
    static let foreground = Color(red: 0.01, green: 0.41, blue: 0.63)
    static let border = Color(red: 0.05, green: 0.65, blue: 0.91)
    static let width: CGFloat = 220
    static let height: CGFloat = 40
    static let cornerRadius: CGFloat = 8
    static let borderWidth: CGFloat = 2
}

private extension View {
    func configActionButtonStyle() -> some View {
        font(.system(size: 15, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .frame(width: ConfigActionButtonStyle.width, height: ConfigActionButtonStyle.height)
            .background(
                ConfigActionButtonStyle.background,
                in: RoundedRectangle(cornerRadius: ConfigActionButtonStyle.cornerRadius)
            )
            .foregroundStyle(ConfigActionButtonStyle.foreground)
            .overlay(
                RoundedRectangle(cornerRadius: ConfigActionButtonStyle.cornerRadius)
                    .stroke(ConfigActionButtonStyle.border, lineWidth: ConfigActionButtonStyle.borderWidth)
            )
    }
}

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
        GeometryReader { proxy in
            let compactHeight = proxy.size.height < 460
            VStack(spacing: 0) {
                configTopBar(compactHeight: compactHeight)
                ScrollView {
                    VStack(spacing: ConfigLayoutRules.settingGroupSpacing) {
                        Text("游戏配置")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .accessibilityIdentifier("ConfigTitle")

                        settingStepper("玩家血量", value: $draft.playerMaxHp, range: GameConfig.hpRange)
                        settingStepper("怪物血量", value: $draft.monsterMaxHp, range: GameConfig.hpRange)
                        settingStepper("怪物数量", value: $draft.monstersTotal, range: GameConfig.monsterCountRange)

                        timerRow
                        audioPlaybackSection
                        questionTypeSection
                        packPickerSection
                        reportChannelRow

                        Text("家长配置")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 8)
                            .accessibilityIdentifier("ConfigSectionParentTitle")

                        parentAccountSection
                        parentPinRow
                        cloudSyncSection
                        if coordinator.configStore.config.parentPin.count == 6 {
                            adminRow
                        }
                    }
                    .padding(.horizontal, AppTheme.pageHorizontalPadding)
                    .padding(.vertical, 22)
                }
            }
            .padding(.horizontal, AppTheme.pageHorizontalPadding)
            .padding(.top, AppTheme.portraitPageTopPadding)
            .padding(.bottom, compactHeight ? 8 : 14)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(Color.white)
        .onChange(of: draft) { _, new in
            coordinator.saveConfig(new)
        }
        .sheet(isPresented: $showCustomTimerSheet) {
            customTimerSheetContent
        }
        .onAppear {
            draft = coordinator.configStore.config
            questionTypeHint = ""
        }
    }

    private func configTopBar(compactHeight: Bool) -> some View {
        HStack {
            MonsterCodexStyleBackButton(
                action: { coordinator.route = .home },
                compact: compactHeight,
                accessibilityIdentifier: "ConfigBackButton"
            )
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private var timerRow: some View {
        HStack(spacing: 12) {
            Text("倒计时")
                .font(.title2.weight(.bold))
                .frame(width: ConfigLayoutRules.labelWidth, alignment: .trailing)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(ConfigLayoutRules.timerOptionRows(GameConfig.timerChoices + [0]), id: \.self) { row in
                    HStack(spacing: 8) {
                        ForEach(row, id: \.self) { seconds in
                            if seconds > 0 {
                                timerChoiceButton(seconds)
                            } else {
                                customTimerButton
                            }
                        }
                    }
                }
            }
            .frame(width: ConfigLayoutRules.controlColumnWidth, alignment: .leading)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: 560)
    }

    private var customTimerButton: some View {
        Button {
            openCustomTimerSheet()
        } label: {
            Text(customTimerChipTitle)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 12)
                .frame(height: 40)
                .background(isCustomTimer ? Color(red: 0.71, green: 0.33, blue: 0.04) : AppTheme.paleBlue, in: Capsule())
                .foregroundStyle(isCustomTimer ? Color.white : Color(red: 0.11, green: 0.3, blue: 0.85))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("ConfigTimerCustom")
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
        coordinator.saveConfig(draft)
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
                .background(isSelected ? Color(red: 0.71, green: 0.33, blue: 0.04) : AppTheme.paleBlue, in: Capsule())
                .foregroundStyle(isSelected ? Color.white : Color(red: 0.11, green: 0.3, blue: 0.85))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("ConfigTimer\(seconds)s")
    }

    private var audioPlaybackSection: some View {
        settingGroup(label: "发音播放") {
            VStack(alignment: .leading, spacing: ConfigLayoutRules.settingOptionSpacing) {
                configSwitch("自动发音", isOn: $draft.autoSpeak, accessibilityIdentifier: "ConfigAutoSpeakSwitch")
                configSwitch("播放BGM", isOn: $draft.playBgm, accessibilityIdentifier: "ConfigPlayBgmSwitch")
                configSwitch("动作特效音", isOn: $draft.actionSfx, accessibilityIdentifier: "ConfigActionSfxSwitch")
            }
        }
    }

    /// Parity with Harmony `ConfigPage.questionTypeRow` — switch column + last-type hint.
    private var questionTypeSection: some View {
        let ordered = BattleQuestionTypePolicy.defaultOrderedTypeIds
        return VStack(alignment: .leading, spacing: 4) {
            settingGroup(label: "题型选择") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(ordered, id: \.self) { typeId in
                        configSwitch(
                            BattleQuestionTypePolicy.displayLabel(forTypeId: typeId),
                            isOn: questionTypeBinding(typeId),
                            accessibilityIdentifier: "ConfigQuestionType_\(typeId)"
                        )
                    }
                }
            }
            Text("至少保留一种题型")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(
                    questionTypeHint.isEmpty
                        ? Color.clear
                        : Color(red: 0.71, green: 0.33, blue: 0.04),
                )
                .padding(.leading, ConfigLayoutRules.labelWidth + ConfigLayoutRules.controlGap)
                .accessibilityIdentifier("ConfigQuestionTypeLastEnabledHint")
        }
    }

    private func settingGroup<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: ConfigLayoutRules.controlGap) {
            Text(label)
                .font(.title2.weight(.bold))
                .frame(width: ConfigLayoutRules.labelWidth, alignment: .trailing)
            content()
                .frame(width: ConfigLayoutRules.controlColumnWidth, alignment: .leading)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: 560)
    }

    private func configSwitch(_ title: String, isOn: Binding<Bool>, accessibilityIdentifier: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.navy)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(width: ConfigLayoutRules.settingSwitchLabelWidth, alignment: .leading)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(AppTheme.gold)
                .accessibilityIdentifier(accessibilityIdentifier)
        }
        .frame(width: ConfigLayoutRules.controlColumnWidth, height: 42, alignment: .leading)
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

    private func questionTypeBinding(_ typeId: String) -> Binding<Bool> {
        Binding(
            get: { isQuestionTypeEnabled(typeId) },
            set: { _ in toggleQuestionType(typeId) }
        )
    }

    private var packPickerSection: some View {
        let active = coordinator.packSelectionStore.activePackIds.count
        let limit = PackSelectionStore.maxActivePacks
        return HStack(spacing: 12) {
            Text("我的词包")
                .font(.title2.weight(.bold))
                .frame(width: ConfigLayoutRules.labelWidth, alignment: .trailing)
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

    private var reportChannelRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Text("投诉与举报")
                    .font(.title2.weight(.bold))
                    .frame(width: ConfigLayoutRules.labelWidth, alignment: .trailing)
                Button("投诉与举报入口") {
                    SystemBrowser.open(CompliancePolicy.reportChannelURL)
                }
                .configActionButtonStyle()
                .buttonStyle(.plain)
                .accessibilityIdentifier("ConfigReportChannelButton")
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: 560)
    }

    private var parentPinRow: some View {
        let pinReady = coordinator.configStore.config.parentPin.count == 6
        return HStack(spacing: 12) {
            Text("家长密码")
                .font(.title2.weight(.bold))
                .frame(width: ConfigLayoutRules.labelWidth, alignment: .trailing)
            Button {
                coordinator.route = .pinSetup
            } label: {
                Text(pinReady ? "修改 (•••••• 已设置)" : "设置")
                    .configActionButtonStyle()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("ConfigParentPinButton")
            Spacer(minLength: 0)
        }
        .frame(maxWidth: 560)
    }

    private var parentAccountSection: some View {
        HStack(spacing: 12) {
            Text("家长账号")
                .font(.title2.weight(.bold))
                .frame(width: ConfigLayoutRules.labelWidth, alignment: .trailing)
            if let credentials = coordinator.cloudCredentialsStore.credentials {
                Button {
                    coordinator.openBoundDeviceInfo()
                } label: {
                    Text("学习档案：\(credentials.nickname)")
                        .configActionButtonStyle()
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ConfigBoundDeviceInfoButton")
            } else {
                Button("绑定家长账号") { coordinator.openBinding() }
                    .configActionButtonStyle()
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
                    .frame(width: ConfigLayoutRules.labelWidth, alignment: .trailing)
                Button {
                    Task { await coordinator.syncWordStatsExplicitly() }
                } label: {
                    Text("立即同步学习记录")
                        .configActionButtonStyle()
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
                .frame(width: ConfigLayoutRules.labelWidth, alignment: .trailing)
            Button("家长管理后台") { coordinator.openParentAdmin() }
                .configActionButtonStyle()
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
                .frame(width: ConfigLayoutRules.labelWidth, alignment: .trailing)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 16) {
                Button("Back") { coordinator.route = .home }
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(minHeight: DeveloperMenuLayoutSpec.headerButtonHeight)
                    .background(AppTheme.blue, in: Capsule())
                    .buttonStyle(.plain)
                Text("Developer Options")
                    .font(.system(size: DeveloperMenuLayoutSpec.titleFontSize, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(red: 0.13, green: 0.13, blue: 0.13))
                Spacer()
            }
            VStack(alignment: .leading, spacing: 12) {
                devToolButton("Domain Switch", id: "DevMenuDomainSwitchButton") {
                    coordinator.openDomainSwitch()
                }
                devToolButton("PcmAudioLab", id: "DevMenuAudioLabButton") {
                    coordinator.openPcmAudioLab()
                }
                devToolButton("MessageBubbleLab", id: "DevMenuMessageBubbleLabButton") {
                    coordinator.openMessageBubbleLab()
                }
                devToolButton("CocosLab", id: "DevMenuCocosLabButton") {
                    runCocosBridgeSpike()
                }
            }
            Spacer()
        }
        .padding(.horizontal, AppTheme.pageHorizontalPadding)
        .padding(.vertical, 16)
        .background(Color.white)
    }

    /// Phase 0 spike: boots the embedded Cocos runtime, round-trips a
    /// ping/pong over the JSB bridge, then dismisses the Cocos window.
    /// Temporary — replaced by the battle integration in Phase 2.
    private func runCocosBridgeSpike() {
        let shim = WMCocosRuntimeShim.shared()
        guard WMCocosRuntimeShim.isLinked else {
            coordinator.showToast("Cocos runtime not linked (simulator build)")
            return
        }

        shim.setScriptHandler { json in
            guard let data = json.data(using: .utf8),
                  let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = message["type"] as? String
            else { return }

            switch type {
            case "battle/ready":
                shim.send(toScript: #"{"v":1,"type":"battle/ping","payload":{"echo":"spike"}}"#)
            case "battle/pong":
                let payload = message["payload"] as? [String: Any]
                let echo = payload?["echo"] as? String ?? "?"
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    shim.dismissCocosWindow()
                    shim.setScriptHandler(nil)
                    coordinator.showToast("Cocos pong OK (echo: \(echo))")
                }
            default:
                break
            }
        }

        guard shim.presentCocosWindow() else {
            coordinator.showToast("Cocos runtime failed to boot")
            return
        }

        // Safety net: never leave the Cocos window stuck over the app.
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
            shim.dismissCocosWindow()
        }
    }

    private func devToolButton(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppTheme.navy)
                Spacer()
                Text("Open")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(ConfigActionButtonStyle.foreground)
            }
            .padding(.horizontal, 16)
            .frame(width: 360, height: 56)
            .background(ConfigActionButtonStyle.background, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(ConfigActionButtonStyle.border, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

struct DomainSwitchView: View {
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
            .padding(.horizontal, AppTheme.pageHorizontalPadding)
            .padding(.vertical, 16)
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
                coordinator.route = .devMenu
            }
            Text("Domain Switch")
                .font(.system(size: DeveloperMenuLayoutSpec.titleFontSize, weight: .heavy, design: .rounded))
                .foregroundStyle(Color(red: 0.13, green: 0.13, blue: 0.13))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Spacer()
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
    static let bubbleLabButtonMinWidth: CGFloat = 108
    static let refreshButtonMinWidth: CGFloat = 156
    static let cardTitleFontSize: CGFloat = 14
    static let cardFooterFontSize: CGFloat = 13
    static let cardHeight: CGFloat = 96
}

@MainActor
final class PcmAudioLabController: ObservableObject {
    @Published var status = "idle"
    @Published var selectedWord = "apple"
    @Published var musicEnabled = true
    @Published var sfxEnabled = true
    @Published var voiceEnabled = true
    @Published var resumeMusicAfterVoice = false
    @Published var masterVolume = BattleAudioMixPolicy.masterVolume
    @Published var musicVolume = BattleAudioMixPolicy.musicVolume
    @Published var musicLoweredVolume = BattleAudioMixPolicy.musicLoweredVolumeWhileVoice
    @Published var sfxDuringVoiceVolume = BattleAudioMixPolicy.sfxDuringVoiceVolume
    @Published var sfxDuringVoicePolicy = BattleSfxDuringVoicePolicy.lower
    @Published var lastEvent = "none"
    @Published var delayedStatus = "none"
    @Published var resumeAttempts = 0
    @Published var musicState = "idle"
    @Published var voiceState = "idle"

    let words = ["apple", "dragon", "magic", "school"]
    let policies = BattleSfxDuringVoicePolicy.allCases
    private let mixer: BattleAudioMixing

    init(mixer: BattleAudioMixing = PcmBattleAudioMixer()) {
        self.mixer = mixer
        syncMixerSettings()
    }

    func startBgm() {
        mixer.prepare()
        syncMixerSettings()
        mixer.startBattle(config: labConfig(playBgm: musicEnabled))
        musicState = musicEnabled ? "playing" : "disabled"
        lastEvent = "start_music"
        status = musicEnabled ? "BGM loop requested." : "BGM disabled."
    }

    func stopBgm() {
        mixer.stopBattle()
        musicState = "stopped"
        lastEvent = "stop_music"
        status = "BGM stopped."
    }

    func selectWord(_ word: String) {
        guard words.contains(word) else { return }
        selectedWord = word
        status = "Selected \(word)."
        lastEvent = "select_word"
    }

    func speak() {
        guard voiceEnabled else {
            status = "Voice disabled."
            return
        }
        syncMixerSettings()
        mixer.speak(selectedWord)
        voiceState = "active"
        lastEvent = "speak"
        status = "Speaking \(selectedWord)."
    }

    func speakOverBgm() {
        mixer.prepare()
        syncMixerSettings()
        mixer.startBattle(config: labConfig(playBgm: musicEnabled))
        mixer.speak(selectedWord)
        musicState = musicEnabled ? "playing" : "disabled"
        voiceState = voiceEnabled ? "active" : "idle"
        lastEvent = "speak_over_music"
        status = "BGM plus voice for \(selectedWord)."
    }

    func playNormalHit() {
        playSfx(.normalHit, event: "normal_attack", message: "Played normal attack SFX.")
    }

    func playComboHit() {
        playSfx(.comboHit, event: "combo_attack", message: "Played combo SFX with temporary BGM duck.")
    }

    func playWrong() {
        playSfx(.wrong, event: "wrong_answer", message: "Played wrong-answer SFX.")
    }

    func playHurt() {
        playSfx(.hurt, event: "player_hurt", message: "Played critical player-hurt SFX.")
    }

    func playVictory() {
        playSfx(.victory, event: "victory", message: "Played victory SFX.")
    }

    func playDefeat() {
        playSfx(.defeat, event: "defeat", message: "Played defeat SFX.")
    }

    func comboOverBgm() {
        mixer.prepare()
        syncMixerSettings()
        mixer.startBattle(config: labConfig(playBgm: musicEnabled))
        mixer.playSfx(.comboHit)
        musicState = musicEnabled ? "playing" : "disabled"
        lastEvent = "combo_over_music"
        status = "Combo attack over BGM."
    }

    func playSfxDuringVoice() {
        if voiceEnabled {
            mixer.speak(selectedWord)
            voiceState = "active"
        }
        mixer.playSfx(.normalHit)
        mixer.playSfx(.comboHit)
        mixer.playSfx(.hurt)
        delayedStatus = sfxDuringVoicePolicy == .delay ? "normal_hit, combo_hit" : "none"
        lastEvent = "sfx_during_voice"
        status = "Voice, BGM, non-critical SFX, combo SFX, and critical SFX fired together."
    }

    func wrongSequence() {
        syncMixerSettings()
        mixer.playSfx(.wrong)
        mixer.playSfx(.hurt)
        lastEvent = "wrong_sequence"
        status = "Wrong answer plus player hurt sequence."
    }

    func winSequence() {
        syncMixerSettings()
        mixer.playSfx(.victory)
        lastEvent = "win_sequence"
        status = "Played victory over current BGM."
    }

    func toggleMusic() {
        musicEnabled.toggle()
        if !musicEnabled {
            mixer.stopBattle()
            musicState = "stopped"
        }
        syncMixerSettings()
        lastEvent = "toggle_music"
        status = "BGM \(boolLabel(musicEnabled))."
    }

    func toggleSfx() {
        sfxEnabled.toggle()
        syncMixerSettings()
        lastEvent = "toggle_sfx"
        status = "SFX \(boolLabel(sfxEnabled))."
    }

    func toggleVoice() {
        voiceEnabled.toggle()
        voiceState = voiceEnabled ? "idle" : "disabled"
        syncMixerSettings()
        lastEvent = "toggle_voice"
        status = "Voice \(boolLabel(voiceEnabled))."
    }

    func toggleResumeMusicAfterVoice() {
        resumeMusicAfterVoice.toggle()
        resumeAttempts += resumeMusicAfterVoice ? 1 : 0
        syncMixerSettings()
        lastEvent = "toggle_resume"
        status = "Resume after voice \(boolLabel(resumeMusicAfterVoice))."
    }

    func adjustMaster(_ delta: Double) {
        masterVolume = clamp01(masterVolume + delta)
        syncMixerSettings()
    }

    func adjustMusic(_ delta: Double) {
        musicVolume = clamp01(musicVolume + delta)
        syncMixerSettings()
    }

    func adjustDuck(_ delta: Double) {
        musicLoweredVolume = clamp01(musicLoweredVolume + delta)
        syncMixerSettings()
    }

    func adjustSfxDuringVoice(_ delta: Double) {
        sfxDuringVoiceVolume = clamp01(sfxDuringVoiceVolume + delta)
        syncMixerSettings()
    }

    func setPolicy(_ policy: BattleSfxDuringVoicePolicy) {
        sfxDuringVoicePolicy = policy
        syncMixerSettings()
        lastEvent = "policy_\(policy.rawValue)"
        status = "SFX during voice policy: \(policy.rawValue)."
    }

    func dispose() {
        mixer.dispose()
    }

    func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func playSfx(_ cue: BattleSfxCue, event: String, message: String) {
        syncMixerSettings()
        mixer.playSfx(cue)
        lastEvent = event
        status = message
    }

    private func syncMixerSettings() {
        mixer.updateSettings(BattleAudioMixSettings(
            masterVolume: masterVolume,
            musicVolume: musicVolume,
            musicLoweredVolumeWhileVoice: musicLoweredVolume,
            sfxVolume: BattleAudioMixPolicy.sfxVolume,
            sfxDuringVoiceVolume: sfxDuringVoiceVolume,
            resumeMusicAfterVoice: resumeMusicAfterVoice,
            voiceEnabled: voiceEnabled,
            sfxEnabled: sfxEnabled,
            sfxDuringVoicePolicy: sfxDuringVoicePolicy,
        ))
    }

    private func labConfig(playBgm: Bool? = nil) -> GameConfig {
        GameConfig(playBgm: playBgm ?? musicEnabled, actionSfx: sfxEnabled)
    }

    private func clamp01(_ value: Double) -> Double {
        min(1.0, max(0.0, (value * 100).rounded() / 100))
    }

    private func boolLabel(_ value: Bool) -> String {
        value ? "on" : "off"
    }
}

struct PcmAudioLabView: View {
    @ObservedObject var coordinator: AppCoordinator
    @StateObject private var lab = PcmAudioLabController()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Button("Back") {
                        lab.dispose()
                        coordinator.route = .devMenu
                    }
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(minHeight: DeveloperMenuLayoutSpec.headerButtonHeight)
                    .background(AppTheme.blue, in: Capsule())
                    .buttonStyle(.plain)
                    Spacer()
                    Text("PcmAudioLab")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppTheme.navy)
                        .accessibilityIdentifier("PcmAudioLabTitle")
                    Spacer()
                    Color.clear.frame(width: 72, height: 1)
                }

                mixPanel

                VStack(alignment: .leading, spacing: 12) {
                    transportPanel
                    voicePanel
                    policyPanel
                    statusPanel
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, AppTheme.pageHorizontalPadding)
            .padding(.vertical, 14)
        }
        .background(Color.white)
        .onDisappear {
            lab.dispose()
        }
    }

    private var transportPanel: some View {
        labPanel("Transport") {
            buttonGrid([
                ("Start BGM", "PcmAudioLabStartBgmButton", { lab.startBgm() }),
                ("Stop BGM", "PcmAudioLabStopBgmButton", { lab.stopBgm() }),
                ("Normal hit", "AudioLabNormalHit", { lab.playNormalHit() }),
                ("Combo hit", "AudioLabComboHit", { lab.playComboHit() }),
                ("Wrong", "AudioLabWrong", { lab.playWrong() }),
                ("Hurt", "AudioLabHurt", { lab.playHurt() }),
                ("Victory", "AudioLabVictory", { lab.playVictory() }),
                ("Defeat", "AudioLabDefeat", { lab.playDefeat() }),
            ])
        }
    }

    private var voicePanel: some View {
        labPanel("PCM Voice") {
            HStack(spacing: 6) {
                ForEach(lab.words, id: \.self) { word in
                    chipButton(
                        word,
                        selected: lab.selectedWord == word,
                        id: "AudioLabWord_\(word)",
                    ) {
                        lab.selectWord(word)
                    }
                }
            }
            buttonGrid([
                ("Speak", "AudioLabSpeak", { lab.speak() }),
                ("Speak over BGM", "PcmAudioLabSpeakOverBgmButton", { lab.speakOverBgm() }),
                ("Combo over BGM", "AudioLabComboOverMusic", { lab.comboOverBgm() }),
                ("SFX during voice", "PcmAudioLabSfxDuringVoiceButton", { lab.playSfxDuringVoice() }),
                ("Wrong sequence", "AudioLabWrongSequence", { lab.wrongSequence() }),
                ("Win sequence", "AudioLabWinSequence", { lab.winSequence() }),
            ])
        }
    }

    private var mixPanel: some View {
        labPanel("Mix") {
            HStack(spacing: 6) {
                toggleChip("BGM", isOn: lab.musicEnabled, id: "AudioLabToggleMusic") { lab.toggleMusic() }
                toggleChip("SFX", isOn: lab.sfxEnabled, id: "AudioLabToggleSfx") { lab.toggleSfx() }
                toggleChip("Voice", isOn: lab.voiceEnabled, id: "AudioLabToggleVoice") { lab.toggleVoice() }
                toggleChip("Resume", isOn: lab.resumeMusicAfterVoice, id: "AudioLabToggleResume") { lab.toggleResumeMusicAfterVoice() }
            }

            VStack(spacing: 7) {
                HStack(spacing: 8) {
                    volumeControl("Master", value: lab.percent(lab.masterVolume), minusId: "AudioLabMasterMinus", plusId: "AudioLabMasterPlus", onMinus: { lab.adjustMaster(-0.05) }, onPlus: { lab.adjustMaster(0.05) })
                    volumeControl("BGM", value: lab.percent(lab.musicVolume), minusId: "AudioLabMusicMinus", plusId: "AudioLabMusicPlus", onMinus: { lab.adjustMusic(-0.05) }, onPlus: { lab.adjustMusic(0.05) })
                }
                HStack(spacing: 8) {
                    volumeControl("BGM duck", value: lab.percent(lab.musicLoweredVolume), minusId: "AudioLabDuckMinus", plusId: "AudioLabDuckPlus", onMinus: { lab.adjustDuck(-0.02) }, onPlus: { lab.adjustDuck(0.02) })
                    volumeControl("SFX voice", value: lab.percent(lab.sfxDuringVoiceVolume), minusId: "AudioLabSfxVoiceMinus", plusId: "AudioLabSfxVoicePlus", onMinus: { lab.adjustSfxDuringVoice(-0.05) }, onPlus: { lab.adjustSfxDuringVoice(0.05) })
                }
            }
        }
    }

    private var policyPanel: some View {
        labPanel("SFX During Voice") {
            HStack(spacing: 8) {
                ForEach(lab.policies, id: \.self) { policy in
                    chipButton(
                        policy.rawValue,
                        selected: lab.sfxDuringVoicePolicy == policy,
                        id: "AudioLabPolicy_\(policy.rawValue)",
                    ) {
                        lab.setPolicy(policy)
                    }
                }
            }
            Text("Critical hurt/victory/defeat cues still play under suppress and delay policies.")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(red: 0.33, green: 0.42, blue: 0.47))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statusPanel: some View {
        labPanel("Status") {
            Text(lab.status)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(red: 0.2, green: 0.29, blue: 0.35))
                .accessibilityIdentifier("PcmAudioLabStatus")
            Text("music=\(lab.musicState) voice=\(lab.voiceState) volume=\(lab.percent(lab.musicVolume)) timers=0")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(red: 0.33, green: 0.42, blue: 0.47))
                .accessibilityIdentifier("AudioLabSnapshot")
            Text("last=\(lab.lastEvent) delayed=\(lab.delayedStatus) resume=\(lab.resumeAttempts)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(red: 0.33, green: 0.42, blue: 0.47))
        }
    }

    private func labPanel<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(Color(red: 0.02, green: 0.23, blue: 0.34))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func buttonGrid(_ items: [(String, String, () -> Void)]) -> some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
        ], spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                labButton(item.0, id: item.1, action: item.2)
            }
        }
    }

    private func labButton(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(ConfigActionButtonStyle.foreground)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(ConfigActionButtonStyle.background, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(ConfigActionButtonStyle.border, lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private func chipButton(_ title: String, selected: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: selected ? .heavy : .semibold, design: .rounded))
                .foregroundStyle(selected ? Color.white : Color(red: 0.19, green: 0.32, blue: 0.4))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(selected ? Color(red: 0.15, green: 0.42, blue: 0.49) : Color(red: 0.93, green: 0.96, blue: 0.96), in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private func toggleChip(_ title: String, isOn: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("\(title)  \(isOn ? "on" : "off")")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundStyle(isOn ? Color.white : Color(red: 0.33, green: 0.42, blue: 0.47))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(isOn ? Color(red: 0, green: 0.48, blue: 0.53) : Color(red: 0.92, green: 0.96, blue: 0.97), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private func volumeControl(
        _ label: String,
        value: String,
        minusId: String,
        plusId: String,
        onMinus: @escaping () -> Void,
        onPlus: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(red: 0.2, green: 0.29, blue: 0.35))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: 64, alignment: .leading)
            stepButton("-", id: minusId, action: onMinus)
            Text(value)
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundStyle(Color(red: 0.07, green: 0.19, blue: 0.28))
                .frame(width: 38)
            stepButton("+", id: plusId, action: onPlus)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stepButton(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(Color(red: 0.07, green: 0.19, blue: 0.28))
                .frame(width: 28, height: 24)
                .background(Color(red: 0.92, green: 0.96, blue: 0.97), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
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
                Button("取消") { coordinator.cancelParentPinSetup() }
                Button("保存 PIN") { coordinator.saveParentPin(pin, confirmation: confirmation) }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.red)
                    .accessibilityIdentifier("ParentPinSaveButton")
            }
        }
        .frame(width: 380)
        .padding(.horizontal, AppTheme.pageHorizontalPadding)
        .padding(.vertical, 26)
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
        .padding(.horizontal, AppTheme.pageHorizontalPadding)
        .padding(.vertical, 26)
        .background(AppTheme.cream, in: RoundedRectangle(cornerRadius: 22))
    }
}
