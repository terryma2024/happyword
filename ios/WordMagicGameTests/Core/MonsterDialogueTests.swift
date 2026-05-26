@testable import WordMagicGame
import XCTest

final class MonsterDialogueTests: XCTestCase {
    func testDialogueCatalogMatchesSignedFeatureCatalog() throws {
        let expected = try Self.loadFeatureDialogueCatalog()

        XCTAssertEqual(MonsterDialogueCatalog.all.count, 100)
        XCTAssertEqual(MonsterDialogueCatalog.all.count, expected.count)

        for row in expected {
            let actual = try XCTUnwrap(MonsterDialogueCatalog.dialogue(catalogIndex1Based: row.index))
            XCTAssertEqual(MonsterCodex.entry(catalogIndex1Based: row.index).nameEn, row.name)
            XCTAssertEqual(actual.introLine.en, row.introEn, "intro EN mismatch for \(row.index) \(row.name)")
            XCTAssertEqual(actual.introLine.zh, row.introZh, "intro ZH mismatch for \(row.index) \(row.name)")
            XCTAssertEqual(actual.defeatLine.en, row.defeatEn, "defeat EN mismatch for \(row.index) \(row.name)")
            XCTAssertEqual(actual.defeatLine.zh, row.defeatZh, "defeat ZH mismatch for \(row.index) \(row.name)")
        }
    }

    func testDialogueResolverUsesFallbackForMissingCatalogIndex() {
        let fallback = MonsterDialogueCatalog.resolve(catalogIndex1Based: 0, monsterName: "Mystery Boss")

        XCTAssertEqual(fallback.introLine.en, "Mystery Boss challenges you!")
        XCTAssertEqual(fallback.introLine.zh, "来挑战Mystery Boss吧！")
        XCTAssertEqual(fallback.defeatLine.en, "Mystery Boss yields to your words.")
        XCTAssertEqual(fallback.defeatLine.zh, "Mystery Boss认可你的单词。")
    }

    private static func loadFeatureDialogueCatalog() throws -> [DialogueRow] {
        let url = repoRoot
            .appendingPathComponent("docs/features/2026-05-25-boss-dialogue-v0-9-2/boss-dialogue-catalog.md")
        let text = try String(contentsOf: url, encoding: .utf8)
        return text
            .split(separator: "\n")
            .compactMap { line -> DialogueRow? in
                guard line.hasPrefix("| ") else { return nil }
                let cells = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                guard cells.count == 6,
                      let index = Int(cells[0])
                else { return nil }
                return DialogueRow(
                    index: index,
                    name: cells[1],
                    introEn: cells[2],
                    introZh: cells[3],
                    defeatEn: cells[4],
                    defeatZh: cells[5]
                )
            }
    }

    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private struct DialogueRow {
    var index: Int
    var name: String
    var introEn: String
    var introZh: String
    var defeatEn: String
    var defeatZh: String
}
