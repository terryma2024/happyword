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
            }
            .padding(.horizontal, 42)
            .padding(.vertical, 22)
        }
        .background(AppTheme.page)
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
            SecureField("再次输入 PIN", text: $confirmation)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("ParentPinConfirmInput")
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
