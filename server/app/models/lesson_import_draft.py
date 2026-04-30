"""LessonImportDraft (V0.5.5).

A single lesson-import workflow: a textbook photo is uploaded, the
vision model extracts an `extracted` JSON (category metadata + word
list), and an admin reviews / edits / approves it. Approve creates a
Category + batch-upserts Words; reject drops it.

The state machine matches LlmDraft's: pending → approved | rejected.
"""

from datetime import UTC, datetime
from typing import Annotated, Any, Literal

from beanie import Document, Indexed
from pydantic import Field


def _utcnow() -> datetime:
    return datetime.now(tz=UTC)


LessonDraftStatus = Literal["pending", "approved", "rejected"]


class LessonImportDraft(Document):
    source_image_url: str
    extracted: dict[str, Any]
    edited_extracted: dict[str, Any] | None = None
    status: Annotated[LessonDraftStatus, Indexed()] = "pending"
    created_at: datetime = Field(default_factory=_utcnow)
    reviewed_at: datetime | None = None
    reviewer: str | None = None
    model: str
    prompt_version: int = 1
    approval_summary: dict[str, Any] | None = None

    class Settings:
        name = "lesson_import_drafts"
