import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var coordinator = AppCoordinator()

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            switch coordinator.route {
            case .home:
                HomeView(coordinator: coordinator)
            case .battle:
                BattleView(coordinator: coordinator)
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
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.82), in: Capsule())
                        .accessibilityIdentifier("AppToast")
                        .padding(.bottom, 28)
                }
                .transition(.opacity)
            }
        }
        .accessibilityIdentifier("RootView")
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

#Preview {
    ContentView()
}
