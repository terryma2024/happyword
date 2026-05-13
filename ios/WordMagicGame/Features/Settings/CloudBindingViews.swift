import SwiftUI

struct ScanBindingView: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var shortCode = ""

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button("返回") { coordinator.route = .config }
                    .font(.headline.weight(.bold))
                Spacer()
                Text("绑定家长账号")
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppTheme.navy)
                Spacer()
                Color.clear.frame(width: 48, height: 1)
            }

            HStack(spacing: 28) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("家长端短码")
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppTheme.navy)
                    Text("输入家长端生成的 6 位短码，也可粘贴二维码链接")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(coordinator.bindingMessage.isEmpty ? "绑定后会同步家庭词包和学习报告" : coordinator.bindingMessage)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(coordinator.bindingMessage.hasPrefix("绑定成功") ? AppTheme.mint : .secondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .frame(height: 46, alignment: .topLeading)
                        .accessibilityIdentifier("BindingMessage")
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                TextField("6 位短码", text: $shortCode)
                    .keyboardType(.default)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 24, weight: .bold, design: .rounded).monospacedDigit())
                    .multilineTextAlignment(.center)
                    .frame(width: 280)
                    .accessibilityIdentifier("6 位短码")

                VStack(spacing: 12) {
                    Button("绑定") {
                        Task { await coordinator.bind(pairingInput: shortCode) }
                    }
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(.white)
                    .frame(width: 128, height: 48)
                    .background(AppTheme.red, in: Capsule())
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("绑定")

                    if coordinator.bindingMessage.hasPrefix("绑定成功") {
                        Button("完成") { coordinator.finishBinding() }
                            .font(.title3.weight(.heavy))
                            .foregroundStyle(AppTheme.navy)
                            .frame(width: 128, height: 48)
                            .background(AppTheme.cream, in: Capsule())
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("完成")
                    }
                }
                .frame(width: 142)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 150)
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18).stroke(Color.gray.opacity(0.16), lineWidth: 1.2)
            }
        }
        .padding(.horizontal, 42)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppTheme.page)
    }
}

struct BoundDeviceInfoView: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var pin = ""
    @State private var isUnbindDialogPresented = false
    @State private var isUnbinding = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("家长账户")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppTheme.navy)
                Spacer()
                Button("返回") { coordinator.route = .config }
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(AppTheme.navy)
                    .frame(width: 92, height: 52)
                    .background(AppTheme.paleBlue, in: Capsule())
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 56)
            .padding(.bottom, 12)

            Spacer(minLength: 8)

            if let credentials = coordinator.cloudCredentialsStore.credentials {
                VStack(spacing: 4) {
                    editableNicknameRow(credentials)
                    infoRow("Family ID", credentials.familyId)
                    infoRow("Binding ID", credentials.bindingId)
                    infoRow("Device ID 末四位", coordinator.currentDeviceIdSuffix())
                    infoRow("Device ID 来源", coordinator.currentDeviceIdSourceLabel())
                    infoRow("绑定时间", coordinator.currentBindingTimeText())

                    Button(isUnbinding ? "正在解除…" : "解除设备绑定") {
                        pin = ""
                        coordinator.bindingMessage = ""
                        isUnbindDialogPresented = true
                    }
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(AppTheme.red, in: Capsule())
                    .buttonStyle(.plain)
                    .disabled(isUnbinding)
                    .accessibilityIdentifier("解除设备绑定")

                    if !coordinator.bindingMessage.isEmpty && !isUnbindDialogPresented {
                        Text(coordinator.bindingMessage)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppTheme.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: 620)
                .padding(16)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16).stroke(Color.gray.opacity(0.10), lineWidth: 1)
                }
            } else {
                Text("当前未绑定家长账号。")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }

            Spacer(minLength: 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.page)
        .overlay {
            if isUnbindDialogPresented {
                unbindDialog
            }
        }
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(title)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 142, alignment: .leading)
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.navy)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
    }

    private func editableNicknameRow(_ credentials: CloudCredentials) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Text("孩子档案")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 142, alignment: .leading)
            Text("\(credentials.avatarEmoji) \(credentials.nickname)")
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(AppTheme.navy)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("✏️ 编辑") {
                coordinator.openChildProfile()
            }
            .font(.headline.weight(.heavy))
            .foregroundStyle(AppTheme.navy)
            .frame(width: 116, height: 42)
            .background(AppTheme.paleBlue, in: Capsule())
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
    }

    private var unbindDialog: some View {
        ZStack {
            Color.black.opacity(0.24)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                Text("解除设备绑定")
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppTheme.navy)

                SecureField("家长 PIN", text: $pin)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3.weight(.bold))
                    .frame(width: 280)
                    .accessibilityIdentifier("家长 PIN")
                    .onChange(of: pin) { _, newValue in
                        pin = GameConfig.sanitizePinInput(newValue)
                    }

                Text(coordinator.bindingMessage.isEmpty ? "输入家长 PIN 后解除当前设备绑定" : coordinator.bindingMessage)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(coordinator.bindingMessage.isEmpty ? .secondary : AppTheme.red)
                    .multilineTextAlignment(.center)
                    .frame(height: 36)

                HStack(spacing: 12) {
                    Button("取消") {
                        isUnbindDialogPresented = false
                        pin = ""
                        coordinator.bindingMessage = ""
                    }
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(AppTheme.navy)
                    .frame(width: 124, height: 44)
                    .background(AppTheme.paleBlue, in: Capsule())
                    .buttonStyle(.plain)

                    Button(isUnbinding ? "解除中…" : "确认解除") {
                        confirmUnbind()
                    }
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(.white)
                    .frame(width: 124, height: 44)
                    .background(AppTheme.red, in: Capsule())
                    .buttonStyle(.plain)
                    .disabled(isUnbinding)
                }
            }
            .padding(20)
            .frame(width: 390)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18).stroke(Color.gray.opacity(0.12), lineWidth: 1)
            }
        }
    }

    private func confirmUnbind() {
        isUnbinding = true
        Task {
            await coordinator.confirmUnbind(pin: pin)
            isUnbinding = false
            if coordinator.route == .config {
                isUnbindDialogPresented = false
                pin = ""
            }
        }
    }
}
