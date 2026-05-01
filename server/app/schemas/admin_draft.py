"""Admin LLM-draft schemas (V0.5.4)."""

from datetime import datetime
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field


class DraftOut(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: str
    target_word_id: str
    draft_type: Literal["distractors", "example"]
    status: Literal["pending", "approved", "rejected", "failed"]
    content: dict[str, Any]
    created_at: datetime
    reviewed_at: datetime | None = None
    reviewer: str | None = None
    model: str
    prompt_version: int
    error: str | None = None


class DraftListOut(BaseModel):
    model_config = ConfigDict(extra="forbid")
    items: list[DraftOut]
    total: int
    page: int
    size: int


class DraftPatchIn(BaseModel):
    model_config = ConfigDict(extra="forbid")
    content: dict[str, Any] = Field(...)


class DraftApproveOut(BaseModel):
    """Approve response — surfaces both the persisted draft and the touched word."""

    model_config = ConfigDict(extra="forbid")
    draft: DraftOut
    word_id: str
