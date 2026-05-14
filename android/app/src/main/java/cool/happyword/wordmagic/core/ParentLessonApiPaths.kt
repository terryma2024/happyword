package cool.happyword.wordmagic.core

/**
 * Family-scoped lesson import and draft review paths (parity with Harmony `ParentApiClient` and server `family_lessons`).
 *
 * The `family_id` path segment is decorative for now; use the real `fam-…` id when bound and
 * the underscore placeholder when not (see [UNBOUND_FAMILY_SEGMENT]).
 */
object ParentLessonApiPaths {
    const val UNBOUND_FAMILY_SEGMENT = "_"

    fun familySegment(familyId: String?): String {
        val t = familyId?.trim().orEmpty()
        return if (t.isEmpty()) UNBOUND_FAMILY_SEGMENT else t
    }

    fun lessonsImportPath(familyId: String?): String =
        "/api/v1/family/${familySegment(familyId)}/lessons/import"

    fun lessonDraftsPath(familyId: String?): String =
        "/api/v1/family/${familySegment(familyId)}/lesson-drafts"

    fun lessonDraftDetailPath(familyId: String?, draftId: String): String =
        "/api/v1/family/${familySegment(familyId)}/lesson-drafts/${draftId.trim()}"

    fun lessonDraftApprovePath(familyId: String?, draftId: String): String =
        "/api/v1/family/${familySegment(familyId)}/lesson-drafts/${draftId.trim()}/approve"

    fun lessonDraftRejectPath(familyId: String?, draftId: String): String =
        "/api/v1/family/${familySegment(familyId)}/lesson-drafts/${draftId.trim()}/reject"
}
