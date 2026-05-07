"""V0.6.7 — wire schemas for the parent inbox API."""

from __future__ import annotations

from datetime import datetime  # noqa: TC003 — pydantic needs runtime type
from typing import Any, Literal

from pydantic import BaseModel


class InboxMsgOut(BaseModel):
    msg_id: str
    family_id: str
    parent_user_id: str
    kind: Literal["redemption_request", "weekly_digest", "system"]
    title: str
    body_md: str
    related_resource: dict[str, Any] | None = None
    created_at: datetime
    read_at: datetime | None = None


class InboxListOut(BaseModel):
    items: list[InboxMsgOut]
    unread_count: int
