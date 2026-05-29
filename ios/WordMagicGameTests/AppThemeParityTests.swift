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

    func testHomePackStoryLinePrefersEnglishStoryAndFallsBackToDifficultySummary() {
        let packWithStory = Pack(
            id: "storybook",
            title: "Storybook",
            subtitle: "",
            story: "",
            scene: SceneMetadata(storyEn: "A tiny door opens to five bright words.", storyZh: "小门打开，露出五个发光的单词。"),
            words: []
        )
        XCTAssertEqual(HomePackStoryLine.text(for: packWithStory), "A tiny door opens to five bright words.")

        let packWithoutStory = Pack(
            id: "levels",
            title: "Levels",
            subtitle: "",
            story: "",
            words: [
                WordEntry(id: "easy-1", word: "red", meaningZh: "红色", category: "color", difficulty: 1),
                WordEntry(id: "easy-2", word: "blue", meaningZh: "蓝色", category: "color", difficulty: 2),
                WordEntry(id: "mid", word: "purple", meaningZh: "紫色", category: "color", difficulty: 3),
                WordEntry(id: "hard", word: "violet", meaningZh: "紫罗兰色", category: "color", difficulty: 4),
            ]
        )
        XCTAssertEqual(HomePackStoryLine.text(for: packWithoutStory), "本词包 4 个单词，其中 2 个低难度，1 个中难度，1 个高难度")

        let packWithZeroBuckets = Pack(
            id: "hard-only",
            title: "Hard Only",
            subtitle: "",
            story: "",
            words: [
                WordEntry(id: "hard-1", word: "ancient", meaningZh: "古老的", category: "adjective", difficulty: 4),
                WordEntry(id: "hard-2", word: "brilliant", meaningZh: "灿烂的", category: "adjective", difficulty: 5),
            ]
        )
        XCTAssertEqual(HomePackStoryLine.text(for: packWithZeroBuckets), "本词包 2 个单词，其中 2 个高难度")
    }

    func testAdventureCardUsesPackStoryLineAndRemovesOldTagRow() throws {
        let root = try repoRoot()
        let homeView = try String(contentsOf: root.appending(path: "ios/WordMagicGame/Features/CoreLoop/HomeView.swift"))

        XCTAssertTrue(homeView.contains("Text(HomePackStoryLine.text(for: coordinator.selectedPack))"))
        XCTAssertEqual(HomeAdventureCardStoryStyle.lineLimit, 2)
        XCTAssertEqual(HomeAdventureCardStoryStyle.reservedHeight, 44)
        XCTAssertTrue(homeView.contains(".lineLimit(HomeAdventureCardStoryStyle.lineLimit)"))
        XCTAssertTrue(homeView.contains(".frame(maxWidth: .infinity, minHeight: HomeAdventureCardStoryStyle.reservedHeight, alignment: .center)"))
        XCTAssertFalse(homeView.contains("tag(\"常规\")"))
        XCTAssertFalse(homeView.contains("tag(\"拼写\")"))
        XCTAssertFalse(homeView.contains("tag(\"复习\")"))
        XCTAssertFalse(homeView.contains("tag(\"精英\")"))
        XCTAssertFalse(homeView.contains("tag(\"首领\")"))
        XCTAssertFalse(homeView.contains("今天的冒险包含 \\(levelCount) 关卡，含拼写、复习与首领关"))
        XCTAssertFalse(homeView.contains("Text(coordinator.selectedPack.story)"))
    }

    func testAdventureCardStartButtonCopyMatchesHarmonyAndAndroid() throws {
        let root = try repoRoot()
        let homeView = try String(contentsOf: root.appending(path: "ios/WordMagicGame/Features/CoreLoop/HomeView.swift"))

        XCTAssertTrue(homeView.contains("Text(\"开始今日冒险\")"))
        XCTAssertFalse(homeView.contains("Text(\"开始冒险\")"))
    }

    private func repoRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 {
            url.deleteLastPathComponent()
        }
        return url
    }
}
