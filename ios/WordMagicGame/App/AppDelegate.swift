import SwiftUI
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientationMask: UIInterfaceOrientationMask = {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-UITestRouteParentAdmin") || arguments.contains("-UITestRouteLessonReview") {
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
    static func apply(for route: AppRoute) {
        let mask: UIInterfaceOrientationMask

        switch route {
        case .parentAdmin, .lessonReview:
            mask = .portrait
        default:
            mask = .landscape
        }

        AppDelegate.orientationMask = mask

        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
        scene.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }
}
