"""V0.6.7 — parent inbox message stored alongside the email notification.

Each inbox row backs a single notification surface (currently:
redemption_request / weekly_digest / system). The HTML inbox page
renders unread first, with a read_at timestamp marking dismissals.
"""

from datetime import datetime
from enum import StrEnum
from typing import Annotated, Any

from beanie import Document, Indexed


class ParentInboxKind(StrEnum):
    REDEMPTION_REQUEST = "redemption_request"
    WEEKLY_DIGEST = "weekly_digest"
    SYSTEM = "system"


class ParentInboxMsg(Document):
    msg_id: Annotated[str, Indexed(unique=True)]  # "msg-<8hex>"
    family_id: Annotated[str, Indexed()]
    parent_user_id: str
    kind: ParentInboxKind = ParentInboxKind.SYSTEM
    title: str
    body_md: str  # ≤2KB; rendered with bleach allow-list
    related_resource: dict[str, Any] | None = None
    created_at: datetime
    read_at: datetime | None = None

    class Settings:
        name = "parent_inbox_msgs"
        indexes = [[("parent_user_id", 1), ("read_at", 1), ("created_at", -1)]]
