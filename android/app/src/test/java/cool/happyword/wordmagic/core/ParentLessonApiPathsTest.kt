package cool.happyword.wordmagic.core

import org.junit.Assert.assertEquals
import org.junit.Test

class ParentLessonApiPathsTest {
    @Test
    fun familySegmentUsesPlaceholderWhenBlank() {
        assertEquals("_", ParentLessonApiPaths.familySegment(null))
        assertEquals("_", ParentLessonApiPaths.familySegment("  "))
    }

    @Test
    fun lessonsImportPathMatchesConvention() {
        val fid = "fam-test"
        assertEquals(
            "/api/v1/family/fam-test/lessons/import",
            ParentLessonApiPaths.lessonsImportPath(fid),
        )
    }

    @Test
    fun lessonDraftApprovePath() {
        assertEquals(
            "/api/v1/family/_/lesson-drafts/d1/approve",
            ParentLessonApiPaths.lessonDraftApprovePath(null, "d1"),
        )
    }
}
