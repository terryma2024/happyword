@testable import WordMagicGame
import XCTest

final class ParentLessonAPITests: XCTestCase {
    func testLessonURLsUseFamilyPrefix() throws {
        let base = try XCTUnwrap(URL(string: "https://api.example.test"))
        let fid = "fam-abc"
        XCTAssertEqual(
            ParentLessonAPI.lessonsImportURL(base: base, familyId: fid).absoluteString,
            "https://api.example.test/api/v1/family/fam-abc/lessons/import"
        )
        let list = ParentLessonAPI.lessonDraftsListURL(base: base, familyId: fid, status: "pending", page: 2, size: 10)
        XCTAssertTrue(list.absoluteString.contains("/api/v1/family/fam-abc/lesson-drafts"))
        XCTAssertTrue(list.absoluteString.contains("status=pending"))
        XCTAssertTrue(list.absoluteString.contains("page=2"))
        XCTAssertTrue(list.absoluteString.contains("size=10"))
    }

    func testUnboundFamilyUsesUnderscore() throws {
        let base = try XCTUnwrap(URL(string: "https://api.example.test/"))
        let url = ParentLessonAPI.lessonsImportURL(base: base, familyId: nil)
        XCTAssertEqual(url.path, "/api/v1/family/_/lessons/import")
    }

    func testApproveAndRejectPaths() throws {
        let base = try XCTUnwrap(URL(string: "https://api.example.test"))
        let draftId = "draft-1"
        XCTAssertEqual(
            ParentLessonAPI.lessonDraftApproveURL(base: base, familyId: "fam-x", draftId: draftId).absoluteString,
            "https://api.example.test/api/v1/family/fam-x/lesson-drafts/draft-1/approve"
        )
        XCTAssertEqual(
            ParentLessonAPI.lessonDraftRejectURL(base: base, familyId: "fam-x", draftId: draftId).absoluteString,
            "https://api.example.test/api/v1/family/fam-x/lesson-drafts/draft-1/reject"
        )
    }
}
