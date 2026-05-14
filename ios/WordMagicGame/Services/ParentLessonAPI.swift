import Foundation

/// Family-scoped lesson import and draft review URLs (parity with Harmony `ParentApiClient` and server `family_lessons`).
enum ParentLessonAPI {
    /// Path segment when no family id is available yet (matches server / parent web placeholder).
    static let unboundFamilySegment = "_"

    static func familySegment(familyId: String?) -> String {
        let trimmed = familyId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? unboundFamilySegment : trimmed
    }

    static func familyPathSegment(familyId: String?) -> String {
        let raw = familySegment(familyId: familyId)
        return raw.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? raw
    }

    static func lessonsImportURL(base: URL, familyId: String?) -> URL {
        absoluteURL(
            path: "/api/v1/family/\(familyPathSegment(familyId: familyId))/lessons/import",
            base: base
        )
    }

    static func lessonDraftsListURL(
        base: URL,
        familyId: String?,
        status: String? = "pending",
        page: Int = 1,
        size: Int = 50
    ) -> URL {
        guard var components = URLComponents(
            url: absoluteURL(
                path: "/api/v1/family/\(familyPathSegment(familyId: familyId))/lesson-drafts",
                base: base
            ),
            resolvingAgainstBaseURL: false
        ) else {
            preconditionFailure("Invalid lesson-drafts URL for base \(base)")
        }
        var items: [URLQueryItem] = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "size", value: String(size)),
        ]
        if let status, !status.isEmpty {
            items.append(URLQueryItem(name: "status", value: status))
        }
        components.queryItems = items
        guard let url = components.url else {
            preconditionFailure("Invalid lesson-drafts query for base \(base)")
        }
        return url
    }

    static func lessonDraftDetailURL(base: URL, familyId: String?, draftId: String) -> URL {
        let encodedDraft = draftId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? draftId
        return absoluteURL(
            path: "/api/v1/family/\(familyPathSegment(familyId: familyId))/lesson-drafts/\(encodedDraft)",
            base: base
        )
    }

    static func lessonDraftPatchURL(base: URL, familyId: String?, draftId: String) -> URL {
        lessonDraftDetailURL(base: base, familyId: familyId, draftId: draftId)
    }

    static func lessonDraftApproveURL(base: URL, familyId: String?, draftId: String) -> URL {
        let encodedDraft = draftId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? draftId
        return absoluteURL(
            path: "/api/v1/family/\(familyPathSegment(familyId: familyId))/lesson-drafts/\(encodedDraft)/approve",
            base: base
        )
    }

    static func lessonDraftRejectURL(base: URL, familyId: String?, draftId: String) -> URL {
        let encodedDraft = draftId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? draftId
        return absoluteURL(
            path: "/api/v1/family/\(familyPathSegment(familyId: familyId))/lesson-drafts/\(encodedDraft)/reject",
            base: base
        )
    }

    private static func absoluteURL(path: String, base: URL) -> URL {
        URL(string: path, relativeTo: base)?.absoluteURL
            ?? base.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }
}
