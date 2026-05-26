import SwiftUI
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientationMask: UIInterfaceOrientationMask = {
        if UIDevice.current.userInterfaceIdiom == .pad {
            return .all
        }

        let arguments = ProcessInfo.processInfo.arguments
        let portraitRouteArguments = [
            "-UITestRouteConfig",
            "-UITestRouteTodayPlan",
            "-UITestRoutePackManager",
            "-UITestRouteLearningReport",
            "-UITestRouteLearningReportEmpty",
            "-UITestRouteRedemptionHistory",
            "-UITestRoutePinSetup",
            "-UITestRouteScanBinding",
            "-UITestRouteBoundDeviceInfo",
            "-UITestRouteChildProfile",
            "-UITestRouteParentAdmin",
            "-UITestRouteLessonReview",
            "-UITestRouteMessageBubbleLab",
        ]
        if portraitRouteArguments.contains(where: arguments.contains) {
            return .portrait
        }
        return .landscape
    }()

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        Self.orientationMask
    }
}

@MainActor
enum OrientationController {
    static func mask(for route: AppRoute, idiom: UIUserInterfaceIdiom = UIDevice.current.userInterfaceIdiom) -> UIInterfaceOrientationMask {
        if idiom == .pad {
            return .all
        }

        switch route {
        case .config,
             .todayPlan,
             .checkInCalendar,
             .packManager,
             .learningReport,
             .redemptionHistory,
             .pinSetup,
             .scanBinding,
             .boundDeviceInfo,
             .childProfile,
             .parentAdmin,
             .lessonReview,
             .messageBubbleLab:
            return .portrait
        default:
            return .landscape
        }
    }

    static func apply(for route: AppRoute) {
        let mask = mask(for: route)
        AppDelegate.orientationMask = mask

        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
        scene.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }
}
