import SwiftUI

struct ConfigView: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var draft: GameConfig

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        _draft = State(initialValue: coordinator.configStore.config)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack {
                    Button("返回") { coordinator.route = .home }
                    Spacer()
                    Text("游戏设置")
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .accessibilityIdentifier("ConfigTitle")
                    Spacer()
                    Button("保存") { coordinator.saveConfig(draft) }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.red)
                }

                settingStepper("玩家血量", value: $draft.playerMaxHp, range: GameConfig.hpRange)
                settingStepper("怪物血量", value: $draft.monsterMaxHp, range: GameConfig.hpRange)
                settingStepper("怪物数量", value: $draft.monstersTotal, range: GameConfig.monsterCountRange)

                HStack(spacing: 24) {
                    Text("倒计时")
                        .font(.title2.weight(.bold))
                        .frame(width: 120, alignment: .trailing)
                    ForEach(GameConfig.timerChoices, id: \.self) { seconds in
                        timerChoiceButton(seconds)
                    }
                    TextField("自定义秒数", value: $draft.startingSeconds, format: .number)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 130)
                        .accessibilityIdentifier("ConfigCustomTimerInput")
                }

                HStack(spacing: 24) {
                    Text("自动朗读")
                        .font(.title2.weight(.bold))
                        .frame(width: 120, alignment: .trailing)
                    Toggle("", isOn: $draft.autoSpeak)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .tint(AppTheme.gold)
                        .accessibilityIdentifier("ConfigAutoSpeakSwitch")
                    Spacer()
                }
                .frame(maxWidth: 560)

                HStack(spacing: 16) {
                    Button("家长 PIN") { coordinator.route = .pinSetup }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.gold)
                        .accessibilityIdentifier("ParentPinSetupButton")
                    Button("家长后台") { coordinator.openParentAdmin() }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.red)
                        .accessibilityIdentifier("ConfigParentAdminButton")
                    Button("我的词包") { coordinator.route = .packManager }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("ConfigPackManagerButton")
                }
                .font(.headline.weight(.bold))

                cloudBindingSection

                if DeveloperToolsPolicy.isDeveloperToolsVisible() {
                    developerSection
                }
            }
            .padding(.horizontal, 42)
            .padding(.vertical, 22)
        }
        .background(AppTheme.page)
    }

    private var cloudBindingSection: some View {
        HStack(spacing: 16) {
            Text("家长云同步")
                .font(.title2.weight(.bold))
                .frame(width: 130, alignment: .trailing)

            if let credentials = coordinator.cloudCredentialsStore.credentials {
                Text("已绑定 \(credentials.nickname)")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppTheme.navy)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .accessibilityIdentifier("CloudBindingStatus")
                Button("账号信息") { coordinator.openBoundDeviceInfo() }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.mint)
                    .accessibilityIdentifier("账号信息")
                Button("同步学习记录") {
                    Task { await coordinator.syncWordStatsExplicitly() }
                }
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .buttonStyle(.bordered)
                .accessibilityIdentifier("同步学习记录")
            } else {
                Button("绑定家长账号") { coordinator.openBinding() }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.mint)
                    .accessibilityIdentifier("绑定家长账号")
            }
            Spacer()
        }
        .font(.headline.weight(.bold))
        .frame(maxWidth: 560)
    }

    private var developerSection: some View {
        HStack(spacing: 16) {
            Text("开发工具")
                .font(.title2.weight(.bold))
                .frame(width: 130, alignment: .trailing)
            Button("Backend environment") { coordinator.openDeveloperMenu() }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("ConfigDeveloperBackendButton")
            Spacer()
        }
        .font(.headline.weight(.bold))
        .frame(maxWidth: 560)
    }

    private func settingStepper(_ title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack(spacing: 22) {
            Text(title)
                .font(.title2.weight(.bold))
                .frame(width: 130, alignment: .trailing)
            roundControl("−") { value.wrappedValue = max(range.lowerBound, value.wrappedValue - 1) }
            Text("\(value.wrappedValue)")
                .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                .frame(width: 54)
            roundControl("+") { value.wrappedValue = min(range.upperBound, value.wrappedValue + 1) }
            Spacer()
        }
        .frame(maxWidth: 560)
    }

    private func timerChoiceButton(_ seconds: Int) -> some View {
        let label = seconds == 30 ? "30s" : "\(seconds / 60)m"
        let isSelected = draft.startingSeconds == seconds

        return Button {
            draft.startingSeconds = seconds
        } label: {
            Text(label)
                .font(.title3.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .frame(width: 74, height: 54)
                .background(isSelected ? AppTheme.gold : AppTheme.paleBlue, in: Capsule())
                .foregroundStyle(isSelected ? .white : Color(red: 0.23, green: 0.45, blue: 0.61))
        }
        .buttonStyle(.plain)
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
    }

    private var header: some View {
        HStack(spacing: 16) {
            headerButton("Back", minWidth: DeveloperMenuLayoutSpec.backButtonMinWidth) {
                coordinator.route = .config
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
