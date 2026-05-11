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

    func testHarmonyButtonImageAssetsAreCopiedFromHarmonyOS() throws {
        let pairs = [
            HarmonyAssetPair(assetName: "HarmonyReview", sourcePath: "icons/review.png", filename: "review.png"),
            HarmonyAssetPair(assetName: "HarmonyCodex", sourcePath: "icons/codex.png", filename: "codex.png"),
            HarmonyAssetPair(assetName: "HarmonyWishlist", sourcePath: "icons/wishlist.png", filename: "wishlist.png"),
            HarmonyAssetPair(assetName: "HarmonyGear", sourcePath: "icons/gear.png", filename: "gear.png"),
            HarmonyAssetPair(assetName: "HarmonyScroll", sourcePath: "icons/scroll.png", filename: "scroll.png"),
            HarmonyAssetPair(assetName: "HarmonyStartIcon", sourcePath: "icons/start_icon.svg", filename: "start_icon.svg"),
            HarmonyAssetPair(assetName: "HarmonyWand", sourcePath: "icons/wand.svg", filename: "wand.svg")
        ]

        try assertHarmonyAssets(pairs, sourceRoot: "harmonyos/entry/src/main/resources/rawfile")
    }

    func testHarmonyCharacterImageAssetsAreCopiedFromHarmonyOS() throws {
        let pairs = [
            HarmonyAssetPair(assetName: "HarmonyCharacterMagician", sourcePath: "character/magican.svg", filename: "magican.svg"),
            HarmonyAssetPair(assetName: "HarmonyCharacterMagicianFight", sourcePath: "character/magican_fight.svg", filename: "magican_fight.svg"),
            HarmonyAssetPair(assetName: "HarmonyCharacterMagicianBeaten", sourcePath: "character/magican_beaten.svg", filename: "magican_beaten.svg"),
            HarmonyAssetPair(assetName: "HarmonyCharacterMagicianDizzy", sourcePath: "character/magican_dizz.svg", filename: "magican_dizz.svg"),
            HarmonyAssetPair(assetName: "HarmonyCharacterSlime", sourcePath: "character/slime.svg", filename: "slime.svg"),
            HarmonyAssetPair(assetName: "HarmonyCharacterZombie", sourcePath: "character/zombie.svg", filename: "zombie.svg"),
            HarmonyAssetPair(assetName: "HarmonyCharacterDragon", sourcePath: "character/dragon.svg", filename: "dragon.svg"),
            HarmonyAssetPair(assetName: "HarmonyCharacterJellyfish", sourcePath: "character/jellyfish.svg", filename: "jellyfish.svg"),
            HarmonyAssetPair(assetName: "HarmonyCharacterKraken", sourcePath: "character/kraken.svg", filename: "kraken.svg"),
            HarmonyAssetPair(assetName: "HarmonyCharacterWitch", sourcePath: "character/witch.svg", filename: "witch.svg"),
            HarmonyAssetPair(assetName: "HarmonyCharacterImpKing", sourcePath: "character/imp-king.svg", filename: "imp-king.svg"),
            HarmonyAssetPair(assetName: "HarmonyCharacterPhoenix", sourcePath: "character/phoenix.svg", filename: "phoenix.svg"),
            HarmonyAssetPair(assetName: "HarmonyCharacterPumpkinKing", sourcePath: "character/pumpkin-king.svg", filename: "pumpkin-king.svg"),
            HarmonyAssetPair(assetName: "HarmonyCharacterSnowQueen", sourcePath: "character/snow-queen.svg", filename: "snow-queen.svg"),
            HarmonyAssetPair(assetName: "HarmonyCharacterUnicorn", sourcePath: "character/unicorn.svg", filename: "unicorn.svg")
        ]

        try assertHarmonyAssets(pairs, sourceRoot: "harmonyos/entry/src/main/resources/rawfile")
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

    private func assertHarmonyAssets(_ pairs: [HarmonyAssetPair], sourceRoot: String) throws {
        let root = try repoRoot()
        let assetCatalog = root.appending(path: "ios/WordMagicGame/Resources/Assets.xcassets")
        let harmonyRoot = root.appending(path: sourceRoot)

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
                try Data(contentsOf: harmonyRoot.appending(path: pair.sourcePath)),
                pair.assetName
            )
        }
    }
}

private struct HarmonyAssetPair {
    let assetName: String
    let sourcePath: String
    let filename: String
}
