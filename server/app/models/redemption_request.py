"""V0.6.6 — child-initiated redemption request awaiting parent decision.

The flow is:

1. Bound device POSTs `/api/v1/child/redemption-requests { wishlist_item_id }`
   → server creates `RedemptionRequest(status=pending, expires_at=now+7d)`,
   snapshotting the item's current `cost_coins` so a later parent edit
   doesn't change the price after the fact.
2. Parent decides via `/parent/redemption-requests/{id}/{approve,reject}`
   → status flips, decided_at + decided_by + decision_note recorded.
3. Auto-expiry sweep marks any pending row with `expires_at < now` as
   `expired` so polling devices can dismiss the overlay.
"""

from datetime import datetime
from enum import StrEnum
from typing import Annotated

from beanie import Document, Indexed


class RedemptionStatus(StrEnum):
    PENDING = "pending"
    APPROVED = "approved"
    REJECTED = "rejected"
    EXPIRED = "expired"


class RedemptionRequest(Document):
    request_id: Annotated[str, Indexed(unique=True)]  # "rdm-<8hex>"
    child_profile_id: Annotated[str, Indexed()]
    family_id: Annotated[str, Indexed()]
    wishlist_item_id: str
    cost_coins_at_request: int
    requested_at: datetime
    status: RedemptionStatus = RedemptionStatus.PENDING
    decided_at: datetime | None = None
    decided_by: str | None = None  # parent username
    decision_note: str | None = None
    device_binding_id: str
    expires_at: datetime  # requested_at + 7 days

    class Settings:
        name = "redemption_requests"
        indexes = [[("child_profile_id", 1), ("status", 1), ("requested_at", -1)]]
