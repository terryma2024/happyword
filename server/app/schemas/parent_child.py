"""V0.6.2 — child profile + device listing shapes used by the parent web."""

from datetime import datetime

from pydantic import BaseModel


class ChildProfileOut(BaseModel):
    profile_id: str
    family_id: str
    binding_id: str
    nickname: str
    avatar_emoji: str
    created_at: datetime
    updated_at: datetime


class ChildProfileUpdateIn(BaseModel):
    nickname: str | None = None
    avatar_emoji: str | None = None


class DeviceOut(BaseModel):
    binding_id: str
    family_id: str
    device_id: str
    child_profile_id: str
    user_agent: str | None
    created_at: datetime
    last_seen_at: datetime | None
    revoked_at: datetime | None


class DeviceListOut(BaseModel):
    devices: list[DeviceOut]
    total: int
