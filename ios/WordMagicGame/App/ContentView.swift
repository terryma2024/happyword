import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var coordinator = AppCoordinator()
    @AppStorage(CompliancePolicy.privacyConsentUserDefaultsKey) private var hasPrivacyConsent = false

    private var shouldShowPrivacyConsent: Bool {
        !hasPrivacyConsent && !ProcessInfo.processInfo.arguments.contains("-UITestResetState")
    }

    var body: some View {
        ZStack {
            AppTheme.page.ignoresSafeArea()

            switch coordinator.route {
            case .home:
                HomeView(coordinator: coordinator)
            case .battle:
                if let engine = coordinator.battleEngine {
                    BattleView(coordinator: coordinator, engine: engine)
                }
            case .result:
                ResultView(coordinator: coordinator)
            case .config:
                ConfigView(coordinator: coordinator)
            case .pinSetup:
                ParentPinSetupView(coordinator: coordinator)
            case .pinGate:
                ParentPinGateView(coordinator: coordinator)
            case .parentAdmin:
                ParentAdminView(coordinator: coordinator)
            case .lessonReview:
                LessonDraftReviewView(coordinator: coordinator)
            case .monsterCodex:
                MonsterCodexView(coordinator: coordinator)
            case .packManager:
                PackManagerView(coordinator: coordinator)
            case .wishlist:
                WishlistView(coordinator: coordinator)
            case .redemptionHistory:
                RedemptionHistoryView(coordinator: coordinator)
            case .todayPlan:
                TodayPlanView(coordinator: coordinator)
            case .learningReport:
                LearningReportView(coordinator: coordinator)
            case .checkInCalendar:
                CheckInCalendarView(coordinator: coordinator, store: coordinator.checkInStore)
            case .scanBinding:
                ScanBindingView(coordinator: coordinator)
            case .boundDeviceInfo:
                BoundDeviceInfoView(coordinator: coordinator)
            case .childProfile:
                ChildProfileView(coordinator: coordinator)
            case .devMenu:
                if DeveloperToolsPolicy.isDeveloperToolsVisible() {
                    DevMenuView(coordinator: coordinator)
                } else {
                    ConfigView(coordinator: coordinator)
                }
            case .bypassSecret:
                if DeveloperToolsPolicy.isDeveloperToolsVisible() {
                    BypassSecretView(coordinator: coordinator)
                } else {
                    ConfigView(coordinator: coordinator)
                }
            }

            if let toastMessage = coordinator.toastMessage {
                VStack {
                    Spacer()
                    Text(toastMessage)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppTheme.pageHorizontalPadding)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.90), in: Capsule())
                        .accessibilityIdentifier("AppToast")
                        .padding(.bottom, 28)
                }
                .transition(.opacity)
            }

            if shouldShowPrivacyConsent {
                PrivacyConsentOverlay {
                    hasPrivacyConsent = true
                }
            }
        }
        .onAppear {
            OrientationController.apply(for: coordinator.route)
        }
        .onChange(of: coordinator.route) { _, route in
            OrientationController.apply(for: route)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            Task { await coordinator.syncWordStatsIfPossible(showStatus: false) }
        }
    }
}

private struct PrivacyConsentOverlay: View {
    let onAgree: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.52).ignoresSafeArea()
            VStack(spacing: 14) {
                Text("请阅读并同意隐私政策")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(red: 0.12, green: 0.16, blue: 0.23))
                    .accessibilityIdentifier("PrivacyConsentTitle")

                Text("魔法背单词会在家长绑定、学习同步、课本图片导入和愿望兑换时处理必要信息。继续使用前，请阅读《用户协议》和《隐私政策》。")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 0.23, green: 0.26, blue: 0.32))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("PrivacyConsentBody")

                HStack(spacing: 12) {
                    policyButton("用户协议", id: "PrivacyConsentTermsButton", url: CompliancePolicy.termsOfServiceURL)
                    policyButton("隐私政策", id: "PrivacyConsentPolicyButton", url: CompliancePolicy.privacyPolicyURL)
                }

                Button("同意并继续") {
                    onAgree()
                }
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(AppTheme.red, in: Capsule())
                .buttonStyle(.plain)
                .accessibilityIdentifier("PrivacyConsentAgreeButton")
            }
            .padding(24)
            .frame(maxWidth: 520)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(red: 1.0, green: 0.996, blue: 0.984))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color(red: 1.0, green: 0.82, blue: 0.54), lineWidth: 2)
            )
            .shadow(color: .black.opacity(0.26), radius: 22, y: 10)
            .padding(.horizontal, 28)
            .accessibilityIdentifier("PrivacyConsentDialog")
        }
    }

    private func policyButton(_ title: String, id: String, url: URL) -> some View {
        Button(title) {
            SystemBrowser.open(url)
        }
        .font(.system(size: 15, weight: .bold, design: .rounded))
        .foregroundStyle(Color(red: 0.11, green: 0.3, blue: 0.85))
        .frame(maxWidth: .infinity, minHeight: 40)
        .background(AppTheme.paleBlue, in: Capsule())
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

#Preview {
    ContentView()
}
