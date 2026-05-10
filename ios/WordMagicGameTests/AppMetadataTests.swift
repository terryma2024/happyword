@testable import WordMagicGame
import XCTest

final class AppMetadataTests: XCTestCase {
    func testBundleIdentifierMatchesHarmonyOS() {
        XCTAssertEqual(AppMetadata.bundleIdentifier, "com.terryma.wordmagicgame")
    }

    func testVersionMatchesHarmonyOSBaseline() {
        XCTAssertEqual(AppMetadata.harmonyVersionName, "0.6.7.8")
        XCTAssertEqual(AppMetadata.harmonyVersionCode, 1_006_016)
    }
}
