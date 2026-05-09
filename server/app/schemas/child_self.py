"""V0.6.8 — schemas for the device-side self-edit of child profile."""

from datetime import datetime

from pydantic import BaseModel


class ChildSelfProfileUpdateIn(BaseModel):
    nickname: str
    # When non-empty after strip, replaces avatar_emoji (service caps length).
    avatar_emoji: str | None = None


class ChildSelfProfileOut(BaseModel):
    profile_id: str
    family_id: str
    nickname: str
    avatar_emoji: str
    updated_at: datetime
