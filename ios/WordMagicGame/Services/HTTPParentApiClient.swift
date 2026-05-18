import Foundation

enum ParentApiError: Error, Equatable {
    case boundFamilyRequired
    case imageTooLarge(Int)
    case unsupportedMimeType(String)
    case invalidResponse
    case unexpectedStatus(Int, String)
}

struct HTTPParentApiClient: ParentApiClient {
    private static let maxImageBytes = 4_500_000
    private static let allowedMimeTypes: Set<String> = ["image/jpeg", "image/png", "image/webp"]

    private let baseURLProvider: any BackendURLProviding
    private let headerProvider: any BackendHeaderProviding
    private let credentialsProvider: @MainActor () -> CloudCredentials?
    private let transport: any HTTPTransporting
    private let decoder = JSONDecoder.parentApi

    init(
        baseURLProvider: any BackendURLProviding = BackendURLProvider(),
        headerProvider: any BackendHeaderProviding = BackendHeaderProvider(),
        credentialsProvider: @escaping @MainActor () -> CloudCredentials?,
        transport: any HTTPTransporting = URLSessionHTTPTransport()
    ) {
        self.baseURLProvider = baseURLProvider
        self.headerProvider = headerProvider
        self.credentialsProvider = credentialsProvider
        self.transport = transport
    }

    func fetchStats() async throws -> ParentStats {
        var request = URLRequest(url: endpoint("/api/v1/admin/stats"))
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        headerProvider.apply(to: &request)
        let data = try await send(request, expectedStatuses: [200])
        return try decoder.decode(ParentStats.self, from: data)
    }

    func fetchLessonDrafts() async throws -> LessonDraftListPage {
        let credentials = try boundCredentials()
        var request = URLRequest(
            url: ParentLessonAPI.lessonDraftsListURL(
                base: baseURL(for: credentials),
                familyId: credentials.familyId,
                status: "pending",
                page: 1,
                size: 50
            )
        )
        request.httpMethod = "GET"
        applyJSONHeaders(to: &request, credentials: credentials)
        let data = try await send(request, expectedStatuses: [200])
        return try decoder.decode(LessonDraftListPage.self, from: data)
    }

    func fetchLessonDraft(id: String) async throws -> LessonDraft {
        let credentials = try boundCredentials()
        var request = URLRequest(url: ParentLessonAPI.lessonDraftDetailURL(base: baseURL(for: credentials), familyId: credentials.familyId, draftId: id))
        request.httpMethod = "GET"
        applyJSONHeaders(to: &request, credentials: credentials)
        let data = try await send(request, expectedStatuses: [200])
        return try decoder.decode(LessonDraft.self, from: data)
    }

    func importLessonImage(_ image: PickedLessonImage) async throws -> LessonDraft {
        guard image.sizeBytes <= Self.maxImageBytes else {
            throw ParentApiError.imageTooLarge(image.sizeBytes)
        }
        let mimeType = image.mimeType.lowercased()
        guard Self.allowedMimeTypes.contains(mimeType) else {
            throw ParentApiError.unsupportedMimeType(image.mimeType)
        }
        let credentials = try boundCredentials()
        let multipart = MultipartImageBody(
            fieldName: "image",
            filename: image.filename.isEmpty ? "lesson.jpg" : image.filename,
            mimeType: mimeType,
            data: image.data
        )
        var request = URLRequest(url: ParentLessonAPI.lessonsImportURL(base: baseURL(for: credentials), familyId: credentials.familyId))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(multipart.boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(credentials.deviceToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = multipart.body
        request.timeoutInterval = 180
        headerProvider.apply(to: &request)
        let data = try await send(request, expectedStatuses: [200, 201])
        return try decoder.decode(LessonDraft.self, from: data)
    }

    func patchLessonDraft(id: String, payload: LessonEditPayload) async throws -> LessonDraft {
        let credentials = try boundCredentials()
        var request = URLRequest(url: ParentLessonAPI.lessonDraftPatchURL(base: baseURL(for: credentials), familyId: credentials.familyId, draftId: id))
        request.httpMethod = "PUT"
        applyJSONHeaders(to: &request, credentials: credentials)
        request.httpBody = try JSONEncoder().encode(LessonDraftPatchRequest(payload: payload))
        let data = try await send(request, expectedStatuses: [200])
        return try decoder.decode(LessonDraft.self, from: data)
    }

    func approveLessonDraft(id: String) async throws -> LessonApproveSummary {
        let credentials = try boundCredentials()
        var request = URLRequest(url: ParentLessonAPI.lessonDraftApproveURL(base: baseURL(for: credentials), familyId: credentials.familyId, draftId: id))
        request.httpMethod = "POST"
        applyJSONHeaders(to: &request, credentials: credentials)
        request.httpBody = Data("{}".utf8)
        let data = try await send(request, expectedStatuses: [200])
        return try decoder.decode(LessonApproveSummary.self, from: data)
    }

    func rejectLessonDraft(id: String) async throws {
        let credentials = try boundCredentials()
        var request = URLRequest(url: ParentLessonAPI.lessonDraftRejectURL(base: baseURL(for: credentials), familyId: credentials.familyId, draftId: id))
        request.httpMethod = "POST"
        applyJSONHeaders(to: &request, credentials: credentials)
        request.httpBody = Data("{}".utf8)
        _ = try await send(request, expectedStatuses: [200])
    }

    func publishPack(notes: String) async throws -> ParentPackPublished {
        var request = URLRequest(url: endpoint("/api/v1/admin/packs/publish"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        request.httpBody = try JSONSerialization.data(withJSONObject: trimmed.isEmpty ? [:] : ["notes": trimmed])
        headerProvider.apply(to: &request)
        let data = try await send(request, expectedStatuses: [200, 201])
        return try decoder.decode(ParentPackPublished.self, from: data)
    }

    private func endpoint(_ path: String) -> URL {
        URL(string: path, relativeTo: baseURLProvider.effectiveBaseURL())?.absoluteURL
            ?? baseURLProvider.effectiveBaseURL().appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }

    private func baseURL(for credentials: CloudCredentials) -> URL {
        credentials.apiBaseURL.flatMap(URL.init(string:)) ?? baseURLProvider.effectiveBaseURL()
    }

    private func boundCredentials() throws -> CloudCredentials {
        guard let credentials = credentialsProvider(),
              !credentials.familyId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw ParentApiError.boundFamilyRequired
        }
        return credentials
    }

    private func applyJSONHeaders(to request: inout URLRequest, credentials: CloudCredentials) {
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(credentials.deviceToken)", forHTTPHeaderField: "Authorization")
        headerProvider.apply(to: &request)
    }

    private func send(_ request: URLRequest, expectedStatuses: Set<Int>) async throws -> Data {
        let (data, response) = try await transport.data(for: request)
        guard expectedStatuses.contains(response.statusCode) else {
            throw ParentApiError.unexpectedStatus(response.statusCode, String(decoding: data, as: UTF8.self))
        }
        return data
    }
}

private struct LessonDraftPatchRequest: Encodable {
    var editedExtracted: LessonPatchExtracted

    init(payload: LessonEditPayload) {
        editedExtracted = LessonPatchExtracted(payload: payload)
    }

    private enum CodingKeys: String, CodingKey {
        case editedExtracted = "edited_extracted"
    }
}

private struct LessonPatchExtracted: Encodable {
    var categoryId: String
    var labelEn: String
    var labelZh: String
    var storyZh: String?
    var words: [LessonPatchWord]

    init(payload: LessonEditPayload) {
        categoryId = payload.categoryId
        labelEn = payload.labelEn
        labelZh = payload.labelZh
        storyZh = payload.storyZh
        words = payload.words.map { LessonPatchWord(word: $0.word, meaningZh: $0.meaningZh, difficulty: $0.difficulty) }
    }

    private enum CodingKeys: String, CodingKey {
        case categoryId = "category_id"
        case labelEn = "label_en"
        case labelZh = "label_zh"
        case storyZh = "story_zh"
        case words
    }
}

private struct LessonPatchWord: Encodable {
    var word: String
    var meaningZh: String
    var difficulty: Int
}

private struct MultipartImageBody {
    let boundary = "Boundary-\(UUID().uuidString)"
    let body: Data

    init(fieldName: String, filename: String, mimeType: String, data: Data) {
        var result = Data()
        result.appendString("--\(boundary)\r\n")
        result.appendString("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(filename)\"\r\n")
        result.appendString("Content-Type: \(mimeType)\r\n\r\n")
        result.append(data)
        result.appendString("\r\n--\(boundary)--\r\n")
        body = result
    }
}

private extension Data {
    mutating func appendString(_ value: String) {
        append(Data(value.utf8))
    }
}
