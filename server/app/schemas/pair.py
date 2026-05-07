"""V0.6.2 — pair flow request / response shapes."""

from datetime import datetime

from pydantic import BaseModel, Field


class PairCreateOut(BaseModel):
    token: str
    short_code: str
    qr_payload_url: str
    expires_at: datetime
    status: str


class PairStatusOut(BaseModel):
    token: str
    short_code: str
    status: str
    expires_at: datetime
    redeemed_at: datetime | None
    redeemed_binding_id: str | None
    cancelled_at: datetime | None


class PairRedeemIn(BaseModel):
    token: str | None = None
    short_code: str | None = None
    device_id: str = Field(min_length=8, max_length=128)


class PairRedeemOut(BaseModel):
    binding_id: str
    family_id: str
    child_profile_id: str
    nickname: str
    avatar_emoji: str
    device_token: str
