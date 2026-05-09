"""V0.6.8 — schemas for the device-side self-edit of child profile."""

from datetime import datetime

from pydantic import BaseModel


class ChildSelfProfileUpdateIn(BaseModel):
    nickname: str


class ChildSelfProfileOut(BaseModel):
    profile_id: str
    family_id: str
    nickname: str
    avatar_emoji: str
    updated_at: datetime
