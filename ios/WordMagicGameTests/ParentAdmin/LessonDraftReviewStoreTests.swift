@testable import WordMagicGame
import XCTest

final class LessonDraftReviewStoreTests: XCTestCase {
    func testToggleEditAndApprovePayloadOnlyKeepsSelectedWords() throws {
        let draft = LessonDraft.fixtureReviewedDraft
        var store = LessonDraftReviewStore(draft: draft)

        store.toggleKeep(rowId: draft.words[1].id)
        store.edit(rowId: draft.words[0].id, word: "wizard", meaningZh: "魔法师")

        let payload = store.approvePayload()

        XCTAssertEqual(payload.categoryId, draft.categoryId)
        XCTAssertEqual(payload.words.count, 1)
        XCTAssertEqual(payload.words[0].word, "wizard")
        XCTAssertEqual(payload.words[0].meaningZh, "魔法师")
    }
}
