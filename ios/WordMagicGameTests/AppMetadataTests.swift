@testable import WordMagicGame
import XCTest

final class AppMetadataTests: XCTestCase {
    func testDisplayNameIsChineseProductName() throws {
        XCTAssertEqual(AppMetadata.displayName, "魔法背单词")

        let infoPlist = try repoRoot()
            .appending(path: "ios/WordMagicGame/Resources/Info.plist")
        let data = try Data(contentsOf: infoPlist)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        XCTAssertEqual(plist?["CFBundleDisplayName"] as? String, "魔法背单词")
    }

    func testBundleIdentifierMatchesHarmonyOS() {
        XCTAssertEqual(AppMetadata.bundleIdentifier, "com.terryma.wordmagicgame")
    }

    func testVersionMatchesHarmonyOSBaseline() {
        XCTAssertEqual(AppMetadata.harmonyVersionName, "0.6.7.8")
        XCTAssertEqual(AppMetadata.harmonyVersionCode, 1_006_016)
    }

    func testAppIconAssetReferencesHarmonyLauncherImage() throws {
        let appIconSet = try repoRoot()
            .appending(path: "ios/WordMagicGame/Resources/Assets.xcassets/AppIcon.appiconset")
        let contentsURL = appIconSet.appending(path: "Contents.json")
        let contentsData = try Data(contentsOf: contentsURL)
        let contents = try JSONSerialization.jsonObject(with: contentsData) as? [String: Any]
        let images = contents?["images"] as? [[String: Any]]
        let image = images?.first { entry in
            entry["idiom"] as? String == "universal"
                && entry["platform"] as? String == "ios"
                && entry["size"] as? String == "1024x1024"
        }

        let filename = try XCTUnwrap(image?["filename"] as? String)
        let iconURL = appIconSet.appending(path: filename)
        XCTAssertTrue(FileManager.default.fileExists(atPath: iconURL.path))
        XCTAssertEqual(try pngSize(at: iconURL), CGSize(width: 1024, height: 1024))
    }

    func testIOSImageAssetNamesDoNotUseSourcePlatformPrefix() throws {
        let assetCatalog = try repoRoot()
            .appending(path: "ios/WordMagicGame/Resources/Assets.xcassets")
        let imageSetNames = try FileManager.default
            .contentsOfDirectory(at: assetCatalog, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "imageset" }
            .map { $0.deletingPathExtension().lastPathComponent }
        let sourcePlatformNames = imageSetNames.filter {
            $0.localizedCaseInsensitiveContains("Harmony")
        }

        XCTAssertEqual(sourcePlatformNames, [])
    }

    func testIOSButtonImageAssetsAreCopiedFromHarmonyOS() throws {
        let pairs = [
            SourceAssetPair(assetName: "ToolbarReview", sourcePath: "icons/review.png", filename: "review.png"),
            SourceAssetPair(assetName: "ToolbarCodex", sourcePath: "icons/codex.png", filename: "codex.png"),
            SourceAssetPair(assetName: "ToolbarWishlist", sourcePath: "icons/wishlist.png", filename: "wishlist.png"),
            SourceAssetPair(assetName: "SettingsGear", sourcePath: "icons/gear.png", filename: "gear.png"),
            SourceAssetPair(assetName: "MagicScroll", sourcePath: "icons/scroll.png", filename: "scroll.png"),
            SourceAssetPair(assetName: "StartIcon", sourcePath: "icons/start_icon.svg", filename: "start_icon.svg"),
            SourceAssetPair(assetName: "MagicWand", sourcePath: "icons/wand.svg", filename: "wand.svg")
        ]

        try assertCopiedSourceAssets(pairs, sourceRoot: "harmonyos/entry/src/main/resources/rawfile")
    }

    func testIOSCharacterImageAssetsAreCopiedFromHarmonyOS() throws {
        let playerPairs = [
            SourceAssetPair(assetName: "CharacterMagician", sourcePath: "character/magican.svg", filename: "magican.svg"),
            SourceAssetPair(assetName: "CharacterMagicianFight", sourcePath: "character/magican_fight.svg", filename: "magican_fight.svg"),
            SourceAssetPair(assetName: "CharacterMagicianBeaten", sourcePath: "character/magican_beaten.svg", filename: "magican_beaten.svg"),
            SourceAssetPair(assetName: "CharacterMagicianDizzy", sourcePath: "character/magican_dizz.svg", filename: "magican_dizz.svg")
        ]
        let monsterPairs = MonsterCodex.entries.map {
            SourceAssetPair(assetName: $0.assetName, sourcePath: "character/\($0.key).svg", filename: "\($0.key).svg")
        }

        try assertCopiedSourceAssets(playerPairs + monsterPairs, sourceRoot: "harmonyos/entry/src/main/resources/rawfile")
    }

    private func repoRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 {
            url.deleteLastPathComponent()
        }
        return url
    }

    private func pngSize(at url: URL) throws -> CGSize {
        let data = try Data(contentsOf: url)
        XCTAssertGreaterThanOrEqual(data.count, 24)
        XCTAssertEqual(Array(data[0..<8]), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let width = UInt32(data[16]) << 24 | UInt32(data[17]) << 16 | UInt32(data[18]) << 8 | UInt32(data[19])
        let height = UInt32(data[20]) << 24 | UInt32(data[21]) << 16 | UInt32(data[22]) << 8 | UInt32(data[23])
        return CGSize(width: Int(width), height: Int(height))
    }

    private func assertCopiedSourceAssets(_ pairs: [SourceAssetPair], sourceRoot: String) throws {
        let root = try repoRoot()
        let assetCatalog = root.appending(path: "ios/WordMagicGame/Resources/Assets.xcassets")
        let sourceAssetRoot = root.appending(path: sourceRoot)

        for pair in pairs {
            let imageSet = assetCatalog.appending(path: "\(pair.assetName).imageset")
            let contentsURL = imageSet.appending(path: "Contents.json")
            let contentsData = try Data(contentsOf: contentsURL)
            let contents = try JSONSerialization.jsonObject(with: contentsData) as? [String: Any]
            let images = contents?["images"] as? [[String: Any]]
            let image = images?.first { $0["idiom"] as? String == "universal" }

            XCTAssertEqual(image?["filename"] as? String, pair.filename, pair.assetName)
            XCTAssertEqual(
                try Data(contentsOf: imageSet.appending(path: pair.filename)),
                try Data(contentsOf: sourceAssetRoot.appending(path: pair.sourcePath)),
                pair.assetName
            )
        }
    }
}

private struct SourceAssetPair {
    let assetName: String
    let sourcePath: String
    let filename: String
}
