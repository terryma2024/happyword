"""V0.6.7 — wire schemas for parent account self-service."""

from __future__ import annotations

from datetime import datetime  # noqa: TC003 — pydantic needs runtime type

from pydantic import BaseModel


class AccountStatusOut(BaseModel):
    user_id: str
    email: str
    family_id: str | None
    scheduled_deletion_at: datetime | None
    grace_days_remaining: int = 0


class AccountDeleteOut(BaseModel):
    user_id: str
    scheduled_deletion_at: datetime
    grace_days: int


class AccountCancelDeleteOut(BaseModel):
    user_id: str
    cancelled: bool


class AccountExportOut(BaseModel):
    user_id: str
    family_id: str | None
    items_count: int
    files: list[str]
