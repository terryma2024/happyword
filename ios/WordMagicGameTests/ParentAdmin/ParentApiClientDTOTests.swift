@testable import WordMagicGame
import XCTest

final class ParentApiClientDTOTests: XCTestCase {
    func testDecodesStatsDraftListAndPublishResponse() throws {
        let decoder = JSONDecoder.parentApi

        let stats = try decoder.decode(ParentStats.self, from: Self.statsJSON)
        XCTAssertEqual(stats.wordCount, 42)
        XCTAssertEqual(stats.lessonImportDraftPending, 2)

        let drafts = try decoder.decode(LessonDraftListPage.self, from: Self.draftsJSON)
        XCTAssertEqual(drafts.items.count, 1)
        XCTAssertEqual(drafts.items[0].status, .pendingReview)

        let published = try decoder.decode(ParentPackPublished.self, from: Self.publishJSON)
        XCTAssertEqual(published.version, 7)
        XCTAssertEqual(published.wordCount, 18)
    }

    private static let statsJSON = Data("""
    {
      "user_count": 3,
      "word_count": 42,
      "category_count": 5,
      "pack_count": 4,
      "latest_version": 6,
      "last_published_at": "2026-05-10T08:00:00Z",
      "llm_draft_pending": 1,
      "lesson_import_draft_pending": 2
    }
    """.utf8)

    private static let draftsJSON = Data("""
    {
      "items": [
        {
          "id": "draft-1",
          "source_image_url": "https://example.test/lesson.png",
          "status": "pending_review",
          "prompt_version": 1,
          "created_at": "2026-05-10T08:00:00Z",
          "extracted": {
            "category_id": "magic-school",
            "label_en": "Magic School",
            "label_zh": "魔法学校",
            "words": [
              { "word": "wand", "meaning_zh": "魔杖", "difficulty": 1 }
            ]
          }
        }
      ],
      "total": 1,
      "page": 1,
      "size": 20
    }
    """.utf8)

    private static let publishJSON = Data("""
    {
      "version": 7,
      "schema_version": 5,
      "word_count": 18,
      "published_at": "2026-05-10T08:00:00Z",
      "published_by": "parent",
      "notes": "lesson import mock"
    }
    """.utf8)
}
