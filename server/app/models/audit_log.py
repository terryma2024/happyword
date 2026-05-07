"""V0.6.7 — append-only audit trail for sensitive write actions.

Indexed on (actor_id, ts desc) for "who did what" lookups, and on
(action, ts desc) for "what happened recently" reports. Payload
summary is capped to ~512 bytes by the writer; the document layer
just persists whatever the service supplies.
"""

from datetime import datetime
from enum import StrEnum
from typing import Annotated, Any

from beanie import Document, Indexed


class ActorRole(StrEnum):
    ADMIN = "admin"
    PARENT = "parent"
    DEVICE = "device"
    SYSTEM = "system"


class AuditLog(Document):
    actor_role: ActorRole = ActorRole.SYSTEM
    actor_id: str | None = None
    action: Annotated[str, Indexed()]  # "parent.login", "redemption.approve", ...
    target_collection: str | None = None
    target_id: str | None = None
    payload_summary: dict[str, Any] | None = None
    ts: datetime

    class Settings:
        name = "audit_log"
        indexes = [[("actor_id", 1), ("ts", -1)], [("action", 1), ("ts", -1)]]
