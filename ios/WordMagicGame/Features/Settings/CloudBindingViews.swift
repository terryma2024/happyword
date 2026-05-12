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
                    Text("输入家长端生成的 6 位短码")
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
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
                    .multilineTextAlignment(.center)
                    .frame(width: 220)
                    .accessibilityIdentifier("6 位短码")
                    .onChange(of: shortCode) { _, value in
                        shortCode = String(value.filter(\.isNumber).prefix(6))
                    }

                VStack(spacing: 12) {
                    Button("绑定") {
                        Task { await coordinator.bind(shortCode: shortCode) }
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
        .background(AppTheme.page)
    }
}

struct BoundDeviceInfoView: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var pin = ""

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button("返回") { coordinator.route = .config }
                    .font(.headline.weight(.bold))
                Spacer()
                Text("绑定设备")
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppTheme.navy)
                Spacer()
                Color.clear.frame(width: 48, height: 1)
            }

            HStack(spacing: 18) {
                if let credentials = coordinator.cloudCredentialsStore.credentials {
                    VStack(spacing: 8) {
                        Text(credentials.avatarEmoji)
                            .font(.system(size: 46))
                        Text(credentials.nickname)
                            .font(.system(size: 26, weight: .heavy, design: .rounded))
                            .foregroundStyle(AppTheme.navy)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(width: 230)

                    VStack(spacing: 8) {
                        infoRow("家庭", credentials.familyId)
                        infoRow("档案", credentials.childProfileId)
                        infoRow("设备", coordinator.deviceIdProvider.deviceId())
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Text("尚未绑定")
                        .font(.title.weight(.heavy))
                        .foregroundStyle(AppTheme.navy)
                        .frame(maxWidth: .infinity)
                }

                VStack(spacing: 10) {
                    SecureField("家长 PIN", text: $pin)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                        .accessibilityIdentifier("家长 PIN")

                    Text(coordinator.bindingMessage.isEmpty ? "输入 PIN 后可解除当前设备绑定" : coordinator.bindingMessage)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(coordinator.bindingMessage.isEmpty ? .secondary : AppTheme.red)
                        .multilineTextAlignment(.center)
                        .frame(width: 260, height: 38)

                    Button("解除绑定") {
                        coordinator.unbind(pin: pin)
                    }
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(.white)
                    .frame(width: 150, height: 44)
                    .background(AppTheme.red, in: Capsule())
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("解除绑定")
                }
                .frame(width: 300)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 170)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18).stroke(Color.gray.opacity(0.16), lineWidth: 1.2)
            }
        }
        .padding(.horizontal, 42)
        .padding(.vertical, 14)
        .background(AppTheme.page)
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(AppTheme.navy)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: 430, alignment: .leading)
    }
}
