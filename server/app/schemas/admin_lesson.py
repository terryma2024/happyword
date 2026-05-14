"""Lesson-import draft + approve shapes (V0.5.5)."""

from datetime import datetime
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field

from app.schemas.admin_category import CategoryOut


class LessonExtractedWord(BaseModel):
    """One word the vision model believes belongs in the new lesson."""

    model_config = ConfigDict(extra="forbid")

    word: str = Field(..., min_length=1, max_length=64)
    meaningZh: str = Field(..., min_length=1, max_length=64)
    difficulty: int = Field(..., ge=1, le=5)


class LessonExtractedOut(BaseModel):
    model_config = ConfigDict(extra="forbid")

    category_id: str
    label_en: str
    label_zh: str
    story_zh: str | None = None
    words: list[LessonExtractedWord]


class LessonDraftOut(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: str
    source_image_url: str
    # V0.7: `extracted` and `model` are populated by the async cron
    # extractor (see app/models/lesson_import_draft.py). They are
    # None while status=="extracting" or "extract_failed".
    extracted: dict[str, Any] | None
    edited_extracted: dict[str, Any] | None
    status: Literal[
        "extracting",
        "pending",
        "approved",
        "rejected",
        "extract_failed",
    ]
    created_at: datetime
    reviewed_at: datetime | None
    reviewer: str | None
    model: str | None
    prompt_version: int
    approval_summary: dict[str, Any] | None
    # Extraction telemetry (V0.7) — exposed so the parent admin UI
    # can show a retry / failure banner for `extract_failed` drafts.
    extract_attempts: int = 0
    extract_last_attempted_at: datetime | None = None
    extract_last_error_code: str | None = None
    extract_last_error_message: str | None = None


class LessonDraftListOut(BaseModel):
    model_config = ConfigDict(extra="forbid")
    items: list[LessonDraftOut]
    total: int
    page: int
    size: int


class LessonDraftPatchIn(BaseModel):
    model_config = ConfigDict(extra="forbid")
    edited_extracted: dict[str, Any]


class LessonApproveOut(BaseModel):
    """Returned from POST /api/v1/family/{family_id}/lesson-drafts/{id}/approve."""

    model_config = ConfigDict(extra="forbid")
    created_category: CategoryOut
    created_words: list[dict[str, Any]]
    skipped_words: list[dict[str, Any]]
