"""V0.6.6 — wire schemas for redemption-request endpoints."""

from __future__ import annotations

from datetime import datetime  # noqa: TC003 — pydantic needs runtime type
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field


class RedemptionRequestCreateIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    wishlist_item_id: Annotated[str, Field(min_length=1, max_length=64)]


class RedemptionDecisionIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    note: Annotated[str | None, Field(default=None, max_length=200)]


class RedemptionRequestOut(BaseModel):
    request_id: str
    child_profile_id: str
    wishlist_item_id: str
    cost_coins_at_request: int
    requested_at: datetime
    status: Literal["pending", "approved", "rejected", "expired"]
    decided_at: datetime | None
    decided_by: str | None
    decision_note: str | None
    expires_at: datetime


class RedemptionRequestListOut(BaseModel):
    items: list[RedemptionRequestOut]


class RedemptionPollOut(BaseModel):
    """Returned from `GET /api/v1/child/redemption-requests/poll`.

    The device shares its last-seen `since_ms` so we only return rows whose
    decision (or expiry) happened after that cursor.
    """

    items: list[RedemptionRequestOut]
    server_now_ms: int
