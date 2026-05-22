import SafariServices
import UIKit

enum CompliancePolicy {
    static let privacyPolicyURL = URL(string: "https://happyword.cool/privacy")!
    static let termsOfServiceURL = URL(string: "https://happyword.cool/terms")!
    static let reportChannelURL = URL(string: "https://happyword.cool/report_and_appeal")!
    static let privacyConsentUserDefaultsKey = "privacy_consent_v1"
}

@MainActor
protocol BrowserPresentationHost: AnyObject {
    var presentedViewController: UIViewController? { get }

    func present(
        _ viewControllerToPresent: UIViewController,
        animated flag: Bool,
        completion: (() -> Void)?
    )
}

extension UIViewController: BrowserPresentationHost {}

enum SystemBrowser {
    @MainActor
    static func open(_ url: URL) {
        guard let host = activePresentationHost() else {
            return
        }
        open(url, from: host)
    }

    @MainActor
    @discardableResult
    static func open(_ url: URL, from host: BrowserPresentationHost) -> Bool {
        let browser = SFSafariViewController(url: url)
        browser.dismissButtonStyle = .close
        host.present(browser, animated: true, completion: nil)
        return true
    }

    @MainActor
    private static func activePresentationHost() -> BrowserPresentationHost? {
        let windowScene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        let root = windowScene?.windows.first { $0.isKeyWindow }?.rootViewController
        return topViewController(from: root)
    }

    @MainActor
    private static func topViewController(from root: UIViewController?) -> UIViewController? {
        if let navigationController = root as? UINavigationController {
            return topViewController(from: navigationController.visibleViewController)
        }
        if let tabBarController = root as? UITabBarController {
            return topViewController(from: tabBarController.selectedViewController)
        }
        if let presented = root?.presentedViewController {
            return topViewController(from: presented)
        }
        return root
    }
}
