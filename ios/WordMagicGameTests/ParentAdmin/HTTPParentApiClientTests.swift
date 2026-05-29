@testable import WordMagicGame
import XCTest

@MainActor
final class HTTPParentApiClientTests: XCTestCase {
    func testFetchLessonDraftsUsesBoundFamilyAndBearerToken() async throws {
        let transport = RecordingParentTransport { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/api/v1/family/fam-live/lesson-drafts")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer device-token")
            XCTAssertEqual(request.url?.urlQueryParameters["status"], "pending")
            return Self.response(request: request, status: 200, body: Self.draftListJSON)
        }
        let client = makeClient(transport: transport)

        let page = try await client.fetchLessonDrafts()

        XCTAssertEqual(page.items.map(\.id), ["draft-live"])
        XCTAssertEqual(page.items[0].words[0].meaningZh, "魔杖")
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testImportLessonImageUploadsMultipartToFamilyImportEndpoint() async throws {
        let transport = RecordingParentTransport { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/v1/family/fam-live/lessons/import")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer device-token")
            XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
            let body = try XCTUnwrap(request.httpBody)
            let text = String(decoding: body, as: UTF8.self)
            XCTAssertTrue(text.contains("name=\"image\"; filename=\"lesson.jpg\""))
            XCTAssertTrue(text.contains("Content-Type: image/jpeg"))
            XCTAssertTrue(text.contains("JPEGDATA"))
            return Self.response(request: request, status: 201, body: Self.extractingDraftJSON)
        }
        let client = makeClient(transport: transport)

        let draft = try await client.importLessonImage(
            PickedLessonImage(
                data: Data("JPEGDATA".utf8),
                filename: "lesson.jpg",
                mimeType: "image/jpeg",
                sizeBytes: 8
            )
        )

        XCTAssertEqual(draft.id, "draft-extracting")
        XCTAssertEqual(draft.status, .extracting)
    }

    func testPatchLessonDraftEncodesServerExpectedEditedExtractedShape() async throws {
        let transport = RecordingParentTransport { request in
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertEqual(request.url?.path, "/api/v1/family/fam-live/lesson-drafts/draft-live")
            let body = try XCTUnwrap(request.httpBody)
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let edited = try XCTUnwrap(json?["edited_extracted"] as? [String: Any])
            XCTAssertEqual(edited["category_id"] as? String, "magic-school")
            XCTAssertEqual(edited["label_zh"] as? String, "魔法学校")
            XCTAssertEqual(edited["story_en"] as? String, "A tiny school door opens for today's magic words.")
            XCTAssertEqual(edited["story_zh"] as? String, "今天学习魔法学校里的新单词。")
            let words = try XCTUnwrap(edited["words"] as? [[String: Any]])
            XCTAssertEqual(words[0]["word"] as? String, "wand")
            XCTAssertEqual(words[0]["meaningZh"] as? String, "魔杖")
            XCTAssertNil(words[0]["meaning_zh"])
            XCTAssertNil(words[0]["keep"])
            return Self.response(request: request, status: 200, body: Self.pendingDraftJSON)
        }
        let client = makeClient(transport: transport)

        _ = try await client.patchLessonDraft(
            id: "draft-live",
            payload: LessonDraft.fixtureReviewedDraft.editedExtractedPayload()
        )
    }

    func testApproveLessonDraftDecodesCreatedWordSummary() async throws {
        let transport = RecordingParentTransport { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/v1/family/fam-live/lesson-drafts/draft-live/approve")
            return Self.response(request: request, status: 200, body: Self.approveJSON)
        }
        let client = makeClient(transport: transport)

        let summary = try await client.approveLessonDraft(id: "draft-live")

        XCTAssertEqual(summary.createdWords.count, 2)
    }

    func testPublishPackPostsToAdminPublishEndpoint() async throws {
        let transport = RecordingParentTransport { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/v1/admin/packs/publish")
            let body = try XCTUnwrap(request.httpBody)
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            XCTAssertEqual(json?["notes"] as? String, "ios smoke")
            return Self.response(request: request, status: 201, body: Self.publishJSON)
        }
        let client = makeClient(transport: transport)

        let published = try await client.publishPack(notes: "ios smoke")

        XCTAssertEqual(published.version, 8)
        XCTAssertEqual(published.wordCount, 42)
    }

    func testImportRequiresBoundFamily() async {
        let client = HTTPParentApiClient(
            baseURLProvider: StaticBackendURLProvider(URL(string: "https://api.example.test")!),
            headerProvider: EmptyHeaderProvider(),
            credentialsProvider: { nil },
            transport: RecordingParentTransport { request in
                XCTFail("Unexpected request: \(request)")
                return Self.response(request: request, status: 500, body: Data())
            }
        )

        do {
            _ = try await client.importLessonImage(
                PickedLessonImage(data: Data("x".utf8), filename: "x.jpg", mimeType: "image/jpeg", sizeBytes: 1)
            )
            XCTFail("Expected missing credentials error")
        } catch ParentApiError.boundFamilyRequired {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeClient(transport: RecordingParentTransport) -> HTTPParentApiClient {
        HTTPParentApiClient(
            baseURLProvider: StaticBackendURLProvider(URL(string: "https://api.example.test")!),
            headerProvider: EmptyHeaderProvider(),
            credentialsProvider: {
                CloudCredentials(
                    bindingId: "binding-live",
                    familyId: "fam-live",
                    childProfileId: "child-live",
                    nickname: "小朋友",
                    avatarEmoji: "star",
                    deviceToken: "device-token",
                    pairedAt: nil,
                    apiBaseURL: nil
                )
            },
            transport: transport
        )
    }

    private static func response(request: URLRequest, status: Int, body: Data) -> (Data, HTTPURLResponse) {
        (
            body,
            HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        )
    }

    private static let draftListJSON = Data("""
    {
      "items": [
        {
          "id": "draft-live",
          "source_image_url": "https://blob/lesson.jpg",
          "status": "pending",
          "prompt_version": 1,
          "created_at": "2026-05-10T08:00:00Z",
          "reviewed_at": null,
          "reviewer": null,
          "model": "gpt-4o",
          "extracted": {
            "category_id": "magic-school",
            "label_en": "Magic School",
            "label_zh": "魔法学校",
            "story_en": "A tiny school door opens for today's magic words.",
            "story_zh": null,
            "words": [
              { "word": "wand", "meaningZh": "魔杖", "difficulty": 1 }
            ]
          },
          "edited_extracted": null
        }
      ],
      "total": 1,
      "page": 1,
      "size": 50
    }
    """.utf8)

    private static let extractingDraftJSON = Data("""
    {
      "id": "draft-extracting",
      "source_image_url": "https://blob/lesson.jpg",
      "status": "extracting",
      "prompt_version": 1,
      "created_at": "2026-05-10T08:00:00Z",
      "reviewed_at": null,
      "reviewer": null,
      "model": null,
      "extracted": null,
      "edited_extracted": null
    }
    """.utf8)

    private static let pendingDraftJSON = Data("""
    {
      "id": "draft-live",
      "source_image_url": "https://blob/lesson.jpg",
      "status": "pending",
      "prompt_version": 1,
      "created_at": "2026-05-10T08:00:00Z",
      "reviewed_at": null,
      "reviewer": null,
      "model": "gpt-4o",
      "extracted": null,
      "edited_extracted": null
    }
    """.utf8)

    private static let approveJSON = Data("""
    {
      "created_category": {
        "id": "lesson-magic-school",
        "label_en": "Magic School",
        "label_zh": "魔法学校",
        "story_en": null,
        "story_zh": null,
        "source": "lesson-import",
        "source_image_url": "https://blob/lesson.jpg",
        "created_at": "2026-05-10T08:00:00Z",
        "updated_at": "2026-05-10T08:00:00Z"
      },
      "created_words": [
        { "id": "wand", "word": "wand", "meaningZh": "魔杖" },
        { "id": "spell", "word": "spell", "meaningZh": "咒语" }
      ],
      "skipped_words": []
    }
    """.utf8)

    private static let publishJSON = Data("""
    {
      "version": 8,
      "schema_version": 5,
      "word_count": 42,
      "published_at": "2026-05-10T08:00:00Z",
      "published_by": "parent",
      "notes": "ios smoke"
    }
    """.utf8)
}

private struct EmptyHeaderProvider: BackendHeaderProviding {
    func headers() -> [String: String] { [:] }
}

private final class RecordingParentTransport: HTTPTransporting, @unchecked Sendable {
    private let handler: (URLRequest) throws -> (Data, HTTPURLResponse)
    private(set) var requests: [URLRequest] = []

    init(handler: @escaping (URLRequest) throws -> (Data, HTTPURLResponse)) {
        self.handler = handler
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        return try handler(request)
    }
}

private extension URL {
    var urlQueryParameters: [String: String] {
        URLComponents(url: self, resolvingAgainstBaseURL: false)?
            .queryItems?
            .reduce(into: [String: String]()) { result, item in result[item.name] = item.value } ?? [:]
    }
}
