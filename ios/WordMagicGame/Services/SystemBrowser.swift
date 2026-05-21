import UIKit

enum CompliancePolicy {
    static let privacyPolicyURL = URL(string: "https://happyword.cool/privacy")!
    static let termsOfServiceURL = URL(string: "https://happyword.cool/terms")!
    static let reportChannelURL = URL(string: "https://happyword.cool/report_and_appeal")!
    static let privacyConsentUserDefaultsKey = "privacy_consent_v1"
}

enum SystemBrowser {
    @MainActor
    static func open(_ url: URL) {
        UIApplication.shared.open(url)
    }
}
