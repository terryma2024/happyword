import PhotosUI
import SwiftUI
import VisionKit

struct ScanBindingView: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var shortCode = ""
    @State private var showManualSheet = false
    @State private var showScanner = false
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var isDecodingGalleryQR = false
    @State private var galleryHint = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header

                Text("请扫描家长端「添加设备」页面显示的二维码")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)

                VStack(spacing: 12) {
                    scanActions
                    Text(statusMessage)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(statusColor)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.85)
                        .frame(minHeight: 44, alignment: .top)
                        .accessibilityIdentifier("BindingMessage")

                    if coordinator.bindingMessage.hasPrefix("绑定成功") {
                        Button("完成") { coordinator.finishBinding() }
                            .font(.title3.weight(.heavy))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(AppTheme.mint, in: Capsule())
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("完成")
                            .frame(maxWidth: 360)
                    }
                }
                .frame(maxWidth: 560)
                .padding(.horizontal, AppTheme.pageHorizontalPadding)
                .padding(.vertical, 20)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
                .overlay {
                    RoundedRectangle(cornerRadius: 18).stroke(Color.gray.opacity(0.16), lineWidth: 1.2)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, AppTheme.pageHorizontalPadding)
            .padding(.vertical, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.page)
        .overlay {
            if isDecodingGalleryQR {
                ZStack {
                    Color.black.opacity(0.18).ignoresSafeArea()
                    ProgressView("正在识别二维码…")
                        .padding(18)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
            }
        }
        .sheet(isPresented: $showManualSheet) {
            manualEntrySheet
        }
        .fullScreenCover(isPresented: $showScanner) {
            DataScannerShellView(
                isPresented: $showScanner,
                onScan: { payload in
                    Task { await coordinator.bind(pairingInput: payload) }
                },
                onStartFailed: {
                    coordinator.bindingMessage = "无法启动相机扫码，请从图库选择或手动输入"
                }
            )
        }
        .onChange(of: photoPickerItem) { _, item in
            guard let item else { return }
            Task { await decodeGalleryQR(from: item) }
        }
        .onChange(of: coordinator.bindingMessage) { _, newValue in
            if newValue.hasPrefix("绑定成功") {
                showManualSheet = false
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            MonsterCodexStyleBackButton(
                action: { coordinator.route = .config },
                accessibilityIdentifier: "ScanBindingBack"
            )

            Text("扫码绑定家长账号")
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundStyle(AppTheme.navy)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("ScanBindingTitle")

            Color.clear.frame(width: 54, height: 54)
        }
    }

    private var scanActions: some View {
        VStack(spacing: 12) {
            Button("打开扫码器") {
                galleryHint = ""
                if DataScannerViewController.isSupported {
                    showScanner = true
                } else {
                    coordinator.bindingMessage = "当前设备不支持实时扫码，请从图库选择二维码或手动输入短码"
                }
            }
            .font(.title3.weight(.heavy))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(AppTheme.blue, in: Capsule())
            .buttonStyle(.plain)
            .accessibilityIdentifier("ScanBindingOpenScanner")

            if usesMockGalleryBinding {
                Button {
                    Task { await coordinator.bind(pairingInput: "123456") }
                } label: {
                    GalleryQRCodeButtonLabel()
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ScanBindingPickFromGallery")
            } else {
                PhotosPicker(selection: $photoPickerItem, matching: .images, photoLibrary: .shared()) {
                    GalleryQRCodeButtonLabel()
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ScanBindingPickFromGallery")
            }

            Button("无法扫码？手动输入短码") {
                galleryHint = ""
                coordinator.bindingMessage = ""
                shortCode = ""
                showManualSheet = true
            }
            .font(.headline.weight(.heavy))
            .foregroundStyle(AppTheme.navy)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(AppTheme.paleBlue, in: Capsule())
            .buttonStyle(.plain)
            .accessibilityIdentifier("ScanBindingManualEntry")

            Button("创建或登录 家长账号") {
                openParentLoginInBrowser()
            }
            .font(.headline.weight(.bold))
            .foregroundStyle(Color(red: 0.15, green: 0.39, blue: 0.92))
            .frame(maxWidth: .infinity, minHeight: 40)
            .buttonStyle(.plain)
            .accessibilityIdentifier("ScanBindingParentLoginLink")

            complianceLinks
        }
        .frame(maxWidth: 360)
    }

    private var complianceLinks: some View {
        VStack(spacing: 6) {
            Text("绑定或登录前请阅读")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("ScanBindingCompliancePrompt")
            HStack(spacing: 12) {
                policyButton("用户协议", id: "ScanBindingTermsButton", url: CompliancePolicy.termsOfServiceURL)
                policyButton("隐私政策", id: "ScanBindingPrivacyButton", url: CompliancePolicy.privacyPolicyURL)
            }
        }
    }

    private func policyButton(_ title: String, id: String, url: URL) -> some View {
        Button(title) {
            SystemBrowser.open(url)
        }
        .font(.subheadline.weight(.bold))
        .foregroundStyle(Color(red: 0.15, green: 0.39, blue: 0.92))
        .frame(maxWidth: .infinity, minHeight: 34)
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private var usesMockGalleryBinding: Bool {
        ProcessInfo.processInfo.arguments.contains("-UITestMockBinding")
    }

    private var manualEntrySheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("输入家长端生成的 6 位短码，也可粘贴二维码链接")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)

                TextField("6 位短码", text: $shortCode)
                    .keyboardType(.default)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("6 位短码")

                Button("绑定") {
                    Task { await coordinator.bind(pairingInput: shortCode) }
                }
                .font(.title3.weight(.heavy))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(AppTheme.red, in: Capsule())
                .buttonStyle(.plain)
                .accessibilityIdentifier("绑定")

                if !coordinator.bindingMessage.isEmpty {
                    Text(coordinator.bindingMessage)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(coordinator.bindingMessage.hasPrefix("绑定成功") ? AppTheme.mint : AppTheme.red)
                        .multilineTextAlignment(.center)
                }

                Button("创建或登录 家长账号") {
                    openParentLoginInBrowser()
                }
                .font(.headline.weight(.bold))
                .foregroundStyle(Color(red: 0.15, green: 0.39, blue: 0.92))
                .frame(maxWidth: .infinity, minHeight: 40)
                .buttonStyle(.plain)
                .accessibilityIdentifier("ScanBindingParentLoginLinkManual")

                complianceLinks

                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationTitle("手动输入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        showManualSheet = false
                    }
                    .accessibilityIdentifier("ScanBindingManualClose")
                }
            }
        }
    }

    private var statusMessage: String {
        if !galleryHint.isEmpty {
            return galleryHint
        }
        if coordinator.bindingMessage.isEmpty {
            return "绑定后会同步家庭词包和学习报告"
        }
        return coordinator.bindingMessage
    }

    private var statusColor: Color {
        if !galleryHint.isEmpty {
            return AppTheme.red
        }
        if coordinator.bindingMessage.hasPrefix("绑定成功") {
            return AppTheme.mint
        }
        if coordinator.bindingMessage.isEmpty {
            return .secondary
        }
        return AppTheme.red
    }

    private func openParentLoginInBrowser() {
        let url = BackendURLProvider.parentFamilyLoginPageURL(
            baseURL: coordinator.developerMenuViewModel.effectiveBaseURL
        )
        SystemBrowser.open(url)
    }

    private func decodeGalleryQR(from item: PhotosPickerItem) async {
        galleryHint = ""
        isDecodingGalleryQR = true
        defer {
            isDecodingGalleryQR = false
            photoPickerItem = nil
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                galleryHint = "无法读取所选照片"
                return
            }
            guard let image = UIImage(data: data) else {
                galleryHint = "无法读取所选照片"
                return
            }
            let payload = try QRCodeImageDecoder.firstQRPayload(in: image)
            await coordinator.bind(pairingInput: payload)
        } catch QRCodeImageDecoder.DecodeError.notFound {
            galleryHint = "未在照片中找到二维码，请换一张图片试试"
        } catch {
            galleryHint = "识别失败，请换一张清晰的二维码截图"
        }
    }
}

private struct GalleryQRCodeButtonLabel: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "photo.on.rectangle.angled")
            Text("从图库选择二维码")
        }
        .font(.title3.weight(.heavy))
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, minHeight: 52)
        .background(AppTheme.blue, in: Capsule())
    }
}

struct BoundDeviceInfoView: View {
    @ObservedObject var coordinator: AppCoordinator
    @Environment(\.openURL) private var openURL
    @State private var pin = ""
    @State private var isUnbindDialogPresented = false
    @State private var isUnbinding = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                MonsterCodexStyleBackButton(
                    action: { coordinator.route = .config },
                    accessibilityIdentifier: "BoundDeviceInfoBack"
                )

                Text("家长账户")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppTheme.navy)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("BoundDeviceInfoTitle")

                Color.clear.frame(width: 54, height: 54)
            }
            .padding(.top, 56)
            .padding(.bottom, 12)

            ScrollView {
                if let credentials = coordinator.cloudCredentialsStore.credentials {
                    VStack(spacing: 4) {
                        editableNicknameRow(credentials)
                        infoRow("Family ID", credentials.familyId)
                        infoRow("Binding ID", credentials.bindingId)
                        infoRow("Device ID 末四位", coordinator.currentDeviceIdSuffix())
                        infoRow("Device ID 来源", coordinator.currentDeviceIdSourceLabel())
                        infoRow("绑定时间", coordinator.currentBindingTimeText())
                        accountManagementButton(credentials)

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
                    .padding(.vertical, 8)
                } else {
                    Text("当前未绑定家长账号。")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, AppTheme.pageHorizontalPadding)
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

    private func accountManagementButton(_ credentials: CloudCredentials) -> some View {
        Button {
            openURL(coordinator.parentAccountSettingsURL(for: credentials))
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("账号与数据管理")
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                    Text("打开家长账号设置，可导出数据或删除账号")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right.square.fill")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(AppTheme.navy)
            }
            .foregroundStyle(AppTheme.navy)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(AppTheme.paleBlue, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("账号与数据管理")
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
