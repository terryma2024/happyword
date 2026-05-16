import UIKit

enum SystemBrowser {
    @MainActor
    static func open(_ url: URL) {
        UIApplication.shared.open(url)
    }
}
