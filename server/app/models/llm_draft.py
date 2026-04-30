"""LLM word-level draft (V0.5.4).

State machine: pending -> approved | rejected. ``failed`` is a terminal
state set when the OpenAI call itself raised — admins re-trigger
generation to produce a fresh pending draft, which keeps the failed row
around for audit / debugging.
"""

from datetime import UTC, datetime
from typing import Annotated, Any, Literal

from beanie import Document, Indexed
from pydantic import Field


def _utcnow() -> datetime:
    return datetime.now(tz=UTC)


DraftStatus = Literal["pending", "approved", "rejected", "failed"]
DraftType = Literal["distractors", "example"]


class LlmDraft(Document):
    # Note: Beanie's `_id` is auto-generated (PydanticObjectId). We let it
    # do its thing here — drafts are short-lived rows; admins identify
    # them via the API-returned id string.
    target_word_id: Annotated[str, Indexed()]
    draft_type: DraftType
    content: dict[str, Any]
    status: Annotated[DraftStatus, Indexed()] = "pending"
    created_at: datetime = Field(default_factory=_utcnow)
    reviewed_at: datetime | None = None
    reviewer: str | None = None
    model: str
    prompt_version: int = 1
    error: str | None = None  # populated when status == "failed"

    class Settings:
        name = "llm_drafts"
