@testable import WordMagicGame
import XCTest

final class AppThemeParityTests: XCTestCase {
    func testAdventureCardUsesSelectedPackSceneColors() throws {
        let root = try repoRoot()
        let homeView = try String(contentsOf: root.appending(path: "ios/WordMagicGame/Features/CoreLoop/HomeView.swift"))

        XCTAssertTrue(homeView.contains("HomeScenePalette(scene: coordinator.selectedPack.scene)"))
        XCTAssertTrue(homeView.contains(".background(scenePalette.primary, in: RoundedRectangle(cornerRadius: 24))"))
        XCTAssertTrue(homeView.contains(".stroke(scenePalette.accent.opacity(0.72), lineWidth: 1.5)"))
        XCTAssertFalse(homeView.contains(".background(AppTheme.cream, in: RoundedRectangle(cornerRadius: 24))"))
        XCTAssertFalse(homeView.contains(".stroke(AppTheme.gold.opacity(0.48), lineWidth: 1.5)"))
    }

    func testHexColorParserSupportsPackSceneMetadata() {
        let palette = HomeScenePalette(scene: SceneMetadata(bgPrimary: "#fff6e0", bgAccent: "ffd49a"))

        XCTAssertEqual(palette.primaryHex, "#FFF6E0")
        XCTAssertEqual(palette.accentHex, "#FFD49A")
    }

    func testAdventureSummaryUsesFixedHarmonyOSCopy() throws {
        let root = try repoRoot()
        let homeView = try String(contentsOf: root.appending(path: "ios/WordMagicGame/Features/CoreLoop/HomeView.swift"))

        XCTAssertTrue(homeView.contains("今天的冒险包含 \\(levelCount) 关卡，含拼写、复习与首领关"))
        XCTAssertFalse(homeView.contains("Text(coordinator.selectedPack.story)"))
    }

    private func repoRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 {
            url.deleteLastPathComponent()
        }
        return url
    }
}
