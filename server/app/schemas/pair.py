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
    # Token may be a 12-char QR prefix (from `/p/<prefix>`, see
    # `pair._qr_payload_url`) or the full 32-char hex token. Keep the
    # schema lenient so unknown token-like values consistently map to the
    # public TOKEN_INVALID contract instead of leaking validation details.
    token: str | None = Field(default=None, min_length=8, max_length=64)
    short_code: str | None = Field(default=None, pattern=r"^[0-9]{6}$")
    device_id: str = Field(min_length=8, max_length=128)


class PairRedeemOut(BaseModel):
    binding_id: str
    family_id: str
    child_profile_id: str
    nickname: str
    avatar_emoji: str
    device_token: str
