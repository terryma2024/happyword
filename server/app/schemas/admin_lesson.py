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
    extracted: dict[str, Any]
    edited_extracted: dict[str, Any] | None
    status: Literal["pending", "approved", "rejected"]
    created_at: datetime
    reviewed_at: datetime | None
    reviewer: str | None
    model: str
    prompt_version: int
    approval_summary: dict[str, Any] | None


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
    """Returned from POST /admin/lesson-drafts/{id}/approve."""

    model_config = ConfigDict(extra="forbid")
    created_category: CategoryOut
    created_words: list[dict[str, Any]]
    skipped_words: list[dict[str, Any]]
