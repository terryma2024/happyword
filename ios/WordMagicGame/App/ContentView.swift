import SwiftUI

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
            case .devMenu:
                #if DEBUG
                DevMenuView(coordinator: coordinator)
                #else
                HomeView(coordinator: coordinator)
                #endif
            }
        }
        .accessibilityIdentifier("RootView")
        .onAppear {
            OrientationController.apply(for: coordinator.route)
        }
        .onChange(of: coordinator.route) { _, route in
            OrientationController.apply(for: route)
        }
    }
}

#Preview {
    ContentView()
}
