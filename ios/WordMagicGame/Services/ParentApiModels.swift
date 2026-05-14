import Foundation

extension JSONDecoder {
    static var parentApi: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}

extension JSONEncoder {
    static var parentApi: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }
}

struct ParentStats: Codable, Equatable {
    var userCount: Int
    var wordCount: Int
    var categoryCount: Int
    var packCount: Int
    var latestVersion: Int?
    var lastPublishedAt: String?
    var llmDraftPending: Int
    var lessonImportDraftPending: Int
}

struct ParentPackPublished: Codable, Equatable {
    var version: Int
    var schemaVersion: Int
    var wordCount: Int
    var publishedAt: String
    var publishedBy: String
    var notes: String?
}

enum LessonDraftStatus: String, Codable, Equatable {
    case extracting
    case extractFailed = "extract_failed"
    case pending
    case approved
    case rejected

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        if raw == "pending_review" {
            self = .pending
            return
        }
        guard let value = LessonDraftStatus(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown lesson draft status \(raw)"
            )
        }
        self = value
    }
}

struct LessonExtractedWord: Codable, Equatable, Identifiable {
    var id: String { "\(word)-\(meaningZh)" }
    var word: String
    var meaningZh: String
    var difficulty: Int
}

struct LessonExtracted: Codable, Equatable {
    var categoryId: String
    var labelEn: String
    var labelZh: String
    var storyZh: String?
    var words: [LessonExtractedWord]
}

struct LessonDraft: Codable, Equatable, Identifiable {
    var id: String
    var sourceImageUrl: String
    var extracted: LessonExtracted?
    var editedExtracted: LessonExtracted?
    var status: LessonDraftStatus
    var reviewer: String?
    var model: String?
    var promptVersion: Int
    var createdAt: String
    var reviewedAt: String?
    var extractAttempts: Int?
    var extractLastAttemptedAt: String?
    var extractLastErrorCode: String?
    var extractLastErrorMessage: String?
}

extension LessonDraft {
    var categoryId: String {
        (editedExtracted ?? extracted)?.categoryId ?? "magic-school"
    }

    var categoryLabel: String {
        (editedExtracted ?? extracted)?.labelZh ?? "魔法课程"
    }

    var words: [LessonReviewWord] {
        ((editedExtracted ?? extracted)?.words ?? []).enumerated().map { index, word in
            LessonReviewWord(id: "\(id)-\(index)", word: word.word, meaningZh: word.meaningZh, difficulty: word.difficulty, keep: true)
        }
    }

    static let fixtureReviewedDraft = LessonDraft(
        id: "draft-1",
        sourceImageUrl: "https://example.test/lesson.png",
        extracted: LessonExtracted(
            categoryId: "magic-school",
            labelEn: "Magic School",
            labelZh: "魔法学校",
            storyZh: "今天学习魔法学校里的新单词。",
            words: [
                LessonExtractedWord(word: "wand", meaningZh: "魔杖", difficulty: 1),
                LessonExtractedWord(word: "spell", meaningZh: "咒语", difficulty: 1),
            ]
        ),
        editedExtracted: nil,
        status: .pending,
        reviewer: nil,
        model: "mock",
        promptVersion: 1,
        createdAt: "2026-05-10T08:00:00Z",
        reviewedAt: nil,
        extractAttempts: 1,
        extractLastAttemptedAt: nil,
        extractLastErrorCode: nil,
        extractLastErrorMessage: nil
    )
}

struct LessonDraftListPage: Codable, Equatable {
    var items: [LessonDraft]
    var total: Int
    var page: Int
    var size: Int
}

struct LessonReviewWord: Codable, Equatable, Identifiable {
    var id: String
    var word: String
    var meaningZh: String
    var difficulty: Int
    var keep: Bool
}

struct LessonApprovePayload: Codable, Equatable {
    var categoryId: String
    var labelZh: String
    var words: [LessonReviewWord]
}

struct PickedLessonImage: Equatable {
    var filename: String
    var mimeType: String
    var sizeBytes: Int
}

@MainActor
protocol ParentApiClient {
    func fetchStats() async throws -> ParentStats
    func fetchLessonDrafts() async throws -> LessonDraftListPage
    func fetchLessonDraft(id: String) async throws -> LessonDraft
    func importLessonImage(_ image: PickedLessonImage) async throws -> LessonDraft
    func patchLessonDraft(id: String, payload: LessonApprovePayload) async throws -> LessonDraft
    func approveLessonDraft(id: String) async throws -> ParentPackPublished
    func rejectLessonDraft(id: String) async throws
    func publishPack(notes: String) async throws -> ParentPackPublished
}

struct MockParentApiClient: ParentApiClient {
    func fetchStats() async throws -> ParentStats {
        ParentStats(
            userCount: 1,
            wordCount: 42,
            categoryCount: 5,
            packCount: 3,
            latestVersion: 6,
            lastPublishedAt: "2026-05-10",
            llmDraftPending: 1,
            lessonImportDraftPending: 2
        )
    }

    func fetchLessonDrafts() async throws -> LessonDraftListPage {
        LessonDraftListPage(items: [LessonDraft.fixtureReviewedDraft], total: 1, page: 1, size: 20)
    }

    func fetchLessonDraft(id: String) async throws -> LessonDraft {
        LessonDraft.fixtureReviewedDraft
    }

    func importLessonImage(_ image: PickedLessonImage) async throws -> LessonDraft {
        LessonDraft.fixtureReviewedDraft
    }

    func patchLessonDraft(id: String, payload: LessonApprovePayload) async throws -> LessonDraft {
        LessonDraft.fixtureReviewedDraft
    }

    func approveLessonDraft(id: String) async throws -> ParentPackPublished {
        ParentPackPublished(version: 7, schemaVersion: 5, wordCount: 18, publishedAt: "2026-05-10", publishedBy: "mock-parent", notes: "approved")
    }

    func rejectLessonDraft(id: String) async throws {}

    func publishPack(notes: String) async throws -> ParentPackPublished {
        ParentPackPublished(version: 7, schemaVersion: 5, wordCount: 18, publishedAt: "2026-05-10", publishedBy: "mock-parent", notes: notes)
    }
}
